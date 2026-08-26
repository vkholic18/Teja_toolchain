#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

export PIPELINE_TYPE="pr"

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

# Check if GitHub access verification script exists
if [ -f "${SCRIPT_DIR}/verify_github_access.sh" ]
then
    echo "Running GitHub access verification"
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "VERIFY_GITHUB_ACCESS" ${EXIT_ON_TASK_FAILURE} \
    ${SCRIPT_DIR}/verify_github_access.sh
else
    echo "verify_github_access.sh file not found"
    exit 1
fi
