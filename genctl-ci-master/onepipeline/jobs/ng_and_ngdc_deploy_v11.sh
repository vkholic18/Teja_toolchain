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
MAX_ATTEMPTS_BUSY_WAIT=${MAX_ATTEMPTS_BUSY_WAIT:-900}
SLEEP_TIME_BUSY_WAIT=${SLEEP_TIME_BUSY_WAIT:-30}

#This can be removed once we get new agent
CUSTOM_SUB_PIPELINE_CONFIG="onepipeline/pipelines/templatized/release_bundles/pr_with_rias_smoke_v11/.pipeline-config-subpipeline-brt-deploy-dal.yaml"

# Trigger NG deploy (Without waiting)
${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_v11.sh "deploy-ng-as-subpipeline" "deploy-ng-trigger"  "false" ${CUSTOM_SUB_PIPELINE_CONFIG} 

# Extract NG deploy info
DEPLOY_NG_TASK=$(get_data pending-tasks)
DEPLOY_NG_PIPELINE_RUN_ID=${DEPLOY_NG_TASK#"async-"}

# Trigger NGDC deploy (Without waiting)
${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_v11.sh "deploy-ngdc-as-subpipeline" "deploy-ngdc-trigger"  "false" ${CUSTOM_SUB_PIPELINE_CONFIG}

# Extract NGDC info
DEPLOY_NG_AND_NGDC_TASKS=$(get_data pending-tasks)

# At this point, in DEPLOY_NG_AND_NGDC_TASKS we should have the previous value + the new one
# Therefore, to get the new one, we remove the previous one
DEPLOY_NGDC_TASK=${DEPLOY_NG_AND_NGDC_TASKS//"$DEPLOY_NG_TASK"/}
DEPLOY_NGDC_TASK_REMOVED_CHARS=$(echo ${DEPLOY_NGDC_TASK} | tr -d '\r' | tr -d ' ' )
DEPLOY_NGDC_PIPELINE_RUN_ID=${DEPLOY_NGDC_TASK_REMOVED_CHARS#"async-"}

# By now, pass if NG passes
ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)
BASE_URL="api.${ENDPOINT}.devops.cloud.ibm.com"

# Wait for both to finish (ng only)
# wait_until_all_pipeline_runs_finish "${BASE_URL}" \
# "${PIPELINE_ID}" "deploy-ng/${DEPLOY_NG_PIPELINE_RUN_ID}" \
# "${MAX_ATTEMPTS_BUSY_WAIT}" "${SLEEP_TIME_BUSY_WAIT}"

# Wait for both to finish (ng + ngdc)
wait_until_all_pipeline_runs_finish "${BASE_URL}" \
"${PIPELINE_ID}" "deploy-ng/${DEPLOY_NG_PIPELINE_RUN_ID}" \
"${MAX_ATTEMPTS_BUSY_WAIT}" "${SLEEP_TIME_BUSY_WAIT}"

# Get status
DEPLOY_NG_SUB_PIPELINE_STATUS=$(curl -s -X GET --location --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" --header "Accept: application/json" "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${DEPLOY_NG_PIPELINE_RUN_ID}?includes=definitions" | jq -r '.status')

# Check result and exit accordingly
if [[ "$DEPLOY_NG_SUB_PIPELINE_STATUS" == "succeeded" ]]
then
    echo "Deploy NG was succesful"
else
    echo "Deploy NG failed; will exit with error..."
    exit 1
fi

