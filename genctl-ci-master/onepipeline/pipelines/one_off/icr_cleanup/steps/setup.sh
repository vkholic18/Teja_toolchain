#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ============================================================================================

set -o pipefail

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

#source cloud utils 
source "$PATH_TO_GENCTL_CI/scripts/ibmcloud_utils.sh" 

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="false"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"
# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

echo "running ICR_Image Creation"

run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "ICR_CLEANUP" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/icr_cleanup/create-list-images.sh