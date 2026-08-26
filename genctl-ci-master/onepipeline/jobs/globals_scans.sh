#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024, 2025
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
export EXIT_ON_TASK_FAILURE="true"

## Validate globals scan ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "VALIDATE_GLOBALS_SCAN" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/globals_pipeline_scripts/validate_globals_scan.sh

## Tidy ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "TIDY_SCAN" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/globals_pipeline_scripts/globals_tidy.sh
