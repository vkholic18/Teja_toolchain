#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================

# The following environment variables need to be set before executing the script:

# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO, PATH_TO_RESOURCELOCK_REPO

# In addition the following environment variables are optional: 
WAIT_BEFORE_RETRY=${WAIT_BEFORE_RETRY:-5}
LOCK_POOL=${LOCK_POOL:-"release-deploy-lock"}

RELEASE_LOCK_DIRECTORY="${PATH_TO_RESOURCELOCK_REPO}/$LOCK_POOL"
UNCLAIMED_PATH=$RELEASE_LOCK_DIRECTORY/unclaimed/*
CLAIMED_PATH=$RELEASE_LOCK_DIRECTORY/claimed/*
PIPELINE_FILE=${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml

# Used in OnePipeline for stop the busy wait
WAIT_BEFORE_RETRY_ONE_PIPELINE=${WAIT_BEFORE_RETRY_ONE_PIPELINE:-30}
MAX_ATTEMPTS_TO_GET_LOCK=1080
ATTEMPTS_TO_GET_LOCK=0

# Source few utils
source ${PATH_TO_GENCTL_CI}/scripts/rebase_and_retrieve_metadata.sh
source ${PATH_TO_GENCTL_CI}/scripts/retry.sh
source ${PATH_TO_GENCTL_CI}/tools/lock_and_queue_utils/queue_utils.sh


retry initGit
retry getPipelineDetails
pushd $RELEASE_LOCK_DIRECTORY
echo -n "."

rebase
popd

# Create queue file
# Check if repo contains specific CI attributes and add it to queue filename
mzonesStr=""
if containsPipelineAttributes; then
    # get the contents once
    pipeline_content=$(cat $PIPELINE_FILE)
    if pipelineContainsName; then
        echo in getEnvByName
        mzonesStr=$(getEnvByName)
        echo mzoneStr: $mzonesStr
    else
        getEnvsByAttributes
    fi

    if [[ -z $mzonesStr ]]; then
        echo mzone with requested name or attributes is either not available or does not exist in CI pool
        exit 1
    fi
fi

pushd $RELEASE_LOCK_DIRECTORY
echo -n "."

getUnclaimedEnv result
envFile=${result}
getFirstInQueue nextInQueue

echo "adding to queue and waiting to my turn"
getId id
echo pipeline ID is: $id
timestamp=$(date +"%Y-%m-%d_%H-%M-%S.%s")


# Create pipeline queue file in queue directory
queue_file=${timestamp}:${id}
touch $QUEUE_FILES_FOLDERS/${queue_file}
retry git add $QUEUE_FILES_FOLDERS/${queue_file}
retry commitAndPush "${pipelineName}/${jobName} build ${buildName}"

start=`date +%s`
filesInQueue=""
placeInQueue=0;
maxQueueLength=0;
nextInQueue="";

## =================================================================================================
## Check the queue in loop until there is available environment and this pipeline is first in queue
## =================================================================================================
while true
do
    if [[ ${IS_ONE_PIPELINE_RUN} == "true" ]]
    then   
        echo "$(date +'%Y-%m-%d %H:%M:%S.%s'): Will proceed to sleep for ${WAIT_BEFORE_RETRY_ONE_PIPELINE} seconds..."
        sleep ${WAIT_BEFORE_RETRY_ONE_PIPELINE}
    else
        sleep ${WAIT_BEFORE_RETRY}
    fi
    rebase
    currFilesInQueue=$(ls $QUEUE_FILES_FOLDERS | wc -l)
    if [[ ${currFilesInQueue} > ${maxQueueLength} ]]; then
        maxQueueLength=${currFilesInQueue}
    fi
    currPlaceInQueue=0
    # If place in queue or length of queue changed, print the new place and length
    fileFound=false
    for filename in $QUEUE_FILES_FOLDERS/*; do
        let "currPlaceInQueue+=1"
        if [[ ${filename} == *"${id}"*  ]];then
            fileFound=true
            if [[ ${currPlaceInQueue} != ${placeInQueue} || ${currFilesInQueue} != ${filesInQueue} ]];then
            echo Place in queue: ${currPlaceInQueue}/${currFilesInQueue}
            placeInQueue=${currPlaceInQueue}
            filesInQueue=${currFilesInQueue}
            fi
        fi
    done

    if [[ $fileFound = false ]]; then
        echo Queue file deleted by a cleanup process that identified it hang. Please restart this build.
        exit 1
    fi
    echo -ne "."
    getUnclaimedEnv result

    envFile=${result}
    # There is available mzone in the pool
    if [ $envFile ]; then
        getFirstInQueue firstInQueue
        firstInQueue=$(echo $firstInQueue | cut -d ":" -f 2)
        if [[ $firstInQueue != $nextInQueue ]];then
            echo There is available mzone. Next in queue: $firstInQueue, my ID:$id
            nextInQueue=$firstInQueue
        fi
        # Check if its my turn
        if [[ $nextInQueue == $id ]]; then
            # check if id contains specific CI mzones (envs) and if there is env that fits .If its not exist, give the turn to next relevant pipeline
            echo envFile: $envFile
            nextId=$id
            popd
            envFile=$(availableMzoneFits)
            pushd $RELEASE_LOCK_DIRECTORY
            echo envFile: $envFile
            if [[ -z $envFile ]]; then
                echo Requested mzone not found, give the turn to different pipeline
                swapTurnWithNextRelevantPipeline
            else
                # Remove pipeline queue file and move forward to claim the mzone.
                echo Getting $envFile
                retry git mv $UNCLAIMED_DIR/${envFile} $CLAIMED_DIR/${envFile}
                retry commitAndPush "${gitMsg}:${envFile}"
                end=`date +%s`
                runtime=$((end-start))
                runtime=$((runtime/60))
                echo Time in queue: ${runtime} minute/s
                retry git rm $QUEUE_FILES_FOLDERS/*${id}
                retry commitAndPush "remove ${pipelineName}/${jobName} build ${buildName} MinutesInQ-${runtime} MaxQLength-${maxQueueLength} ${timestamp}"
                popd
                if [[ ${IS_ONE_PIPELINE_RUN} == "true" ]]
                then
                    # In One Pipeline we don't want to exit, but rather export the MZONE we got
                    # And break, in order to finish the loop to continue with the rest of the execution in the parent call
                    export CLAIM_MZONE_RESULT=$(cat $RELEASE_LOCK_DIRECTORY/$CLAIMED_DIR/${envFile})
                    echo "Since we are in One Pipeline run, we export value ${CLAIM_MZONE_RESULT} to environment variable CLAIM_MZONE_RESULT"
                    break
                else
                    exit 0;
                fi
            fi
        else
            if [[ ${IS_ONE_PIPELINE_RUN} == "true" ]]
            then  
                if [[ ${ATTEMPTS_TO_GET_LOCK} -eq ${MAX_ATTEMPTS_TO_GET_LOCK} ]]
                then
                    echo "$(date +'%Y-%m-%d %H:%M:%S.%s'): After ${ATTEMPTS_TO_GET_LOCK} attempts, didn't manage to acquire lock"
                    break
                else
                    echo "$(date +'%Y-%m-%d %H:%M:%S.%s'): Up to now, made ${ATTEMPTS_TO_GET_LOCK} attempts to acquire lock..."
                    ATTEMPTS_TO_GET_LOCK=$((ATTEMPTS_TO_GET_LOCK+1))
                fi
            fi
        fi
    else
        if [[ ${IS_ONE_PIPELINE_RUN} == "true" ]]
        then  
            if [[ ${ATTEMPTS_TO_GET_LOCK} -eq ${MAX_ATTEMPTS_TO_GET_LOCK} ]]
            then
                echo "$(date +'%Y-%m-%d %H:%M:%S.%s'): After ${ATTEMPTS_TO_GET_LOCK} attempts, didn't manage to acquire lock"
                break
            else
                echo "$(date +'%Y-%m-%d %H:%M:%S.%s'): Up to now, made ${ATTEMPTS_TO_GET_LOCK} attempts to acquire lock..."
                ATTEMPTS_TO_GET_LOCK=$((ATTEMPTS_TO_GET_LOCK+1))
            fi
        fi
    fi
done
