#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Source utility to get equivalent dev-int version from master
source ${PATH_TO_GENCTL_CI}/scripts/get_dev_int_version_equivalent_to_current_master.sh

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="razee"

# Workaround
export PIPELINE_RUN_BRANCH=${REPO_MAIN_BRANCH}
export PIPELINE_TYPE="merge"

# Commented out since when the repo is cloned in the subpipeline is standing in dev-integration instead of main/master
#INITIAL_PIPELINE_TYPE="merge"
#get_pipeline_type "${PIPELINE_RUN_BRANCH}" "${INITIAL_PIPELINE_TYPE}" "${REPO_MAIN_BRANCH}"

# Define the repositories to be cloned
REPOS_TO_CLONE="
PLATFORM_INVENTORY
GENCTL_VETTED_VERSIONS
MICRO_DEPLOY_SERVER
GENESIS_DEPLOY_ARTIFACTS
RESOURCELOCK
RIAS_RELEASE
RIAS_ETCD_RELEASE
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

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="false"

# Get the Mzone we need to use for running validations
export CLAIM_MZONE_RESULT=$(get_env ci_parent_pipeline_claimed_mzone)

# At this point, we should have an Mzone to run validations
# If this variable is empty then it means, something went wrong and we exit with error
if [[ -z "${CLAIM_MZONE_RESULT}" ]]
then
    echo "We don't know in which MZone run validations; something went wrong"
    echo "Exiting with error..."
    exit 1
else
    echo "Will proceed to run validations on ${CLAIM_MZONE_RESULT}"
    ${PATH_TO_GENCTL_CI}/scripts/cluster_validation.sh
fi

