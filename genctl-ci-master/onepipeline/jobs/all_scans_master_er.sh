#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
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

# detect the phase of the PR
detect_pr_phase "$PR_URL"

if [[ "$PR_PHASE" == "pre-merge" ]]; then
    ## Verify PR Head ##
    if [[ ${SKIP_VERIFY_PR_HEAD} == "false" ]]; then
        run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "SCAN_PR_FROM_DEV_INTEG" ${EXIT_ON_TASK_FAILURE} \
        ${PATH_TO_GENCTL_CI}/scripts/verify_pr_head/verify_pr_head.sh
    fi
fi

## Validate pipeline yaml ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "VALIDATE_PIPELINE_YAML" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/verify_workspace_pipeline_config.sh
