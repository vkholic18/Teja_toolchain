#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script reads the PR title and gets the environment.yaml from master and deployed_artifacts branches.

# =============================================================================================
set -eux

# capture all the PR metadata in TRIGGER_PAYLOAD_PATH
TRIGGER_PAYLOAD_PATH=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "$PR_URL" | jq )
promotion_repo_name=$(echo ${TRIGGER_PAYLOAD_PATH} | jq .title | awk '{print $4}')

pushd ${WORKSPACE}
mkdir promotion-repo

echo "promotion_repo_name: ${promotion_repo_name}"
echo ${promotion_repo_name} > promotion-repo/promotion_repo_name

echo "Cloning promotion repo"
mkdir ${promotion_repo_name}
git clone ${IBM_GITHUB_URI_BASE}:${CD_PROMOTION_FROM_ORG}/${promotion_repo_name}.git ${promotion_repo_name}

# Get environment.yaml from master branch
cp ${promotion_repo_name}/environment.yaml promotion-repo/master_environment.yaml

cd ${promotion_repo_name}
if ! git rev-parse --verify origin/deployed_artifacts; then
  echo "could not find deployed_artifacts branch in ${promotion_repo_name}"
  exit 0
fi

# Get environment.yaml from 'deployed_artifacts' branch
git checkout deployed_artifacts
cd ..
cp ${promotion_repo_name}/environment.yaml promotion-repo/deployed_artifacts_environment.yaml
