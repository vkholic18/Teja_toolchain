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

## Check pr title and commits ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "SCAN_PR_TITLE" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/check_pr_title/check_pr_title.sh

## Go vetting ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "SCAN_GO_VETTING" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/go-vetting.sh ${PATH_TO_WORKSPACE_REPO}

# Skipping genlog #
## Genlog ##
#run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "SCAN_GENLOG" ${EXIT_ON_TASK_FAILURE} \
#${PATH_TO_GENCTL_CI}/scripts/scan_repo_for_genlog.sh
