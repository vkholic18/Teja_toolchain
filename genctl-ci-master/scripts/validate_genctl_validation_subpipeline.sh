#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script scales razee clusters

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

# Source the ibmcloud_utils.sh
. ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

export GENCTL_VALIDATION_PIPELINES=$(get_data pending-tasks)

FORMATTED_PIPELINES=""

COUNTER=1
for pipeline_id in ${GENCTL_VALIDATION_PIPELINES}; do
    # Remove "async-" prefix if present
    clean_id=${pipeline_id#"async-"}
    # Add to formatted string with genctl-env-N prefix
    if [ -z "${FORMATTED_PIPELINES}" ]; then
        FORMATTED_PIPELINES="genctl-env-${COUNTER}/${clean_id}"
    else
        FORMATTED_PIPELINES="${FORMATTED_PIPELINES} genctl-env-${COUNTER}/${clean_id}"
    fi
    COUNTER=$((COUNTER + 1))
done

# Update the variable with the formatted version
GENCTL_VALIDATION_PIPELINES="${FORMATTED_PIPELINES}"

echo "Formatted pipeline IDs: ${GENCTL_VALIDATION_PIPELINES}"

# Set few variables
MAX_ATTEMPTS_BUSY_WAIT=${MAX_ATTEMPTS_BUSY_WAIT:-960}
SLEEP_TIME_BUSY_WAIT=${SLEEP_TIME_BUSY_WAIT:-30}

# Extract the endpoint
ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)
BASE_URL="api.${ENDPOINT}.devops.cloud.ibm.com"

# Wait for all pipelines to finish
wait_until_all_pipeline_runs_finish "${BASE_URL}" \
"${PIPELINE_ID}" "${GENCTL_VALIDATION_PIPELINES}" \
"${MAX_ATTEMPTS_BUSY_WAIT}" "${SLEEP_TIME_BUSY_WAIT}"

# At this point, we assume the pipelines finished
# In order to avoid getting the token expired right before getting the final status of the pipeline, we generate a new one
source "${PATH_TO_GENCTL_CI}/onepipeline/utils/iam_utils.sh"

# Iterate over each pipeline to check status and save URLs
ALL_SUCCEEDED=true
for formatted_pipeline in ${GENCTL_VALIDATION_PIPELINES}; do
    # Extract the pipeline run ID from "genctl-env-N/pipeline-id" format
    PIPELINE_RUN_ID=$(echo ${formatted_pipeline} | cut -d '/' -f 2)
    ENV_NAME=$(echo ${formatted_pipeline} | cut -d '/' -f 1)

    echo "Checking status for ${ENV_NAME} with pipeline run ID: ${PIPELINE_RUN_ID}"

    # Get the task name (with async- prefix) for URL retrieval
    TASK="async-${PIPELINE_RUN_ID}"
    SUBPIPELINE_URL=$(get_data ${TASK} "url")
    set_env "SAVE_SUBPIPELINE_URL_${ENV_NAME}" "${SUBPIPELINE_URL}"
    export_env "SAVE_SUBPIPELINE_URL_${ENV_NAME}"

    # Get status
    SUB_PIPELINE_STATUS=$(curl -s -X GET --location --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" --header "Accept: application/json" "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${PIPELINE_RUN_ID}?includes=definitions" | jq -r '.status')

    echo "${ENV_NAME} subpipeline status: ${SUB_PIPELINE_STATUS}"

    # Check result
    if [[ "$SUB_PIPELINE_STATUS" != "succeeded" ]]; then
        echo "ERROR: ${ENV_NAME} subpipeline failed with status: ${SUB_PIPELINE_STATUS}"
        echo "Check the subpipeline for more details: ${SUBPIPELINE_URL}"
        ALL_SUCCEEDED=false
    fi
done

# Exit with error if any pipeline failed
if [[ "$ALL_SUCCEEDED" == "false" ]]; then
    echo "One or more genctl validation subpipelines failed"
    exit 1
else
    echo "All genctl validation subpipelines succeeded"
fi
