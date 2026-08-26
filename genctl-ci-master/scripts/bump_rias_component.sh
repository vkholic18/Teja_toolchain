#!/usr/bin/env bash

##
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
##

# The following environment variables need to be set before executing the script:
#Required
#PATH_TO_GENCTL_CI 
#PATH_TO_WORKSPACE_REPO 
#VAULT_GIT_CONFIG_USER_EMAIL 
#VAULT_GIT_CONFIG_USERNAME
#GIT_PRIVATE_KEY
#REPO_NAME_TO_BUMP, ORG_NAME_TO_BUMP, BRANCH_TO_BUMP

#Optional
# RIAS_COMPONENT
# IBM_GITHUB_URI_BASE:
# HOTFIX_MAJOR_COMPONENT
# COMPONENT:  Not sure where this is being used. 
# VERSION_FILE: Not sure where this is being used. 

#set flag
set -u
export RIAS_COMPONENT=${RIAS_COMPONENT:-""}
export IBM_GITHUB_URI_BASE=${IBM_GITHUB_URI_BASE:-""}
export HOTFIX_MAJOR_COMPONENT=${HOTFIX_MAJOR_COMPONENT:-""}
export COMPONENT=${COMPONENT:-""}
export VERSION_FILE=${VERSION_FILE:-""}

# Skip rias release inventory bump if the pipeline is for a non-rias hotfix
if [[ "$HOTFIX_MAJOR_COMPONENT" != "" && "${HOTFIX_MAJOR_COMPONENT}-release" != "$REPO_NAME_TO_BUMP" ]]; then
  echo "This is a hotfix pipeline for ${HOTFIX_MAJOR_COMPONENT}; skipping ${REPO_NAME_TO_BUMP} inventory bump"
  exit 0
fi

# Setup for interaction with git remote
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

# Use gh tool to create PR with label and login
gh auth login --hostname github.ibm.com --with-token <<< ${GH_TOKEN}

root_dir=${PWD}
# Clone the change versions repo that we will be updating
git clone ${IBM_GITHUB_URI_BASE}:${ORG_NAME_TO_BUMP}/${REPO_NAME_TO_BUMP}.git -b ${BRANCH_TO_BUMP}

# Check if component is part of rias/rias-etcd
set +e
python3 ${PATH_TO_GENCTL_CI}/scripts/exist_in_inventory_json.py ${RIAS_COMPONENT} ${REPO_NAME_TO_BUMP}/component-input/inventory.json
rias_shared_result=$?
echo $rias_shared_result
set -e

if [[ ${rias_shared_result} == 0 ]]; then
  echo "${RIAS_COMPONENT} is a ${REPO_NAME_TO_BUMP} component."

  # update inventory file
  #${PATH_TO_GENCTL_CI}/scripts/update_vetted_version.py ${REPO_NAME_TO_BUMP}/${VERSION_FILE} ${COMPONENT} ${IMAGE_TAG}
  pushd ${PATH_TO_WORKSPACE_REPO}
  component_hash_new=`git rev-parse --verify HEAD`
  echo new component git ref: $component_hash_new
  popd
  url=
  ${PATH_TO_GENCTL_CI}/scripts/update_inventory_json.py ${RIAS_COMPONENT} $component_hash_new "${url}" ${REPO_NAME_TO_BUMP}/component-input/inventory.json ${REPO_NAME_TO_BUMP}/component-input/inventory.json

  pushd ${REPO_NAME_TO_BUMP}
  cat component-input/inventory.json
  if git diff-index --quiet HEAD; then
    echo there are no changes in a ${REPO_NAME_TO_BUMP}
    exit 0
  else
    current_timestamp=$(date +%Y%m%d%H%M%S)
    git stash
    git pull --rebase origin
    git checkout -b CIGC-5279-${component_hash_new:0:8}-${current_timestamp}
    git stash apply
    git add component-input/inventory.json
    git commit -m "chore: CIGC-5279: Update inventory version for ${RIAS_COMPONENT}"
    git push origin CIGC-5279-${component_hash_new:0:8}-${current_timestamp}
    gh pr create --title "chore: CIGC-5279: Update inventory version for ${RIAS_COMPONENT}" --body "chore: CIGC-5279: Update inventory version for ${RIAS_COMPONENT} created automatically by VPC CI automation" --label "for-ci-only-ignore-build-ut"
    popd
  fi

else
  echo "${RIAS_COMPONENT} is not a ${REPO_NAME_TO_BUMP} component; skipping..."
fi
