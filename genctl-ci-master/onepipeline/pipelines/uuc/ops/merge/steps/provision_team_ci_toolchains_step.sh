#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
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

export PIPELINE_TYPE="merge"

# Define the repositories to be cloned
REPOS_TO_CLONE="
UUC_TOOLCHAINS"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Clone required repos
clone_repos_from_env_vars "${IBM_HTTPS_BASE_URL}" "${WORKSPACE}" "${REPOS_TO_CLONE}"

# Path needed by provision_team_ci_toolchains.sh to skip re-cloning the toolchains repo
export PATH_TO_UUC_TOOLCHAINS_REPO="${WORKSPACE}/${UUC_TOOLCHAINS_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if CI toolchains provisioning script exists
if [ -f "${SCRIPT_DIR}/provision_team_ci_toolchains.sh" ]
then
    echo "Running team CI toolchains provisioning"
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "PROVISION_TEAM_CI_TOOLCHAINS" ${EXIT_ON_TASK_FAILURE} \
    ${SCRIPT_DIR}/provision_team_ci_toolchains.sh
else
    echo "provision_team_ci_toolchains.sh file not found"
    exit 1
fi

# Made with Bob
