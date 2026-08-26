#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
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

# Source tekton api utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/tekton_api_utils.sh

# Set few variables
MAX_ATTEMPTS_BUSY_WAIT=${MAX_ATTEMPTS_BUSY_WAIT:-960}
SLEEP_TIME_BUSY_WAIT=${SLEEP_TIME_BUSY_WAIT:-30}


# Used for GHE checks
export FULL_CHECK_STR_BRT="${CHECKS_PREFIX}/${WORKSPACE_TESTS_CHECK_LABEL}"
export FULL_CHECK_DEPLOY_NGDC="${CHECKS_PREFIX}/DEPLOY_NGDC"

# Set pending status for BRT
set_ghe_commit_status "pending" "${WORKSPACE_TESTS_CHECK_LABEL} starts to run." "${FULL_CHECK_STR_BRT}"

# Trigger BRT (Without waiting)
${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_v11.sh "brt-as-subpipeline" "taas-worker-trigger" "false" "onepipeline/pipelines/templatized/razee/pr_and_ci_master_v11/.pipeline-config-subpipeline-configurations.yaml"

# Extract BRT deploy info
BRT_TASK=$(get_data pending-tasks)
BRT_PIPELINE_RUN_ID=${BRT_TASK#"async-"}

# Set pending status for NGDC
set_ghe_commit_status "pending" "DEPLOY_NGDC starts to run." "${FULL_CHECK_DEPLOY_NGDC}"

# Trigger NGDC deploy (Without waiting)
${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_v11.sh "deploy-ngdc-as-subpipeline" "deploy-ngdc-trigger" "false" "onepipeline/pipelines/templatized/razee/pr_and_ci_master_v11/.pipeline-config-subpipeline-configurations.yaml"

# Extract NGDC info
BRT_AND_DEPLOY_NGDC_TASKS=$(get_data pending-tasks)

# At this point, in DEPLOY_NG_AND_NGDC_TASKS we should have the previous value + the new one
# Therefore, to get the new one, we remove the previous one
DEPLOY_NGDC_TASK=${BRT_AND_DEPLOY_NGDC_TASKS//"$BRT_TASK"/}
DEPLOY_NGDC_TASK_REMOVED_CHARS=$(echo ${DEPLOY_NGDC_TASK} | tr -d '\r' | tr -d ' ' )
DEPLOY_NGDC_PIPELINE_RUN_ID=${DEPLOY_NGDC_TASK_REMOVED_CHARS#"async-"}

# By now, pass if BRT passes
ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)
BASE_URL="api.${ENDPOINT}.devops.cloud.ibm.com"

# Wait for both to finish
wait_until_all_pipeline_runs_finish "${BASE_URL}" \
"${PIPELINE_ID}" "brt/${BRT_PIPELINE_RUN_ID} ngdc/${DEPLOY_NGDC_PIPELINE_RUN_ID}" \
"${MAX_ATTEMPTS_BUSY_WAIT}" "${SLEEP_TIME_BUSY_WAIT}"

# Get statuses
BRT_SUB_PIPELINE_STATUS=$(curl -s -X GET --location --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" --header "Accept: application/json" "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${BRT_PIPELINE_RUN_ID}?includes=definitions" | jq -r '.status')
DEPLOY_NGDC_SUB_PIPELINE_STATUS=$(curl -s -X GET --location --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" --header "Accept: application/json" "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${DEPLOY_NGDC_PIPELINE_RUN_ID}?includes=definitions" | jq -r '.status')

## First check is only for the GHE statuses ##

# Handle BRT statuses
if [[ "$BRT_SUB_PIPELINE_STATUS" == "succeeded" ]]
then
    set_ghe_commit_status "success" "${WORKSPACE_TESTS_CHECK_LABEL} finished running" "${FULL_CHECK_STR_BRT}"
else
    set_ghe_commit_status "failure" "${WORKSPACE_TESTS_CHECK_LABEL} finished running" "${FULL_CHECK_STR_BRT}"
fi

# Handle Deploy NGDC statuses
if [[ "$DEPLOY_NGDC_SUB_PIPELINE_STATUS" == "succeeded" ]]
then
    set_ghe_commit_status "success" "DEPLOY_NGDC finished running" "${FULL_CHECK_DEPLOY_NGDC}"
else
    set_ghe_commit_status "failure" "DEPLOY_NGDC finished running" "${FULL_CHECK_DEPLOY_NGDC}"
fi

# Now for the actual result / exit code
# By now we consider only the BRT

if [[ "$BRT_SUB_PIPELINE_STATUS" == "succeeded" ]]
then
    echo "BRT passed"
else
    echo "BRT failed"
    exit 1
fi
