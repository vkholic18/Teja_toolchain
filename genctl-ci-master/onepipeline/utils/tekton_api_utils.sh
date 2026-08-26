#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

export ONE_PIPELINE_RUN_FINISHED_STATUSES="failed error succeeded cancelled"

function wait_until_pipeline_run_finished() {
    # This function waits until a pipeline run finishes

    # Pre-requisites: This function assumes that:
    # A) we have SECRET_PATH environment variable defined, this is required to generate IAM token
    # B) We have ONE_PIPELINE_PATH environment variable defined (This is provided by OnePipeline automatically)

    BASE_URL=$1
    PIPELINE_ID=$2
    RUN_ID=$3
    MAX_ATTEMPTS=$4
    SLEEP_TIME=$5

    # Local vars
    ATTEMPTS=0
    STATUS=" "

    # First generate an IAM token
    source "${PATH_TO_GENCTL_CI}/onepipeline/utils/iam_utils.sh"

    echo "Will check up to ${MAX_ATTEMPTS} times, until pipeline run ${RUN_ID} of pipeline ${PIPELINE_ID} is in one of the following states: [ ${ONE_PIPELINE_RUN_FINISHED_STATUSES} ] "
    
    while true
    do
        # If we reach the maximum number of attempts, exit 1
        if [[ ${ATTEMPTS} -eq ${MAX_ATTEMPTS} ]]
        then
            echo "After checking ${ATTEMPTS} times, pipeline is still running, exiting..."
            exit 1
        else
            echo "Will do attempt ${ATTEMPTS} to check if the pipeline finished running..."
        fi

        # Get the status
        STATUS=$(curl -s -X GET --location --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" --header "Accept: application/json"   "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${RUN_ID}?includes=definitions" | jq -r '.status') 

        if [[ "$STATUS" == "null" ]]
        then
            echo "Couldn't manage to get the pipeline status, this might indicate that the IAM token is expired"
            echo "Will generate a new token and try again..."

            # Generate a new token
            source "${PATH_TO_GENCTL_CI}/onepipeline/utils/iam_utils.sh"

            # Get the status
            STATUS=$(curl -s -X GET --location --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" --header "Accept: application/json"   "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${RUN_ID}?includes=definitions" | jq -r '.status')

            # If after getting a fresh token, status is still null, then something must be wrong and we just exit
            if [[ "$STATUS" == "null" ]]
            then
                echo "After generating a new token, we are still not able to get the pipeline status..."
                exit 1
            fi
        fi
        
        echo "Current status of pipeline is: ${STATUS}"
        if [[ "$ONE_PIPELINE_RUN_FINISHED_STATUSES" =~ (^|[[:space:]])$STATUS($|[[:space:]]) ]]
        then
            # Exit the loop
            break
        fi

        # Wait and increment the number of attempts
        sleep ${SLEEP_TIME}
        ATTEMPTS=$((ATTEMPTS+1))
    done
}
function wait_until_all_pipeline_runs_finish() {
    # This function waits until all the defined pipeline runs are finished

    # Limitation: All the pipeline runs need to be from same pipeline (Same base URL)

    # Pre-requisites: This function assumes that:
    # A) we have SECRET_PATH environment variable defined, this is required to generate IAM token
    # B) We have ONE_PIPELINE_PATH environment variable defined (This is provided by OnePipeline automatically)

    BASE_URL=$1
    PIPELINE_ID=$2
    RUNS_READABLE_NAME_AND_IDS=$3 # This is a string which is a space separated list of strings in the format of <READABLE_NAME>/<PIPELINE_RUN_ID>
    MAX_ATTEMPTS=$4 # This is the total 
    SLEEP_TIME=$5

    # Local vars
    ATTEMPTS=0
    STATUS=" "

    # First generate an IAM token
    source "${PATH_TO_GENCTL_CI}/onepipeline/utils/iam_utils.sh"

    echo "Will check up to ${MAX_ATTEMPTS} times, until the following runs: [ ${RUNS_READABLE_NAME_AND_IDS} ] are in one of the following states: [ ${ONE_PIPELINE_RUN_FINISHED_STATUSES} ] "
    echo "PS: Note that all these runs belong to pipeline ${PIPELINE_ID}"


    # Initially we assume that no pipeline finished yet
    REMAINING_RRNAIDS="${RUNS_READABLE_NAME_AND_IDS}"

    # Convert the initial string into an array ONCE
    read -ra REMAINING_RRNAIDS <<< "${RUNS_READABLE_NAME_AND_IDS}"
    
    ATTEMPTS=0
    
    while true; do
        # If we reach the maximum number of attempts, exit 1
        if (( ATTEMPTS >= MAX_ATTEMPTS )); then
            echo "After checking ${ATTEMPTS} times, not all the pipelines that we checked are finished..."
            exit 1
        else
            echo "Will do attempt ${ATTEMPTS} to check if all the pipelines finished running..."
        fi
    
        # This will hold pipelines that are still running after this iteration
        NEW_REMAINING_RRNAIDS=()
    
        for RRNAID in "${REMAINING_RRNAIDS[@]}"; do
            READABLE_NAME="${RRNAID%%/*}"
            PIPELINE_RUN_ID="${RRNAID##*/}"
    
            # Get the status
            STATUS=$(curl -s -X GET \
                --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" \
                --header "Accept: application/json" \
                "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${PIPELINE_RUN_ID}?includes=definitions" \
                | jq -r '.status')
    
            if [[ -z "$STATUS" ]]; then
                echo "Status for pipeline run id ${PIPELINE_RUN_ID} is empty; something went wrong..."
                exit 1
            fi
    
            if [[ "$STATUS" == "null" ]]; then
                echo "Couldn't manage to get the pipeline status, this might indicate that the IAM token is expired"
                echo "Will generate a new token and try again..."
    
                # Generate a new token
                source "${PATH_TO_GENCTL_CI}/onepipeline/utils/iam_utils.sh"
    
                STATUS=$(curl -s -X GET \
                    --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" \
                    --header "Accept: application/json" \
                    "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${PIPELINE_RUN_ID}?includes=definitions" \
                    | jq -r '.status')
    
                if [[ "$STATUS" == "null" ]]; then
                    echo "After generating a new token, we are still not able to get the pipeline status..."
                    exit 1
                fi
            fi
    
            echo "Current status of ${READABLE_NAME} is: ${STATUS}"
    
            if [[ "$ONE_PIPELINE_RUN_FINISHED_STATUSES" =~ (^|[[:space:]])$STATUS($|[[:space:]]) ]]; then
                echo "${READABLE_NAME} finished"
            else
                # Still running → keep it
                NEW_REMAINING_RRNAIDS+=("$RRNAID")
            fi
        done
    
        # Update remaining list
        REMAINING_RRNAIDS=("${NEW_REMAINING_RRNAIDS[@]}")
    
        if (( ${#REMAINING_RRNAIDS[@]} == 0 )); then
            echo "All the pipelines that we waited for are finished..."
            break
        else
            echo "The following did not finish yet:"
            for REM in "${REMAINING_RRNAIDS[@]}"; do
                echo "${REM%%/*}"
            done
    
            sleep "${SLEEP_TIME}"
            ((ATTEMPTS++))
        fi
    done
}
