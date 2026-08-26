#!/usr/bin/env bash
if [[ "$PIPELINE_DEBUG" == 1 ]]; then
  trap env EXIT
  env
  set -x
fi

# At this point we know we are about to run dynamic scans, therefore, we extract and export some info we need
export API_FILE_NAME=$(yq -r '.dynamic_scan.api_file_name | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export PROFILES=$(yq -r '.dynamic_scan.profiles | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)

# Some configurations before the actual run
source ${PATH_TO_GENCTL_CI}/scripts/zap/config_before_run.sh

# start the scan
source "${COMMONS_PATH}/owasp-zap/run_scan.sh"

# Read the evidence 
cat $WORKSPACE/doi-evidence/owasp-zap-evidence.json

if [[ ${PIPELINE_REPO_NAME} == "resource-metadata-workspace" ]]; then
    # cleanup the VSI if the post the scan 
    ${PATH_TO_WORKSPACE_REPO}/hack/ci/cleanup_after_metadata_scan.sh dmscan
fi
