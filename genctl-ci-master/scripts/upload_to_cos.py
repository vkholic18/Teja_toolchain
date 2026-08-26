#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# Description:
#    Search files in the base_file_dir directory
#    and upload them on IBM COS under given bucket/component/GIT_SHA folder

#
# Inputs:
#     positional arguments:
#     bucket_name           IBM COS bucket name ; e.g.development-workspace-artifacts
#     base_file_dir         base directory name to search the files in; e.g./Users/develop/genesis/prod/regional-group-workspace/hack/deploy/razee/
#     destination           workspace/config-hash-folder directory name in the bucket for upload files; e.g.regional-group-workspace/b1ebb7924868369c4dbd7e0f0aaf74c747d11111/
#
#     optional arguments:
#     -h, --help            show this help message and exit
#     --cos-service-credentials COS_SERVICE_CREDENTIALS
#     IBM COS service credentials json. If skipped get it from environment variable COS_SERVICE_CREDENTIALS
#     --cos-endpoint-url COS_ENDPOINT_URL
#     IBM COS end point. default: https://s3.us-south.cloud-object-storage.appdomain.cloud/
#     --cos-auth-endpoint-url COS_AUTH_ENDPOINT_URL
#     IBM COS authentication end point. default: https://iam.cloud.ibm.com/identity/token/
#     --cos-upload-filter COS_UPLOAD_FILTER
#     regex filter to search and upload files match the pattern. e.g "\.json$" only *.json files will be uploaded


import logging
import ibm_boto3
import os
import sys
from ibm_botocore.client import Config, ClientError
import json
import argparse
import re


def setup_logger():
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    return logger

def multi_part_upload(cos_client, bucket_name, item_name, file_path):
    logger = logging.getLogger()
    try:
        logger.info(f"Starting file transfer for {item_name} to bucket: {bucket_name}\n")
        # set 5 MB chunks
        part_size = 1024 * 1024 * 5

        # set threadhold to 15 MB
        file_threshold = 1024 * 1024 * 15

        # set the transfer threshold and chunk size
        transfer_config = ibm_boto3.s3.transfer.TransferConfig(
            multipart_threshold=file_threshold,
            multipart_chunksize=part_size
        )

        # the upload_fileobj method will automatically execute a multi-part upload
        # in 5 MB chunks for all files over 15 MB

        with open(file_path, "rb") as file_data:
            cos_client.Object(bucket_name, item_name).upload_fileobj(
                Fileobj=file_data,
                Config=transfer_config
            )
        logger.info(f"Transfer for {item_name} Complete!\n")
    except ClientError as be:
        logger.error(f"CLIENT ERROR: {be}\n")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unable to complete multi-part upload: {e}")
        sys.exit(1)

def normalize_path(path):
    #search for double or more slashes and replase ot to a single slash
    return re.sub("\/{2,}", '/', path)

def envconfig(args):
    if not args.cos_service_credentials:
        args.cos_service_credentials = os.getenv("COS_SERVICE_CREDENTIALS")

def main():
    parser = argparse.ArgumentParser(
        description="upload files on IBM COS"
    )
    # global flags
    parser.add_argument(
        "bucket_name",
        help=(
            "IBM COS bucket name ; e.g."
            "development-workspace-artifacts"
        ),
    )
    parser.add_argument(
        "base_file_dir",
        help=(
            "base directory name to search the files in; e.g."
            "/Users/develop/genesis/prod/regional-group-workspace"
        ),
    )
    parser.add_argument(
        "destination",
        help=(
            "workspace/config-hash-folder directory name in the bucket for upload files; e.g."
            "regional-group-workspace/b1ebb7924868369c4dbd7e0f0aaf74c747d11111/"
        ),
    )
    parser.add_argument(
        "--cos-service-credentials",
        help=(
            "IBM COS service credentials json. "
            "If skipped get it from environment variable COS_SERVICE_CREDENTIALS"
        ),
    )
    parser.add_argument(
        "--cos-endpoint-url",
        default="https://s3.us-south.cloud-object-storage.appdomain.cloud/",
        help="IBM COS end point. default: https://s3.us-south.cloud-object-storage.appdomain.cloud/ ",
    )
    parser.add_argument(
        "--cos-auth-endpoint-url",
        default="https://iam.cloud.ibm.com/identity/token/",
        help="IBM COS authentication end point. default: https://iam.cloud.ibm.com/identity/token/",
    )
    parser.add_argument(
        "--cos-upload-filter",
        help=(
            "regex filter to search and upload files match the pattern. "
            "e.g \"\.json$\" only *.json files will be uploaded"
        ),
    )
    # parse args and run the subcommand
    args = parser.parse_args()
    envconfig(args)  # get some defaults from the environment
    logger = setup_logger()
    cos_creds = json.loads(args.cos_service_credentials)
    logger.info(f"iam apikey name {cos_creds['iam_apikey_name']}\n")

    cos_client = ibm_boto3.resource('s3',
                                    ibm_api_key_id=cos_creds['apikey'],
                                    ibm_service_instance_id=cos_creds['resource_instance_id'],
                                    ibm_auth_endpoint=args.cos_auth_endpoint_url,
                                    config=Config(signature_version="oauth"),
                                    endpoint_url=args.cos_endpoint_url)

    file_filter = args.cos_upload_filter
    logger.info(f"Upload filter: {file_filter} ")
    for root, directories, filenames in os.walk(args.base_file_dir):
        for filename in filenames:
            if file_filter:
                FILE_PATTERN = re.compile(file_filter)
                if  bool(FILE_PATTERN.search(filename)) == False:
                    #skip filename
                    continue
            config_file_full_name = os.path.join(root,filename)
            logger.info(f"Source file for upload: {config_file_full_name} ")
            head, config_file = config_file_full_name.split(args.base_file_dir)
            destination = normalize_path(args.destination + "/" + config_file)
            multi_part_upload(cos_client, args.bucket_name, destination, config_file_full_name)

if __name__ == "__main__":
    main()