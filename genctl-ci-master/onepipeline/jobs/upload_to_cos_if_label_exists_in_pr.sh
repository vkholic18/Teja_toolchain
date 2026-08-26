#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
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

${PATH_TO_GENCTL_CI}/scripts/check_pr_has_label/check_pr_has_label.sh "${DEV_INTEGRATION_PR_COS_UPLOAD_READY_LABEL_NAME}"

result=$?
echo "result check_pr_has_label: $result"
if [[ $result -eq 0 ]] ; then
    echo "label ${DEV_INTEGRATION_PR_COS_UPLOAD_READY_LABEL_NAME} exist"
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "UPLOAD_TO_COS" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/tasks/upload-to-cos.sh
elif [[ $result -eq 100 ]] ; then
    echo "failed to get information about the ${DEV_INTEGRATION_PR_COS_UPLOAD_READY_LABEL_NAME} label"
    exit 1
fi
