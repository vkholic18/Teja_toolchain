#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# The following environment variables should be defined before executing this script

# PATH_TO_GENCTL_CI, PATH_TO_BRT_LOCKS

export LOCK_POOL=${LOCK_POOL:-"release-deploy-lock"}
export WAIT_BEFORE_RETRY=${WAIT_BEFORE_RETRY:-300}

function getId {
    echo in getId
    local  __idvar=$1
    eval $__idvar="$pipelineName-$jobName-$buildName-$buildId-$serverName"
}

function getUnclaimedEnv {
    local  __resultvar=$1
    eval $__resultvar="$(ls $UNCLAIMED_DIR | tail -1)"
}

function getFirstInQueue {
    local  __resultvar=$1
    eval $__resultvar="$(ls $QUEUE_FILES_FOLDERS | sort -n | head -1)"
}

if [[ -z ${LOCK_POOL:-} ]]
then
    LOCK_POOL=release-deploy-lock
fi

source ${PATH_TO_GENCTL_CI}/scripts/rebase_and_retrieve_metadata.sh
source ${PATH_TO_GENCTL_CI}/scripts/retry.sh

RELEASE_LOCK_DIRECTORY=${PATH_TO_RESOURCELOCK_REPO}/$LOCK_POOL
QUEUE_FILES_FOLDERS="queue"
UNCLAIMED_DIR="unclaimed"

pushd $RELEASE_LOCK_DIRECTORY
nextInQueue="";

for (( c=1; c<=2; c++ ))
do
    retry rebase
    getUnclaimedEnv result
    envFile=$result
    getFirstInQueue currNextInQueue
    if [ $envFile ] && [ $currNextInQueue ]; then
        echo "queue is not empty and there is available env"
        getFirstInQueue currNextInQueue
        currNextInQueue=$(echo $currNextInQueue | cut -d ":" -f 2)
        if [[ $currNextInQueue != $nextInQueue ]];then
            echo "Check queue again in $WAIT_BEFORE_RETRY seconds before deleting queue file - $currNextInQueue"
            nextInQueue=$currNextInQueue
        else
            echo "Validated $nextInQueue is stuck - deleting"
            retry git rm $QUEUE_FILES_FOLDERS/*$nextInQueue
            retry commitAndPush "Remove stuck $nextInQueue"
            nextInQueue=""
        fi
        sleep ${WAIT_BEFORE_RETRY}
    else
        echo "Nothing to clean from queue"
        exit 0
    fi
done
