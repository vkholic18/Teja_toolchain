#!/bin/bash
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# This bash script calls upload_to_cos.py.
# arg1 = path to json file containing the COS credentials to allow uploading
# arg2 = output directory for new ffsld

source ${PATH_TO_GENCTL_CI}/scripts/retry.sh

echo "upload to cos started"

FFSLD_OUTPUT_DIR=$1
COMPONENT="genesis-deploy-artifacts"

# REGION is a placeholder and should be replaced on run time with the bucket-endpoint
COS_ENDPOINT_TEMPLATE="https://s3.REGION.cloud-object-storage.appdomain.cloud/"
COS_UPLOAD_CONTENT_ROOT="${FFSLD_OUTPUT_DIR}"

retry python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/upload_cos_requirements.txt

function upload_to_cos() {
  if [ "$#" -ne 4 ]; then
    echo "ERROR: ${FUNCNAME[0]} requires 5 arguments but got $#. Please pass in the correct arguments."
    exit 1
  fi
  bucket_name=$1
  base_dir_file=$2
  destination=$3
  endpoint_url=$4
  echo "Uploading to COS"
  echo "Upload info : Bucket name=\"${bucket_name}\" Base directory name=\"${base_dir_file}\" Destination=\"${destination}\" Endpoint URL=\"${endpoint_url}\""
  python3 ${PATH_TO_GENCTL_CI}/scripts/upload_to_cos.py "${bucket_name}" "${base_dir_file}" "${destination}" --cos-endpoint-url "${endpoint_url}"
}

if [ "$#" -ne 1 ]; then
  echo "ERROR: ${FUNCNAME[0]} requires 2 arguments but got $#. Please pass in the correct arguments."
  exit 1
fi

echo "ffsld_upload_to_cos.sh: ${PWD}"

echo "DEBUG: Show featureflagsetld YAML before upload."
find ${COS_UPLOAD_CONTENT_ROOT} -name featureflagsetld.yaml -type f -print -exec  cat {} \;
echo "DEBUG: -----------------------------------------"

# Upload new ffsld files to COS
if [ -d "${COS_UPLOAD_CONTENT_ROOT}" ]; then
# Check if COS bucket list was defined - allows to upload to multiple buckets
    endpoint_url="https://s3.us-south.cloud-object-storage.appdomain.cloud/"
    echo "Artifact will be pushed to:"
    echo "vpc-featureflagsets"
    echo ${endpoint_url}
    upload_to_cos "vpc-featureflagsets" "${COS_UPLOAD_CONTENT_ROOT}" "${COMPONENT}" "${endpoint_url}"
else
  echo "Warning: COS files directory does not exist."
  echo ${COS_UPLOAD_CONTENT_ROOT}
fi
