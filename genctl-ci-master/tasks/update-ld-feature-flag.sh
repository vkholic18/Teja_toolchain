#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2020-2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# The following environment variables need to be set before executing the script:
#PATH_TO_GENCTL_CI: Path to genctl-ci repository
#PATH_TO_WORKSPACE_REPO: Path to workspace repository
#AUTH_TOKEN: api key to access LaunchDarkly
#LAUNCH_DARKLY_ENVIRONMENT (e.g development)
## tag for LD rule describe which environment (mzone) the feature is deployed. defined in ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml
#LAUNCH_DARKLY_RULE_TAG (e.g. rias-ng-us-south-dal-dev73-etcd,mzone720a)
## feature flag name for this workspace defined in ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml
#LAUNCH_DARKLY_FEATURE_FLAG (e.g. rias-inception-version)
## if true use the variation in a default rule
#LAUNCH_DARKLY_USE_IN_DEFAULT_RULE
## if true create a hash variation only
#LAUNCH_DARKLY_CREATE_VARIATION_ONLY:
## empty if running in a regular (not a hotfix) pipeline
#HOTFIX_MAJOR_COMPONENT
# empty if running in a regular (not a hotfix) pipeline, true if running razee hotfix
#RAZEE_HOTFIX
#GIT_PRIVATE_KEY: ((ghe-private-key))
#DEV_REGIONS parameters to set vetted versions in https://github.ibm.com/nextgen-environments/dev-regions/blob/master/vetted-versions.yaml
#PATH_TO_DEV_REGIONS_REPO
#DEV_REGIONS_ORG_NAME:
#DEV_REGIONS_REPO_NAME:
#DEV_REGIONS_BRANCH:
#DEV_REGIONS_FILE:

set -ex
source ${PATH_TO_GENCTL_CI}/scripts/retry.sh
export build_root="${PWD}"
# Configure ssh agent for git - used to do a git fetch on tags to get the most updated tags
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
if [[ -d gh-release ]]; then
  pushd gh-release
  export GIT_SHA=$(cat commit_sha)
  git_tag=$(cat tag)
  echo "git_tag=${git_tag}"
  popd
else
  #explicitly fetch tags
  pushd ${PATH_TO_WORKSPACE_REPO}
  git fetch --tags
  export GIT_SHA=$(git rev-parse --verify HEAD)
  echo "GIT_SHA=${GIT_SHA}"
  git_tag=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true
  echo "git_tag=${git_tag}"
  popd
fi
if [[ "${RAZEE_HOTFIX}" == "true" && -f ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml ]]; then
  echo "This is a hotfix pipeline. LAUNCH_DARKLY_RULE_TAG should be empty to create variation only but not update the HF variation in the rule"
  LAUNCH_DARKLY_FEATURE_FLAG=$(yq -r '.deployment.feature_flag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
  LAUNCH_DARKLY_RULE_TAG=""
elif [[ -f ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml ]]; then
  LAUNCH_DARKLY_FEATURE_FLAG=$(yq -r '.deployment.feature_flag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
  LAUNCH_DARKLY_RULE_TAG=$(yq -r '.deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
else
  LAUNCH_DARKLY_FEATURE_FLAG=""
  LAUNCH_DARKLY_RULE_TAG=""
fi
echo "LAUNCH_DARKLY_FEATURE_FLAG=${LAUNCH_DARKLY_FEATURE_FLAG}"
echo "LAUNCH_DARKLY_RULE_TAG=${LAUNCH_DARKLY_RULE_TAG}"

if [ -z "${LAUNCH_DARKLY_FEATURE_FLAG}" ]; then
  echo "Error: LAUNCH_DARKLY_FEATURE_FLAG is not defined. Exiting ..."
  exit 1
fi
retry python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/featureflags/requirements.txt

#create variation and use in default rule (runs on merge to MASTER pipelines)
if [ "${LAUNCH_DARKLY_USE_IN_DEFAULT_RULE}" = "true" ]; then
  if [ "${RAZEE_HOTFIX}" == "true" ]; then
    echo "This is a hotfix pipeline. New variation will be created but not updated as a default rule."
    if [[ ! -z "$git_tag" ]]; then
      echo "No feature flag update"
    fi
  else
    #if tag exists, create sha and tag variation, but use tag in rule
    if [[ ! -z "$git_tag" ]]; then
      echo "Updating LD feature flag rule in merge to MASTER with git tag and git sha"
      ${PATH_TO_GENCTL_CI}/scripts/update_vetted_versions/update_vetted_versions.sh ${DEV_REGIONS_ORG_NAME} ${DEV_REGIONS_REPO_NAME} ${PATH_TO_DEV_REGIONS_REPO} ${PATH_TO_GENCTL_CI} ${DEV_REGIONS_BRANCH} ${LAUNCH_DARKLY_FEATURE_FLAG} ${git_tag} ${DEV_REGIONS_FILE} "false" ${VAULT_GIT_CONFIG_USERNAME:-} ${VAULT_GIT_CONFIG_USER_EMAIL:-}
    #create and use sha varitation only
    else
      echo "Updating LD feature flag rule in merge to MASTER with git sha only"
      ${PATH_TO_GENCTL_CI}/scripts/update_vetted_versions/update_vetted_versions.sh ${DEV_REGIONS_ORG_NAME} ${DEV_REGIONS_REPO_NAME} ${PATH_TO_DEV_REGIONS_REPO} ${PATH_TO_GENCTL_CI} ${DEV_REGIONS_BRANCH} ${LAUNCH_DARKLY_FEATURE_FLAG} ${GIT_SHA} ${DEV_REGIONS_FILE} "false" ${VAULT_GIT_CONFIG_USERNAME:-} ${VAULT_GIT_CONFIG_USER_EMAIL:-}
    fi
  fi
elif [ "${LAUNCH_DARKLY_CREATE_VARIATION_ONLY}" = "true" ]; then
   echo "Updating LD feature flag only with new variation"
else
  #create variation and try to use it in the rule with LAUNCH_DARKLY_RULE_TAG tag
  if [ "${LAUNCH_DARKLY_RULE_TAG}" != "" ]; then
    for rule_tag in $(echo ${LAUNCH_DARKLY_RULE_TAG} | tr "," "\n")
    do
      if [[ -z "${rule_tag}" ]]; then
        continue
      fi

      #if tag exists, create sha and tag variation, but use tag in rule
      if [[ ! -z "$git_tag" ]]; then
        echo "Updating LD feature flag rule in merge to dev-integration with git tag and git sha"
      #create and use sha varitation only
      else
        echo "Updating LD feature flag rule in merge to dev-integration with git sha only"
      fi
    done
  #create variation only
  else
    echo "No feature flag update"
  fi
fi
