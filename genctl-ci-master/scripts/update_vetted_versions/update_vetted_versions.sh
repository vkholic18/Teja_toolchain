#!/bin/bash
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

#Inputs:
# GIT_ORG: Org for the destination repo which contains the file to be updated
GIT_ORG=$1
# GIT_REPO: Destination repo which containst the file to be updated
GIT_REPO=$2
# REPO_DIR: The directory in the CI system where the repo is cloned
REPO_DIR=$3
# GENCTL_CI_DIR: Directory in CI where genctl-ci repo is cloned so that we can
# use the helper scripts
GENCTL_CI_DIR=$4
# PUSH_TO_BRANCH: Branch that the change will be pushed to
PUSH_TO_BRANCH=$5
# WORKSPACE_TAG: Tag that will be updated in the FILE_TO_CHANGE
WORKSPACE_TAG=$6
# WORKSPACE_TAG_VALUE: Value for WORKSPACE_TAG that will be updated in FILE_TO_CHANGE
WORKSPACE_TAG_VALUE=$7
# FILE_TO_CHANGE: Yaml file containing WORKSPACE_TAG and WORKSPACE_TAG_VALUE which will
# be updated by this script
FILE_TO_CHANGE=$8
# IS_RELEASE_BUNDLE: If true, the WORKSPACE_TAG belongs to release bundle, so the
# appropriate helper script for handling release bundles will be called. If false,
# WORKSPACE_TAG is a razee tag and appropriate helper script to update the
# WORKSPACE_TAG will be called
IS_RELEASE_BUNDLE=$9
# VAULT_GIT_CONFIG_USERNAME: git username to use for the checkin
VAULT_GIT_CONFIG_USERNAME=$10
# VAULT_GIT_CONFIG_USER_EMAIL: git email to use for the checkin
VAULT_GIT_CONFIG_USER_EMAIL=$11

# This script updates the FILE_TO_CHANGE in the GIT_ORG and GIT_REPO that has
# been cloned to the REPO_DIR with the new value of WORKSPACE_TAG and WORKSPACE_TAG_VALUE.
# It uses helper scripts in GENCTL_CI_DIR to update the yaml file. It will merge the change
# to the PUSH_TO_BRANCH. If the merge fails, it will retry the transaction 5 times before
# failing permanently.

HAS_UPDATE_SUCCEEDED=0


echo "Logging provided runtime configuration. "
echo "GIT_ORG=${GIT_ORG}"
echo "GIT_REPO=${GIT_REPO}"
echo "REPO_DIR=${REPO_DIR}"
echo "PUSH_TO_BRANCH=${PUSH_TO_BRANCH}"
echo "WORKSPACE_TAG=${WORKSPACE_TAG}"
echo "WORKSPACE_TAG_VALUE=${WORKSPACE_TAG_VALUE}"
echo "FILE_TO_CHANGE=${FILE_TO_CHANGE}"
echo "IS_RELEASE_BUNDLE=${IS_RELEASE_BUNDLE}"
echo "VAULT_GIT_CONFIG_USERNAME=${VAULT_GIT_CONFIG_USERNAME}"
echo "VAULT_GIT_CONFIG_USER_EMAIL=${VAULT_GIT_CONFIG_USER_EMAIL}"

# this function tries to push the changes to the PUSH_TO_BRANCH. If it fails
# due to conflict it will do a hard reset on the branch and set the HAS_UPDATE_SUCCEEDED
# to 0. If it succeeds, it will set HAS_UPDATE_SUCCEEDED to 1.

push_changes_to_branch()
{
    timestamp=`date "+%Y-%m-%d"`
    message="chore: CD-0000: Set the ${WORKSPACE_TAG} to ${WORKSPACE_TAG_VALUE} ${timestamp}"
    echo "commiting ${FILE_TO_CHANGE} file ..."

    git add ${FILE_TO_CHANGE}
    git commit -m "$message"

    echo "pushing ${PUSH_TO_BRANCH} updates to github"
    git push --set-upstream origin $PUSH_TO_BRANCH
    if [[ $? -ne 0 ]]
    then
        echo "failed to push to github"
        HAS_UPDATE_SUCCEEDED=0
        git reset --hard origin/${PUSH_TO_BRANCH}
        return
    fi
    HAS_UPDATE_SUCCEEDED=1
    echo "Setting has_update_succeeded to ${HAS_UPDATE_SUCCEEDED}"
}

# This function sets the git username/password, gets the latest code and
# calls the appropriate helper script to update the WORKSPACE_TAG
# and WORKSPACE_TAG_VALUE

update_vetted_version()
{
    echo $PWD
    git remote -v

    git config --global user.email "$VAULT_GIT_CONFIG_USER_EMAIL"
    git config --global user.name "$VAULT_GIT_CONFIG_USERNAME"

    echo "git fetch origin"
    git fetch origin

    echo "git checkout ${PUSH_TO_BRANCH} origin/${PUSH_TO_BRANCH}"
    git checkout ${PUSH_TO_BRANCH}

    echo "git status"
    git status

    if [[ "$IS_RELEASE_BUNDLE" == "false" ]]; then
        echo "Calling python script to update the vetted-versions.yaml file with razee related data"
        python3 ${GENCTL_CI_DIR}/scripts/release-to-razee-hf-base-configuration.py ${PWD}/vetted-versions.yaml $WORKSPACE_TAG $WORKSPACE_TAG_VALUE
    else
        echo "Calling python script to update the vetted-version.yaml file with release bundle related data "
        python3 ${GENCTL_CI_DIR}/scripts/update_vetted_version.py ${PWD}/vetted-versions.yaml $WORKSPACE_TAG $WORKSPACE_TAG_VALUE
    fi
    echo "git status after modifying the vetted-versions.yaml"
    git status

    push_changes_to_branch
}

pushd $REPO_DIR

NUM_TRIES=0

while [ $HAS_UPDATE_SUCCEEDED -eq 0 ] && [ $NUM_TRIES -le 5 ]; do
    echo "Trying to Update vetted_version $NUM_TRIES..."
    update_vetted_version
    NUM_TRIES=$((NUM_TRIES+1))
done

if [ $HAS_UPDATE_SUCCEEDED -eq 1 ];then
    echo "Updated vetted_version successfully"
fi

#popd $REPO_DIR
