#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Define type of pipeline (Used to search overrides)
# Some promotion pipelines use the non-standard PIPELINE_TYPE as 'promotion'
if [[ "${PIPELINE_REPO_NAME}" == *prod ]] || [[ "${PIPELINE_REPO_NAME}" == "staging" ]]; then
  PIPELINE_TYPE="promotion"
else
  PIPELINE_TYPE="pr"
fi
echo "PIPELINE_TYPE is ${PIPELINE_TYPE}"

# Define the repositories to be cloned
REPOS_TO_CLONE="
PLATFORM_INVENTORY
RIAS_GLOBALS
GENCTL_GLOBALS
DEV_REGIONS
GENESIS_DEPLOY_ARTIFACTS
RIAS_ETCD_GLOBALS
RIAS_ETCD_RELEASE
"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Clone required repos
clone_repos_from_env_vars "${IBM_HTTPS_BASE_URL}" "${WORKSPACE}" "${REPOS_TO_CLONE}"

# Exit if "promotion" label is missing on the PR
${PATH_TO_GENCTL_CI}/scripts/check_pr_has_label/check_pr_has_label.sh "${SCAN_LABEL}"

if [[ $? -ne 0 ]] ; then
  echo "Label \"${SCAN_LABEL}\" is missing. Won't run promotion tests. Exiting ..."
  exit 1
else
  echo "Label \"${SCAN_LABEL}\" found, proceeding .."
fi
