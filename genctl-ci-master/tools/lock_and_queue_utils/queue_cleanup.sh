#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
set -eu

# The following environment variables need to be set before executing the script:

# PATH_TO_GENCTL_CI, PATH_TO_RESOURCELOCK_REPO

# In addition the following environment variables are optional, if they are not set, they take default value
LOCK_POOL=${LOCK_POOL:-"release-deploy-lock"}

# Required in order to be able to consume getId function of queue_utils
mzonesStr=""


# Source utils
source ${PATH_TO_GENCTL_CI}/scripts/rebase_and_retrieve_metadata.sh
source ${PATH_TO_GENCTL_CI}/tools/lock_and_queue_utils/queue_utils.sh

RELEASE_LOCK_DIRECTORY=${PATH_TO_RESOURCELOCK_REPO}/$LOCK_POOL
QUEUE_FILES_FOLDERS="queue"
timestamp=$(date +"%Y-%m-%d_%H-%M-%S.%s")
initGit
getPipelineDetails
pushd $RELEASE_LOCK_DIRECTORY
rebase
getId id
echo ID is: $id
set +e
file=$(ls $QUEUE_FILES_FOLDERS | grep $id)
if [ -z "$file" ]
then
    echo queue file already deleted
else
    echo deleting queue file
    git rm $QUEUE_FILES_FOLDERS/*$id*
    commitAndPush "Verifying file $id removed from the queue $timestamp"
fi