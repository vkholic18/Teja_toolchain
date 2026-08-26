#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Set the flag that exits if the task failed
EXIT_ON_TASK_FAILURE="true"

# This is to set the custom task name for build
CUSTOM_TASK_NAME_FOR_BUILD=$1

if [[ ! -z "${CUSTOM_TASK_NAME_FOR_BUILD}" ]]; then
    CUSTOM_TASK_NAME_FOR_BUILD=$CUSTOM_TASK_NAME_FOR_BUILD
else
    CUSTOM_TASK_NAME_FOR_BUILD="BUILD"
fi

# In some flows we want to skip the build itself, so check 
if [[ $SKIP_BUILD = true ]]; then
    echo "Skipping build..."
else
    ## Build ##
    cd ${WORKSPACE}
    ln -s ${PATH_TO_WORKSPACE_REPO} workspace-repo
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${CUSTOM_TASK_NAME_FOR_BUILD} ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/tasks/pipeline/generic-workspace-build-v11.sh
fi
