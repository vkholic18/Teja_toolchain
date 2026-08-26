#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2020, 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

IS_ONE_PIPELINE_RUN=${IS_ONE_PIPELINE_RUN:-"false"}
PIPELINE_REPO_ORG=${PIPELINE_REPO_ORG:-""}
PIPELINE_REPO_NAME=${PIPELINE_REPO_NAME:-""}
PIPELINE_TYPE=${PIPELINE_TYPE:-""}
PIPELINE_ID=${PIPELINE_ID:-""}
PIPELINE_RUN_ID=${PIPELINE_RUN_ID:-""}
BUILD_NUMBER=${BUILD_NUMBER:-""}
PATH_TO_RESOURCELOCK_REPO=${PATH_TO_RESOURCELOCK_REPO:-"releasedeploy-lock-environments"}
LOCK_POOL=${LOCK_POOL:-"release-deploy-lock"}

# This Script is for doing common git setup and rebase commands and also get metadata from pipeline when using metadata resource

function initGit {
  eval "$(ssh-agent -s)"
  ssh-add - <<< "${GIT_PRIVATE_KEY}"
  mkdir -p ~/.ssh
  ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
  git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
  git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"
}
function rebase {
  git stash > /dev/null
  git fetch > /dev/null
  git rebase origin/master > /dev/null
}
function getPipelineDetails {
  echo Getting env and mzone
  UNCLAIMED_DIR="unclaimed"
  QUEUE_FILES_FOLDERS="queue"
  CLAIMED_DIR="claimed"
  if [[ ${IS_ONE_PIPELINE_RUN} == "false" ]]
  then
    pipelineName=$(cat metadata/build_pipeline_name)
    jobName=$(cat metadata/build_job_name)
    buildName=$(cat metadata/build_name)
    buildId=$(cat metadata/build_id)
    buildTeamName=$(cat metadata/build_team_name)
    serverURL=$(cat metadata/atc_external_url)
    serverName=${serverURL#*//}
  else
    # If we are in One Pipeline, we use the OnePipeline vars
    pipelineName="${PIPELINE_REPO_ORG}_${PIPELINE_REPO_NAME}_${PIPELINE_TYPE}"
    jobName="${PIPELINE_ID}_${PIPELINE_RUN_ID}"
    buildName="${BUILD_NUMBER}"
    buildId="${PIPELINE_RUN_ID}"
    serverName=""
  fi
  gitMsg="${serverName}/${pipelineName}/${jobName} build ${buildName} claiming"
}
function getMzone {
  if [[ -z ${RELEASE_LOCK_DIRECTORY:-} ]]
  then
    RELEASE_LOCK_DIRECTORY=${PATH_TO_RESOURCELOCK_REPO}/${LOCK_POOL}
  fi
  pushd $RELEASE_LOCK_DIRECTORY
  echo gitMsg: ${gitMsg}
  envStr=$(git log --since="7 hour ago" | grep -m1 " ${gitMsg}")
  envName=$(echo ${envStr} | rev | cut -d ":" -f 1 | rev)
  mzoneName=$(cat $CLAIMED_DIR/${envName})
  echo ${mzoneName}
  popd
}

function commitAndPush {
  git commit -m "$1"
  for i in {1..5}
  do
    if git push origin HEAD:master
    then
      echo "git push succeeded"
      return;
    else
      echo "git push failed. Trying again"
      git fetch
      git rebase origin/master
    fi
  done
  exit 1
}
