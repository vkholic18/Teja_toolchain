#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
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

SUBPIPELINE_TO_TRIGGER=$1
TRIGGER_NAME_TO_USE=${2:-""}
WAIT_UNTIL_FINISHES=${3:-"true"}
CUSTOM_SUB_PIPELINE_CONFIG=$4

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

# Trigger the subpipeline
trigger-task "$SUBPIPELINE_TO_TRIGGER"

# Reset the value to original
set_env pipeline-config "${ONE_PIPELINE_CONFIG}"
set_env one-pipeline-config "${ONE_PIPELINE_CONFIG}"

SUB_PIPELINE_RUN_ID=""

if [ "${WAIT_UNTIL_FINISHES}" == "true" ]; then
    # Extract the endpoint, this gives us stuff like eu-gb, us-south, etc
    ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)
    BASE_URL="api.${ENDPOINT}.devops.cloud.ibm.com"

    # Get the ID of the pipeline run that was started on trigger-task 
    PENDING_TASKS=$(get_data pending-tasks)
    for TASK in $(echo ${PENDING_TASKS} | tr "\n" " "); do
      #we're going to check each task for completion. if the status is not one 
      SUB_PIPELINE_RUN_ID=${TASK#"async-"}
      source "${PATH_TO_GENCTL_CI}/onepipeline/utils/iam_utils.sh"

      # Get status
      SUB_PIPELINE_STATUS=$(curl -s -X GET --location --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" --header "Accept: application/json" "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${SUB_PIPELINE_RUN_ID}?includes=definitions" | jq -r '.status')

      echo "SubPipeline-RunId ${SUB_PIPELINE_RUN_ID} has status ${SUB_PIPELINE_STATUS}"
      #if the status is not one of the expected statuses, we should have our ID. if it is one 
      if [[ "$ONE_PIPELINE_RUN_FINISHED_STATUSES" =~ (^|[[:space:]])$SUB_PIPELINE_STATUS($|[[:space:]]) ]]
      then
        echo "skipping"
        continue
      else
        echo "continuing"
        break
      fi
    done

    # Busy wait
    wait_until_pipeline_run_finished "${BASE_URL}" \
    "${PIPELINE_ID}" "${SUB_PIPELINE_RUN_ID}" \
    "${MAX_ATTEMPTS_BUSY_WAIT}" "${SLEEP_TIME_BUSY_WAIT}"

    # At this point, we assume the pipeline finished
    # In order to avoid getting the token expired right before getting the final status of the pipeline, we generate a new one
    source "${PATH_TO_GENCTL_CI}/onepipeline/utils/iam_utils.sh"
    
    SUBPIPELINE_URL=$(get_data ${TASK} "url")
    set_env SAVE_SUBPIPELINE_URL "${SUBPIPELINE_URL}"
    export_env "SAVE_SUBPIPELINE_URL"

    # Get status
    SUB_PIPELINE_STATUS=$(curl -s -X GET --location --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" --header "Accept: application/json" "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${SUB_PIPELINE_RUN_ID}?includes=definitions" | jq -r '.status')

    # Check result and exit accordingly
    if [[ "$SUB_PIPELINE_STATUS" == "succeeded" ]]
    then
        echo "Subpipeline was successful"
    else
        echo "Something went wrong... Check the relevant subpipeline for more details..."
        exit 1
    fi
else
    echo "The parent pipeline will not wait for the sub-pipeline to finish. "
fi
