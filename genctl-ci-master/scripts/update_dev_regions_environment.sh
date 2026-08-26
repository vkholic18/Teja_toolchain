#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# The following environment variables should be set before running the script
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO, PATH_TO_DEV_REGIONS_REPO
# GIT_PRIVATE_KEY, VAULT_GIT_CONFIG_USER_EMAIL, VAULT_GIT_CONFIG_USERNAME

# The following variables are optional
# PATH_TO_GH_RELEASE --> If not then it will be considered as directory not exists
# IBM_GITHUB_URI_BASE, DEV_REGIONS_BRANCH --> If not passed, will take default values
set -eu

export IBM_GITHUB_URI_BASE=${IBM_GITHUB_URI_BASE:-""}
export DEV_REGIONS_BRANCH=${DEV_REGIONS_BRANCH:-""}

export pipeline_file="${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml"

function init_git {
  # Configure ssh agent for git
  eval "$(ssh-agent -s)"
  ssh-add - <<< "${GIT_PRIVATE_KEY}"
  mkdir -p ~/.ssh
  ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
  git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
  git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"
}

function get_pipeline_values {
  key=$1
  value=$(yq -r ".deployment.${key} | select(. != null)" ${pipeline_file})
  echo "${value}"
}

# MAIN
init_git

# Get tags
if [[ -d ${PATH_TO_GH_RELEASE} ]]; then
  pushd ${PATH_TO_GH_RELEASE}
  GIT_SHA=$(cat commit_sha)
  GIT_TAG=$(cat tag)
  echo "GIT_TAG=${GIT_TAG}"
  popd
else
  #explicitly fetch tags
  pushd ${PATH_TO_WORKSPACE_REPO}
  git fetch --tags
  GIT_SHA=$(git rev-parse --verify HEAD)
  echo "GIT_SHA=${GIT_SHA}"
  GIT_TAG=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true
  echo "GIT_TAG=${GIT_TAG}"
  popd
fi

# Select which tagging format to use
if [ -z "$GIT_TAG" ]; then
  tag="$GIT_SHA"
else
  tag="$GIT_TAG"
fi
echo tag: ${tag}

# Gather values from pipeline.yaml
feature_flag=$(get_pipeline_values "feature_flag")
iks_cluster_name=$(get_pipeline_values "iks_cluster_name")
rule_tag=$(get_pipeline_values "rule_tag")
additional_target_dev_env=$(get_pipeline_values "additional_target_dev_env")

# Get additional_target_dev_env from pipeline.yaml from workspace_repo
additional_target_dev_env=${additional_target_dev_env:-}

# Need to be in dev-regions before running python script
pushd ${PATH_TO_DEV_REGIONS_REPO}

# Will try up to 5 times for successful push
for i in {1..3}
do
  # Always grab the latest - less chance of merge conflicts when pushing later
  git fetch origin
  git reset --hard origin/"${DEV_REGIONS_BRANCH}"
  
  # Run python script to update the environment files in dev-regions repo
  python3 ${PATH_TO_GENCTL_CI}/scripts/update_dev_regions_environment.py ${feature_flag} ${iks_cluster_name} ${tag} ${PATH_TO_DEV_REGIONS_REPO} "${rule_tag}" "${additional_target_dev_env}"
  
  # Commit if there are changes
  if [ -z "$(git status -uno --porcelain)" ]; then
    echo "Nothing to commit"
    exit 0
  else
    timestamp=$(date "+%Y-%m-%d")
    message="chore: CD-0000: Set ${feature_flag} to ${tag} on ${timestamp}"
    git add --all
    git commit -m "${message}"
    if git push origin HEAD:"${DEV_REGIONS_BRANCH}"; then
      echo "Attempt $i: git push succeeded"
      exit 0
    else
      echo "Attempt $i: git push failed."
      sleep 30
    fi
  fi
done
exit 1
