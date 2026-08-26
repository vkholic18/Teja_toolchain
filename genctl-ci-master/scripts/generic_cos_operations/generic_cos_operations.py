#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

"""
Generic script to upload/download files to/from IBM Cloud Object Storage (COS)
Usage:
    # Upload
    python3 generic_cos_operations.py upload <file_path> <destination_path>
    
    # Download
    python3 generic_cos_operations.py download <source_path> <local_file_path>
    
    # Upload a file
    python3 generic_cos_operations.py upload report.html zap-results/2024-01-15/result.html
    
    # Download a file
    python3 generic_cos_operations.py download zap-results/2024-01-15/result.html downloaded-report.html
    
    # Dry run (no actual upload/download)
    python3 generic_cos_operations.py upload report.html results/report.html --dry-run
"""

import os
import sys
import logging
import argparse
import ibm_boto3
from ibm_botocore.client import Config, ClientError


def setup_logger():
    """Setup logging configuration"""
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    return logger


def validate_environment():
    """Validate required environment variables"""
    logger = logging.getLogger()

    cos_api_key = os.getenv("COS_API_KEY")
    if not cos_api_key:
        logger.error("COS_API_KEY environment variable is not set")
        sys.exit(1)

    bucket_name = os.getenv("COS_BUCKET_NAME", "vpc-ci-storage")
    endpoint = os.getenv("COS_ENDPOINT", "https://s3.eu-gb.cloud-object-storage.appdomain.cloud")

    logger.info(f"Using bucket: {bucket_name}")
    logger.info(f"Using endpoint: {endpoint}")

    return cos_api_key, bucket_name, endpoint


def get_cos_client(api_key, endpoint):
    """Create and return IBM COS client"""
    logger = logging.getLogger()

    try:
        cos_client = ibm_boto3.client(
            's3',
            ibm_api_key_id=api_key,
            config=Config(signature_version='oauth'),
            endpoint_url=endpoint
        )
        logger.info("Successfully connected to IBM COS")
        return cos_client
    except Exception as e:
        logger.error(f"Failed to create COS client: {e}")
        sys.exit(1)


def upload_file(cos_client, bucket_name, file_path, destination_path, dry_run=False):
    """
    Upload a file to IBM COS
    
    Args:
        cos_client: IBM COS client object
        bucket_name: Name of the COS bucket
        file_path: Local file path to upload
        destination_path: Destination path in the bucket
        dry_run: If True, simulate upload without actually uploading
    """
    logger = logging.getLogger()

    # Check if file exists
    if not os.path.isfile(file_path):
        logger.error(f"File not found: {file_path}")
        sys.exit(1)

    file_size = os.path.getsize(file_path)
    logger.info(f"File to upload: {file_path} ({file_size} bytes)")
    logger.info(f"Destination: s3://{bucket_name}/{destination_path}")

    if dry_run:
        logger.info("🔍 DRY RUN MODE - No actual upload will be performed")
        logger.info(f"Would upload: {file_path} -> s3://{bucket_name}/{destination_path}")
        logger.info(f"File size: {file_size} bytes")
        return True

    try:
        # Upload the file
        logger.info("Starting upload...")
        with open(file_path, 'rb') as file_data:
            cos_client.upload_fileobj(
                Fileobj=file_data,
                Bucket=bucket_name,
                Key=destination_path
            )

        logger.info(f"Successfully uploaded to s3://{bucket_name}/{destination_path}")
        return True

    except ClientError as ce:
        logger.error(f"Client error during upload: {ce}")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Failed to upload file: {e}")
        sys.exit(1)


def verify_upload(cos_client, bucket_name, destination_path, dry_run=False):
    """Verify that the file was uploaded successfully"""
    logger = logging.getLogger()

    if dry_run:
        logger.info("🔍 DRY RUN MODE - Skipping verification")
        return True

    try:
        response = cos_client.head_object(Bucket=bucket_name, Key=destination_path)
        logger.info(f"Verified: File exists in bucket (Size: {response['ContentLength']} bytes)")
        return True
    except ClientError as e:
        if e.response['Error']['Code'] == '404':
            logger.error("✗ Verification failed: File not found in bucket")
        else:
            logger.error(f"✗ Verification failed: {e}")
        return False


def download_file(cos_client, bucket_name, source_path, local_base_path, dry_run=False):
    """
    Download a file or directory from IBM COS
    
    Args:
        cos_client: IBM COS client object
        bucket_name: Name of the COS bucket
        source_path: Source path in the bucket (file or directory prefix)
        local_base_path: Local base path to save downloaded files
        dry_run: If True, simulate download without actually downloading
    """
    logger = logging.getLogger()

    # Normalize source path (remove trailing slash if present)
    source_path = source_path.rstrip('/')

    # Check if source_path is a directory (prefix) or a single file
    try:
        # Try to list objects with this prefix
        paginator = cos_client.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=bucket_name, Prefix=source_path)

        files_to_download = []
        for page in pages:
            if 'Contents' in page:
                for obj in page['Contents']:
                    # Skip if it's just the directory marker itself
                    if not obj['Key'].endswith('/'):
                        files_to_download.append(obj['Key'])

        if not files_to_download:
            # No files found with prefix, try as single file
            try:
                cos_client.head_object(Bucket=bucket_name, Key=source_path)
                files_to_download = [source_path]
            except ClientError:
                logger.error(f"No files found at: s3://{bucket_name}/{source_path}")
                sys.exit(1)

        # Download all files
        downloaded_count = 0
        for file_key in files_to_download:
            # Determine local file path preserving directory structure
            if file_key.startswith(source_path):
                # Remove the source_path prefix to get relative path
                relative_path = file_key[len(source_path):].lstrip('/')
                if not relative_path:
                    # File is exactly the source_path
                    local_file_path = local_base_path
                else:
                    local_file_path = os.path.join(local_base_path, relative_path)
            else:
                local_file_path = os.path.join(local_base_path, os.path.basename(file_key))

            if dry_run:
                logger.info(f"DRY RUN: Would download s3://{bucket_name}/{file_key} -> {local_file_path}")
                downloaded_count += 1
                continue

            # Create directory if it doesn't exist
            local_dir = os.path.dirname(local_file_path)
            if local_dir and not os.path.exists(local_dir):
                os.makedirs(local_dir)

            # Download the file
            try:
                with open(local_file_path, 'wb') as file_data:
                    cos_client.download_fileobj(
                        Bucket=bucket_name,
                        Key=file_key,
                        Fileobj=file_data
                    )
                logger.info(f"Downloaded: {local_file_path}")
                downloaded_count += 1
            except Exception as e:
                logger.error(f"Failed to download {file_key}: {e}")
                sys.exit(1)

        if dry_run:
            logger.info(f"DRY RUN: Would download {downloaded_count} file(s)")
        else:
            logger.info(f"Downloaded {downloaded_count} file(s)")

        return True

    except ClientError as ce:
        logger.error(f"Client error during download: {ce}")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Failed to download: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Upload or download files to/from IBM Cloud Object Storage",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment Variables:
  COS_API_KEY       IBM Cloud API key (required)
  COS_BUCKET_NAME   COS bucket name (default: vpc-ci-storage)
  COS_ENDPOINT      COS endpoint URL (default: https://s3.eu-gb.cloud-object-storage.appdomain.cloud)
Examples:
  # Upload a file
  python3 generic_upload_to_cos.py upload report.html zap-results/2024-01-15/report.html
  
  # Download a file
  python3 generic_upload_to_cos.py download zap-results/2024-01-15/report.html downloaded-report.html
  
  # Dry run (simulate without actual operation)
  python3 generic_upload_to_cos.py upload report.html results/report.html --dry-run
  python3 generic_upload_to_cos.py download results/report.html local-report.html --dry-run
  
  # Skip verification (upload only)
  python3 generic_upload_to_cos.py upload report.html results/report.html --no-verify
        """
    )

    parser.add_argument(
        "operation",
        choices=["upload", "download"],
        help="Operation to perform: upload or download"
    )

    parser.add_argument(
        "source",
        help="Source: local file path (for upload) or COS path (for download)"
    )

    parser.add_argument(
        "destination",
        help="Destination: COS path (for upload) or local file path (for download)"
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Simulate operation without actually performing it"
    )

    parser.add_argument(
        "--no-verify",
        action="store_true",
        help="Skip verification after upload (upload only)"
    )

    args = parser.parse_args()

    # Setup logging
    logger = setup_logger()

    logger.info("=" * 70)
    logger.info(f"Generic COS {args.operation.upper()} Script")
    if args.dry_run:
        logger.info("🔍 DRY RUN MODE ENABLED")
    logger.info("=" * 70)

    # Validate environment and get credentials
    api_key, bucket_name, endpoint = validate_environment()

    # Create COS client
    cos_client = get_cos_client(api_key, endpoint)

    # Perform operation
    if args.operation == "upload":
        # Upload file
        upload_file(cos_client, bucket_name, args.source, args.destination, dry_run=args.dry_run)

        # Verify upload unless --no-verify is specified
        if not args.no_verify:
            verify_upload(cos_client, bucket_name, args.destination, dry_run=args.dry_run)

    elif args.operation == "download":
        # Download file
        download_file(cos_client, bucket_name, args.source, args.destination, dry_run=args.dry_run)

    logger.info("=" * 70)
    if args.dry_run:
        logger.info(f"Dry run completed successfully! (No actual {args.operation} performed)")
    else:
        logger.info(f"{args.operation.capitalize()} completed successfully!")
    logger.info("=" * 70)


if __name__ == "__main__":
    main()
    