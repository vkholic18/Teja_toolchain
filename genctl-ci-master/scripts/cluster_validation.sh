#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
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

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

# # Get the Mzone we need to use for running Deploy Dal
# export CLAIM_MZONE_RESULT=$(get_env ci_parent_pipeline_claimed_mzone)

echo ${CLAIM_MZONE_RESULT}

# At this point, we should have an Mzone to run Deploy dal
# If this variable is empty then it means, something went wrong and we exit with error
if [[ -z "${CLAIM_MZONE_RESULT}" ]]
then
    echo "We don't know in which MZone run Deploy_Dal; something went wrong"
    echo "Exiting with error..."
    exit 1
else
    echo "Will proceed to run validations on ${CLAIM_MZONE_RESULT}"
fi

# dmm cluster validation checks rias
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "DMM_CLUSTER_VALIDATION_CHECKS_RIAS" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/deploy-rias-mds.sh   #executes only the validations not deployment


# dmm cluster validation checks genctl
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "DMM_CLUSTER_VALIDATION_CHECKS_GENCTL" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/cluster-validation-dmm-genctl.sh
