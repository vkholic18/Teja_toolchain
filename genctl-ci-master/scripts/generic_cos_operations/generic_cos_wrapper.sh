#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2026
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# Wrapper script for generic_cos_operations.py
# Simplifies uploading/downloading files to/from IBM Cloud Object Storage

# Required Environment Variables:
#   COS_API_KEY         - IBM Cloud API key for COS authentication
#   COS_BUCKET_NAME     - COS bucket name (default: vpc-ci-storage)
#   COS_ENDPOINT        - COS endpoint URL (default: https://s3.eu-gb.cloud-object-storage.appdomain.cloud)
#
# Optional Environment Variables:
#   PATH_TO_GENCTL_CI   - Path to genctl-ci repo (default: current directory)
#   DRY_RUN             - Set to "true" to simulate operation without actually performing it
#   NO_VERIFY           - Set to "true" to skip verification after upload (upload only)

# Usage:
#   ./generic_cos_wrapper.sh <operation> <source> <destination>
#
# Examples:
#   # Upload a file
#   ./generic_cos_wrapper.sh upload report.html zap-results/2024-01-15/report.html
#
#   # Download a file
#   ./generic_cos_wrapper.sh download zap-results/2024-01-15/report.html downloaded-report.html
#
#   # Dry run
#   DRY_RUN=true ./generic_cos_wrapper.sh upload report.html results/report.html
#
#   # Skip verification (upload only)
#   NO_VERIFY=true ./generic_cos_wrapper.sh upload report.html results/report.html

set -e

# Set defaults
PATH_TO_GENCTL_CI=${PATH_TO_GENCTL_CI:-$(pwd)}
DRY_RUN=${DRY_RUN:-"false"}
NO_VERIFY=${NO_VERIFY:-"false"}

# Validate required arguments
if [ "$#" -lt 3 ]; then
    echo "ERROR: This script requires 3 arguments: <operation> <source> <destination>" >&2
    echo "" >&2
    echo "Usage:" >&2
    echo "  $0 <operation> <source> <destination>" >&2
    echo "" >&2
    echo "Operations:" >&2
    echo "  upload   - Upload a file to COS" >&2
    echo "  download - Download a file from COS" >&2
    exit 1
fi

OPERATION=$1
SOURCE=$2
DESTINATION=$3

# Validate operation
if [[ "${OPERATION}" != "upload" && "${OPERATION}" != "download" ]]; then
    echo "ERROR: Invalid operation '${OPERATION}'. Must be 'upload' or 'download'" >&2
    exit 1
fi

# Validate required environment variables
if [[ -z "${COS_API_KEY}" ]]; then
    echo "ERROR: COS_API_KEY environment variable is not set" >&2
    exit 1
fi

# Set defaults for optional environment variables
COS_BUCKET_NAME=${COS_BUCKET_NAME:-"vpc-ci-storage"}
COS_ENDPOINT=${COS_ENDPOINT:-"https://s3.eu-gb.cloud-object-storage.appdomain.cloud"}

# Validate source based on operation
if [[ "${OPERATION}" == "upload" ]]; then
    if [[ ! -f "${SOURCE}" ]]; then
        echo "ERROR: Source file not found: ${SOURCE}" >&2
        exit 1
    fi
elif [[ "${OPERATION}" == "download" ]]; then
    DEST_DIR=$(dirname "${DESTINATION}")
    if [[ ! -d "${DEST_DIR}" ]]; then
        mkdir -p "${DEST_DIR}"
    fi
fi

# Install Python dependencies
python3 -m pip install -q -r ${PATH_TO_GENCTL_CI}/scripts/generic_cos_operations/requirements.txt

# Build command with optional flags
CMD="python3 ${PATH_TO_GENCTL_CI}/scripts/generic_cos_operations/generic_cos_operations.py ${OPERATION} ${SOURCE} ${DESTINATION}"

if [[ "${DRY_RUN}" == "true" ]]; then
    CMD="${CMD} --dry-run"
fi

if [[ "${NO_VERIFY}" == "true" && "${OPERATION}" == "upload" ]]; then
    CMD="${CMD} --no-verify"
fi

# Execute the operation
${CMD}
