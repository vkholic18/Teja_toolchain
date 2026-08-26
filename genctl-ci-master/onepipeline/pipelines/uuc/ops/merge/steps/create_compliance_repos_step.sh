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

# Set the pipeline template type
export PIPELINE_TYPE="merge"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"  # Continue even if this fails

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if repository creation script exists
if [ -f "${SCRIPT_DIR}/create_compliance_repos.sh" ]
then
    echo "Running compliance repositories creation"
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "CREATE_COMPLIANCE_REPOS" ${EXIT_ON_TASK_FAILURE} \
    ${SCRIPT_DIR}/create_compliance_repos.sh
else
    echo "create_compliance_repos.sh file not found"
    exit 1
fi

# Made with Bob
