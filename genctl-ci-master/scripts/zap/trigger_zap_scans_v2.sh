#!/bin/bash

# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

if [[ "$PIPELINE_DEBUG" == 1 ]]; then
  trap env EXIT
  env
  set -x
fi

export CATEGORY_NAME=${CATEGORY_NAME}
export API_FILE_NAME=${API_FILE_NAME}
export PROFILES=${PROFILES}
export ENDPOINTS=${ENDPOINTS}
export EXCLUDE_ENTRIES=${EXCLUDE_ENTRIES:-"[]"}

# Some configurations before the actual run
source ${PATH_TO_GENCTL_CI}/scripts/zap/config_before_run_v2.sh

# start the scan
source "${COMMONS_PATH}/owasp-zap/run_scan.sh"

SCAN_REPORT="/workspace/app/zap-api/owasp-zap-owasp-zap_result-0.json"
SCAN_TYPE="owasp-zap"

# Upload to parent's COS prefix
COS_KEY="dynamic-scan-evidences/${PARENT_PIPELINE_RUN_ID}/${SCAN_TYPE}-${PIPELINE_RUN_ID}/${SCAN_REPORT}"

# Upload scan results to COS
${PATH_TO_GENCTL_CI}/scripts/generic_cos_operations/generic_cos_wrapper.sh upload $SCAN_REPORT $COS_KEY

if [[ ${PIPELINE_REPO_NAME} == "resource-metadata-workspace" ]]; then
    # cleanup the VSI if the post the scan 
    ${PATH_TO_WORKSPACE_REPO}/hack/ci/cleanup_after_metadata_scan.sh dmscan
fi
