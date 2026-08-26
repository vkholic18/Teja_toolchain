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

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="release_bundles"

INITIAL_PIPELINE_TYPE="pr"
get_pipeline_type "${PIPELINE_RUN_BRANCH}" "${INITIAL_PIPELINE_TYPE}" "${REPO_MAIN_BRANCH}"

# Define the repositories to be cloned
REPOS_TO_CLONE="
RIAS_GLOBALS
GENCTL_VETTED_VERSIONS
PLATFORM_INVENTORY
RIAS_RELEASE
RIAS_ETCD_RELEASE
MICRO_DEPLOY_SERVER
GENESIS_DEPLOY_ARTIFACTS
RESOURCELOCK
INTEGRATION_TESTING
"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Clone required repos
clone_repos_from_env_vars "${IBM_HTTPS_BASE_URL}" "${WORKSPACE}" "${REPOS_TO_CLONE}"

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_PLATFORM_INVENTORY_REPO="${WORKSPACE}/${PLATFORM_INVENTORY_REPO_NAME}"
export PATH_TO_VETTED_VERSIONS_REPO="${WORKSPACE}/${GENCTL_VETTED_VERSIONS_REPO_NAME}"
export PATH_TO_VV_UPDATED="" # Not supported in OnePipeline yet
export PATH_TO_MDS_REPO="${WORKSPACE}/${MICRO_DEPLOY_SERVER_REPO_NAME}"
export PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO="${WORKSPACE}/${GENESIS_DEPLOY_ARTIFACTS_REPO_NAME}"
export PATH_TO_RESOURCELOCK_REPO="${WORKSPACE}/${RESOURCELOCK_REPO_NAME}"
export PATH_TO_RIAS_RELEASE_REPO="${WORKSPACE}/${RIAS_RELEASE_REPO_NAME}"
export PATH_TO_RIAS_ETCD_RELEASE_REPO="${WORKSPACE}/${RIAS_ETCD_RELEASE_REPO_NAME}"
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_INTEGRATION_TESTING_REPO="${WORKSPACE}/${INTEGRATION_TESTING_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

export CLAIM_MZONE_RESULT=$(get_env ci_parent_pipeline_claimed_mzone)

# At this point, we should have an Mzone to run Deploy dal
# If this variable is empty then it means, something went wrong and we exit with error
if [[ -z "${CLAIM_MZONE_RESULT}" ]]
then
    echo "We don't know in which MZone run Deploy_Dal; something went wrong"
    echo "Exiting with error..."
    exit 1
else
    echo "Will proceed to run Deploy Dal on ${CLAIM_MZONE_RESULT}"
fi

# Execution of smoke tests
${PATH_TO_GENCTL_CI}/tasks/run-rias-smoke.sh
