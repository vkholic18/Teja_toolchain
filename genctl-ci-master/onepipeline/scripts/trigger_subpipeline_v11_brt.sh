#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script triggers a one-pipeline subpipeline 
# In addition, if required, it can wait until the subpipeline run finishes

# This script is intented to be used only in one-pipeline context and 
# It relies in built in variables and logic exposed by one-pipeline, changes in one-pipeline might affect this script behavior

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI
# ONE_PIPELINE_PATH (One pipeline internal use)

# In addition the following variables are optional and if not have values they will take the default

MAX_ATTEMPTS_BUSY_WAIT=${MAX_ATTEMPTS_BUSY_WAIT:-240}
SLEEP_TIME_BUSY_WAIT=${SLEEP_TIME_BUSY_WAIT:-30}

# In addition, the script receives the following parameters (As parameter and not as env vars for easier use)

# $1 --> SUBPIPELINE_TO_TRIGGER (Mandatory, is the name of the stage to run)
# $2 --> TRIGGER_NAME_TO_USE (Optional, the name of the trigger if using a predefined one)
# $3 --> WAIT_UNTIL_FINISHES (Optional, a string either 'true' or 'false', according to it will wait for the subpipeline to end or not)
# $4 --> CUSTOM_SUB_PIPELINE_CONFIG (Optional, the path to the custom sub pipeline config)
# $5 --> QZ2_MZONE_NAME (Optional, the name of the QZ2 mzone name)

SUBPIPELINE_TO_TRIGGER=$1
TRIGGER_NAME_TO_USE=${2:-""}
WAIT_UNTIL_FINISHES=${3:-"true"}
CUSTOM_SUB_PIPELINE_CONFIG=$4
QZ2_MZONE_NAME=$5
FEATURE_FLAG=$6


# Source some utils
source "${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh"
source "${PATH_TO_GENCTL_CI}/onepipeline/utils/tekton_api_utils.sh"

#Define environment to use in the sub pipeline
set_env_for_subpipeline

# If set, use a pre-defined trigger
if [ ! -z "$TRIGGER_NAME_TO_USE" ]
then
    set_env subpipeline-webhook-trigger-name "$TRIGGER_NAME_TO_USE"
else
    echo "Will use default one-pipeline subpipeline trigger..."
fi 

ONE_PIPELINE_CONFIG=$(get_env one-pipeline-config "")

set_env one-pipeline-config "${CUSTOM_SUB_PIPELINE_CONFIG}"
set_env qz2-mzone-name "${QZ2_MZONE_NAME}"
set_env qz2-worker-id "${TRIGGER_NAME_TO_USE}"
set_env launch-darkly-feature-flag "${FEATURE_FLAG}"

export_env "one-pipeline-config"
export_env "qz2-mzone-name"
export_env "qz2-worker-id"
export_env "launch-darkly-feature-flag"

# Trigger the subpipeline
trigger-task "$SUBPIPELINE_TO_TRIGGER"

# Reset the value to original
set_env pipeline-config "${ONE_PIPELINE_CONFIG}"
set_env one-pipeline-config "${ONE_PIPELINE_CONFIG}"

echo "The pipeline is triggered successfully, the status will be monitored collectively for all mzone entries"

if [ "${WAIT_UNTIL_FINISHES}" == "true" ]; then

    FORMATTED_PIPELINES=""
    COUNTER=1
    export GENCTL_CLEANUP_PIPELINES=$(get_data pending-tasks)
    for pipeline_id in ${GENCTL_CLEANUP_PIPELINES}; do
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
    GENCTL_CLEANUP_PIPELINES="${FORMATTED_PIPELINES}"

    echo "Formatted pipeline IDs: ${GENCTL_CLEANUP_PIPELINES}"

    # Set few variables
    MAX_ATTEMPTS_BUSY_WAIT=${MAX_ATTEMPTS_BUSY_WAIT:-960}
    SLEEP_TIME_BUSY_WAIT=${SLEEP_TIME_BUSY_WAIT:-30}

    # Extract the endpoint
    ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)
    BASE_URL="api.${ENDPOINT}.devops.cloud.ibm.com"

    # Wait for all pipelines to finish
    wait_until_all_pipeline_runs_finish "${BASE_URL}" \
    "${PIPELINE_ID}" "${GENCTL_CLEANUP_PIPELINES}" \
    "${MAX_ATTEMPTS_BUSY_WAIT}" "${SLEEP_TIME_BUSY_WAIT}"

    # Extract pipeline_run_id from the first entry in GENCTL_CLEANUP_PIPELINES
    FIRST_PIPELINE=$(echo "${GENCTL_CLEANUP_PIPELINES}" | awk '{print $1}')
    VALIDATION_PIPELINE_RUN_ID=$(echo "${FIRST_PIPELINE}" | cut -d'/' -f2)
    
    echo "Using VALIDATION_PIPELINE_RUN_ID: ${VALIDATION_PIPELINE_RUN_ID}"

    VALIDATION_SUB_PIPELINE_STATUS=$(curl -s -X GET --location --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" --header "Accept: application/json" "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${VALIDATION_PIPELINE_RUN_ID}?includes=definitions" | jq -r '.status')
    if [[ "$VALIDATION_SUB_PIPELINE_STATUS" == "succeeded" ]]
    then
        echo "Subpipeline was successful, genctl validations passed"
    else
        echo "Checking logs for validation status..."
        
        # Get logs object IDs
        LOGS_RESPONSE=$(curl -s -X GET --location --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" --header "Accept: application/json" "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${VALIDATION_PIPELINE_RUN_ID}/logs")
        
        # Extract the ID for the run-stage log entry
        RUN_STAGE_LOG_ID=$(echo "${LOGS_RESPONSE}" | jq -r '.logs[] | select(.name | contains("run-stage")) | .id' | head -n 1)
        
        if [ -z "$RUN_STAGE_LOG_ID" ]; then
            echo "ERROR: Could not find run-stage log entry"
            exit 1
        fi
        
        # Fetch the actual logs for the run-stage
        RUN_STAGE_LOGS=$(curl -s -X GET --location --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" --header "Accept: application/json" "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${VALIDATION_PIPELINE_RUN_ID}/logs/${RUN_STAGE_LOG_ID}")
        
        # Search for the validation success string
        if echo "${RUN_STAGE_LOGS}" | grep -q "genctl validations are successful"; then
            echo "Subpipeline was successful, genctl validations passed"
        else
            echo "Validations failed, exiting..."
            exit 1
        fi
    fi

fi
