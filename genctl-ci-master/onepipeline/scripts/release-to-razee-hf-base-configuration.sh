#!/usr/bin/env bash

##
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
##

# The following environment variables need to be set before executing the script:
#Required
#PATH_TO_WORKSPACE_REPO
#GIT_PRIVATE_KEY
#PATH_TO_GENCTL_CI
#COMPONENT
#VAULT_GIT_CONFIG_USER_EMAIL
#VAULT_GIT_CONFIG_USERNAME
#GIT_PRIVATE_KEY
#GENCTL_VETTED_VERSIONS_REPO_NAME
#RAZEE_HOTFIX_NEXTGEN_ENVIRONMENT_FILE


#set flag
set -u

pushd ${PATH_TO_WORKSPACE_REPO}
export GIT_SHA=$(git rev-parse --verify HEAD)
echo "GIT_SHA=${GIT_SHA}"
git_tag=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true
echo "git_tag=${git_tag}"
popd

# Setup for interaction with git remote
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

# Check if pipeline.yaml file exists
if [[ -f ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml ]]; then
  LAUNCH_DARKLY_FEATURE_FLAG=$(yq -r '.deployment.feature_flag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
else
  echo "hack/ci/pipeline.yaml does not exist. Exiting ..."
  exit 1
fi
export LAUNCH_DARKLY_FEATURE_FLAG=${LAUNCH_DARKLY_FEATURE_FLAG}
echo "LAUNCH_DARKLY_FEATURE_FLAG=${LAUNCH_DARKLY_FEATURE_FLAG}"

# Clone the change versions repo that we will be updating
git clone ${IBM_GITHUB_URI_BASE}:${GENCTL_VETTED_VERSIONS_ORG_NAME}/${GENCTL_VETTED_VERSIONS_REPO_NAME}.git -b ${GENCTL_VETTED_VERSIONS_BRANCH_NAME}

echo ${RAZEE_HOTFIX_NEXTGEN_ENVIRONMENT_FILE}
# update version file
if [[ ! -z "$git_tag" ]]; then
  ${PATH_TO_GENCTL_CI}/scripts/release-to-razee-hf-base-configuration.py ${GENCTL_VETTED_VERSIONS_REPO_NAME}/${RAZEE_HOTFIX_NEXTGEN_ENVIRONMENT_FILE} ${LAUNCH_DARKLY_FEATURE_FLAG} ${git_tag}
else
  ${PATH_TO_GENCTL_CI}/scripts/release-to-razee-hf-base-configuration.py ${GENCTL_VETTED_VERSIONS_REPO_NAME}/${RAZEE_HOTFIX_NEXTGEN_ENVIRONMENT_FILE} ${LAUNCH_DARKLY_FEATURE_FLAG} ${GIT_SHA}
fi

pushd ${GENCTL_VETTED_VERSIONS_REPO_NAME}
git add ${RAZEE_HOTFIX_NEXTGEN_ENVIRONMENT_FILE}
git commit -m "Update vetted version for ${COMPONENT}"
git pull --rebase origin
git push origin
popd
