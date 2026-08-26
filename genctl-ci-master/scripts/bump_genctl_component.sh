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
# PATH_TO_GENCTL_CI
# PATH_TO_WORKSPACE_REPO
# GIT_PRIVATE_KEY
# VAULT_GIT_CONFIG_USER_EMAIL
# VAULT_GIT_CONFIG_USERNAME

#Optional
# GENCTL_RELEASE_REPO_NAME
# GENCTL_RELEASE_ORG_NAME
# GENCTL_RELEASE_BRANCH_NAME
# GENCTL_COMPONENT
# HOTFIX_MAJOR_COMPONENT
# COMPONENT
# VERSION_FILE
# IBM_GITHUB_URI_BASE:

export GENCTL_RELEASE_REPO_NAME=${GENCTL_RELEASE_REPO_NAME:-""}
export GENCTL_RELEASE_ORG_NAME=${GENCTL_RELEASE_ORG_NAME:-""}
export GENCTL_RELEASE_BRANCH_NAME=${GENCTL_RELEASE_BRANCH_NAME:-""}
export GENCTL_COMPONENT=${GENCTL_COMPONENT:-""}
export HOTFIX_MAJOR_COMPONENT=${HOTFIX_MAJOR_COMPONENT:-""}
export COMPONENT=${COMPONENT:-""}
export VERSION_FILE=${VERSION_FILE:-""}
export IBM_GITHUB_URI_BASE=${IBM_GITHUB_URI_BASE:-""}

# Skip genctl release submodule bump if it is orda pipeline (legacy hotfixes)
if [[ "$GENCTL_RELEASE_METHOD" != "no-orda" ]]; then
    echo "This pipeline is a legacy orda genctl release, skipping genctl inventory update "
    exit 0
else
    echo "Release component with GENCTL_RELEASE_METHOD=${GENCTL_RELEASE_METHOD}"
fi
# Skip genctl release submodule bump if the pipeline is for a non-genctl hotfix
if [[ "$HOTFIX_MAJOR_COMPONENT" != "" && "$HOTFIX_MAJOR_COMPONENT" != "genctl" ]]; then
    echo "This is a hotfix pipeline for ${HOTFIX_MAJOR_COMPONENT}; skipping genctl submodule bump"
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

if [[ -d repo-updated ]]
then
    echo "repo-updated exists"
else
    echo "repo-updated does not exist, need to create..."
    mkdir -p repo-updated
fi

# Clone the change versions repo that we will be updating
git clone ${IBM_GITHUB_URI_BASE}:${GENCTL_RELEASE_ORG_NAME}/${GENCTL_RELEASE_REPO_NAME}.git -b ${GENCTL_RELEASE_BRANCH_NAME} repo-updated

# Check if component is part of genctl release
set +e
python3 ${PATH_TO_GENCTL_CI}/scripts/exist_in_inventory_json.py ${GENCTL_COMPONENT} repo-updated/component-input/inventory.json
genctl_shared_result=$?
echo $genctl_shared_result
set -e

if [[ ${genctl_shared_result} == 0 ]]; then
    echo "${GENCTL_COMPONENT} is a ${GENCTL_RELEASE_REPO_NAME} component."
    pushd ${PATH_TO_WORKSPACE_REPO}
    component_hash_new=`git rev-parse --verify HEAD`
    echo new component git ref: $component_hash_new
    popd
    url=
    ${PATH_TO_GENCTL_CI}/scripts/update_inventory_json.py ${GENCTL_COMPONENT} $component_hash_new "${url}" repo-updated/component-input/inventory.json repo-updated/component-input/inventory.json
    pushd repo-updated
    cat component-input/inventory.json
    set +e
    git diff-index --quiet HEAD
    diff_status=$?
    set -e
    if [ ${diff_status} -eq 0 ]; then
        echo there are no changes in a ${GENCTL_RELEASE_REPO_NAME}
        exit 0
    else
        current_timestamp=$(date +%Y%m%d%H%M%S)
        git stash
        git pull --rebase origin
        git checkout -b CIGC-5279-${component_hash_new:0:8}-${current_timestamp}
        git stash apply
        git add component-input/inventory.json
        git commit -m "chore: CIGC-5279: Update inventory version for ${GENCTL_COMPONENT}"
        git push origin CIGC-5279-${component_hash_new:0:8}-${current_timestamp}
        gh pr create --title "chore: CIGC-5279: Update inventory version for ${GENCTL_COMPONENT}" --body "chore: CIGC-5279: Update inventory version for ${GENCTL_COMPONENT} created automatically by VPC CI automation" --label "for-ci-only-ignore-build-ut"
        popd
    fi

else
    echo "${GENCTL_COMPONENT} is not a ${GENCTL_RELEASE_REPO_NAME} component; skipping..."
fi
