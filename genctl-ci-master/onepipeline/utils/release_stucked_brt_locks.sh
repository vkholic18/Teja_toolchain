#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# The following environment variables should be defined before executing this script

# PATH_TO_GENCTL_CI, PATH_TO_BRT_LOCKS

# Source lock utils
source ${PATH_TO_GENCTL_CI}/tools/lock_and_queue_utils/lock.sh

# Source tekton api utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/tekton_api_utils.sh

# Get IAM Token
source "${PATH_TO_GENCTL_CI}/onepipeline/utils/iam_utils.sh"

# Move to the claimed folder
pushd ${PATH_TO_BRT_LOCKS}/claimed

# Get the claimed locks
CLAIMED_LOCKS=$(ls)

if [[ -z "${CLAIMED_LOCKS}" ]]
then
    echo "No claimed locks currently..."
else

    echo "The following locks are currently claimed:"
    echo "${CLAIMED_LOCKS}"

    # Iterate over all the claimed locks
    for lock in *
    do
        echo ""
        echo "***** Processing lock ${lock} *****"
        echo ""

        # First do some processing to extract the commit message
        RAW_GIT_LOG_RESULT=$(git log --oneline -- filename ${lock} | head -n 1)
        ONLY_SHA=$(echo ${RAW_GIT_LOG_RESULT} | cut -d ' ' -f 1)
        COMMIT_MESSAGE=${RAW_GIT_LOG_RESULT#"$ONLY_SHA "}
        
        # At this point we should have on COMMIT_MESSAGE the commit message
        # The claim lock of BRT in OnePipeline has the following format:
        # "${PIPELINE_RUN_NAME} run ${BUILD_NUMBER} - 1P_INFO: ${PIPELINE_ID}/${PIPELINE_RUN_ID}/${ENDPOINT}"

        # Example:
        # "riaas/regional-storage pr run 4 - 1P_INFO: ec6bf6da-5d3d-48f9-a4a1-93b291e20f6c/726b422f-ca0c-4ae7-aef3-a9e44077f7c8/us-south"
        
        # Verify if is one-pipeline related
        echo ${COMMIT_MESSAGE} | grep "1P_INFO:"

        if [[ $? -eq 0 ]]
        then
            CLAIMED_PIPELINE_ID_AND_PIPELINE_RUN_ID="${COMMIT_MESSAGE#*1P_INFO: }"
            CLAIMED_PIPELINE_ID=$(echo ${CLAIMED_PIPELINE_ID_AND_PIPELINE_RUN_ID} | cut -d '/' -f 1)
            CLAIMED_RUN_ID=$(echo ${CLAIMED_PIPELINE_ID_AND_PIPELINE_RUN_ID} | cut -d '/' -f 2)
            ENDPOINT=$(echo ${CLAIMED_PIPELINE_ID_AND_PIPELINE_RUN_ID} | cut -d '/' -f 3)
            BASE_URL="api.${ENDPOINT}.devops.cloud.ibm.com"

            echo "PIPELINE_ID_AND_PIPELINE_RUN_ID: ${CLAIMED_PIPELINE_ID_AND_PIPELINE_RUN_ID}"
            echo "PIPELINE_ID: ${CLAIMED_PIPELINE_ID}"
            echo "RUN_ID: ${CLAIMED_RUN_ID}"
            echo "BASE_URL: ${BASE_URL}"

            # Get the status
            STATUS=$(curl -s -X GET --location --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" --header "Accept: application/json"   "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${CLAIMED_PIPELINE_ID}/pipeline_runs/${CLAIMED_RUN_ID}?includes=definitions" | jq -r '.status') 
            
            if [[ -z "${STATUS}" ]] 
            then
                echo "Could not get status for pipeline run"
                echo "Will exit with error..."
                exit 1
            else
                echo "Current status of pipeline is: ${STATUS}"
                if [[ "$ONE_PIPELINE_RUN_FINISHED_STATUSES" =~ (^|[[:space:]])$STATUS($|[[:space:]]) ]]
                then
                    echo "Will give some time to the pipeline to see if it releases it by itself..." 

                    MAX_ATTEMPTS_LOCK_IS_STILL_MINE=60
                    SLEEP_TIME_BETWEEN_ATTEMPTS=15
                    ATTEMPTS_LOCK_IS_STILL_MINE=0

                    while true
                    do
                        echo "Doing attempt ${ATTEMPTS_LOCK_IS_STILL_MINE} to check if lock is released by the pipeline..."
                        
                        # If we reach the maximum number of attempts, assume the lock is stucked
                        if [[ ${ATTEMPTS_LOCK_IS_STILL_MINE} -eq ${MAX_ATTEMPTS_LOCK_IS_STILL_MINE} ]]
                        then
                            echo "After ${ATTEMPTS_LOCK_IS_STILL_MINE} attempts, lock ${lock} is still claimed, despite the pipeline run status is ${STATUS}"
                            if [[ "${STATUS}" == "succeeded" ]]
                            then
                                echo "Status is succeeded but lock ${lock} is still claimed, however it might be that lock is still required by some async process (Example: dynamic scan)..."
                                echo "Therefore we can't assume that is actually stucked and we won't force its release..."
                            else
                                echo "We can assume that lock ${lock} is stucked, therefore, we proceed to force release" 
                                release_lock ${PATH_TO_BRT_LOCKS} ${lock} "Cronjob releasing stucked locks - Run ${BUILD_NUMBER}" 360 10
                            fi
                            break
                        else
                            if lock_is_still_mine ${PATH_TO_BRT_LOCKS} ${lock} "${COMMIT_MESSAGE}"
                            then
                                
                                # Clean and update for next try - This is crucial in order to "see" the lock in unclaimed once it gets released
                                git stash > /dev/null
                                git fetch > /dev/null
                                # We need to reset rather than rebase because if not, our local change will still be there and the move command won't work
                                git reset --hard origin/master > /dev/null
                                
                                # Wait and increment the number of attempts
                                sleep ${SLEEP_TIME_BETWEEN_ATTEMPTS}
                                ATTEMPTS_LOCK_IS_STILL_MINE=$((ATTEMPTS_LOCK_IS_STILL_MINE+1))
                            else
                                echo "Lock is not held anymore"
                                break
                            fi
                        fi
                    done
                else
                    echo "${lock} seems to be still in legitimate use"
                fi
            fi
        else
            echo "Not related to OnePipeline"
        fi

        echo ""
        echo "***** Finished processing lock ${lock} *****"
        echo ""

    done
fi

# Come back
popd