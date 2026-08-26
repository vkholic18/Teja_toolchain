#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023, 2025
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

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="release_bundles"

INITIAL_PIPELINE_TYPE="pr"
get_pipeline_type "${PR_BASEBRANCH}" "${INITIAL_PIPELINE_TYPE}" "${REPO_MAIN_BRANCH}"

# Basic logging info
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/basic_logging_info.sh

# Define the repositories to be cloned
REPOS_TO_CLONE="
PLATFORM_INVENTORY
GENCTL_VETTED_VERSIONS
MICRO_DEPLOY_SERVER
GENESIS_DEPLOY_ARTIFACTS
RESOURCELOCK
GENCTL_RELEASE
RIAS_RELEASE
RIAS_ETCD_RELEASE
PATH_TO_VETTED_VERSIONS_REPO
RIAS_GLOBALS
INTEGRATION_TESTING
DEV_REGIONS
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

# To have same effect that in concourse of in this template not having SKIP_CHECK_PR_TITLE
export SKIP_CHECK_PR_TITLE=""

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

export PATH_TO_GENCTL_RELEASE_REPO="${WORKSPACE}/${GENCTL_RELEASE_REPO_NAME}"
export PATH_TO_RIAS_RELEASE_REPO="${WORKSPACE}/${RIAS_RELEASE_REPO_NAME}"
export PATH_TO_RIAS_ETCD_RELEASE_REPO="${WORKSPACE}/${RIAS_ETCD_RELEASE_REPO_NAME}"
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"

# Set the SSH
eval "$(ssh-agent -s)" # Check if needed here
ssh-add - <<< "${GIT_PRIVATE_KEY}" # Check if needed here

# Note: Here we use a mix of jobs and tasks, therefore we configure both flags

# Set the flag that indicates if exit when a job fails
export EXIT_ON_JOB_FAILURE="true"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

if [[ "$PR_USERLOGIN" == "OnePipeLineCI" ]] && [[ "$PR_LABELS" =~ (^|[[:space:]])"${FOR_CI_ONLY_IGNORE_BUILD_UT_LABEL}"($|[[:space:]]) ]]; 
then
    echo "Skipping build, static-scan as this is just to bump a component"
    exit 0
else
    ### Check pr title and commits ###
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "SCAN_PR_TITLE" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/check_pr_title/check_pr_title.sh

    ### Prepare bundle ###
    run_job "PREPARE_BUNDLE" ${EXIT_ON_JOB_FAILURE} \
    ${PATH_TO_GENCTL_CI}/onepipeline/jobs/prepare_release_bundles.sh

    ### Execute Static code scan using Mend SAST, set EXIT_ON_JOB_FAILURE to false
    export EXIT_ON_JOB_FAILURE="false"
    run_job "CODE_STATIC_SCAN" ${EXIT_ON_JOB_FAILURE} \
    ${PATH_TO_GENCTL_CI}/onepipeline/jobs/run_static_scan.sh
fi
