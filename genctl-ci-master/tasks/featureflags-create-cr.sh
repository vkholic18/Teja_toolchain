#!/usr/bin/env bash

## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
set -eu

source ${PATH_TO_GENCTL_CI}/scripts/retry.sh
retry curl -fsSL https://clis.cloud.ibm.com/install/linux | sh
retry ibmcloud plugin repo-add "IBM Cloud Internal" https://plugins.test.cloud.ibm.com
retry ibmcloud plugin install oss-tooling -r "IBM Cloud Internal"

if [[ "$OSTYPE" == "darwin"* ]]; then
   date () { gdate "$@"; }
fi

declare -A service_env
service_env["global-staging"]="pre_prod"
service_env["global-prod"]="production"
if ! [[ -v service_env["$WORKSPACE_REPO_NAME"] ]]; then
  echo "Validation record for workspace name '$WORKSPACE_REPO_NAME' does not exist."
  exit 1
fi

CURRENT_PATH="$PWD"
cd ${PATH_TO_WORKSPACE}
latest_commit_id=$(git rev-parse HEAD)
pr_url="https://github.ibm.com/nextgen-environments/$WORKSPACE_REPO_NAME/commit/$latest_commit_id"
commit_msg=$(git log --pretty='format:%Creset%s' --no-merges -1)

PR_URL=$(curl -L \
-H "Accept: application/vnd.github.groot-preview+json" \
-H "Authorization: token $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: 2022-11-28" \
"https://github.ibm.com/api/v3/repos/nextgen-environments/$WORKSPACE_REPO_NAME/commits/$latest_commit_id/pulls" \
| jq -r '.[0].url')

PR_Details=$(curl -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  $PR_URL | jq -r '.body')
cd ${CURRENT_PATH}

purpose=" ${commit_msg}
 Code change link: ${pr_url}
 ${PR_Details}"

for i in {1..5}
do
  ibmcloud oss cr create --apikey ${IBM_CLOUD_API_KEY} --endpoint ${IBM_CLOUD_ENDPOINT} -s is-platform-integration --audience private \
  --backout_plan "Submit a new Pull Request that reverts to the previous Feature Flag values" --impact "No impact expected" --region "Other" \
  --purpose "${purpose}" --service_environment "${service_env["$WORKSPACE_REPO_NAME"]}" --validation_record  "NA" --service_environment_detail "global" \
  --description "[AUTOMATED] This is a fully automated change. The ticket is auto approved and the change will execute immediately." \
  --planned_start PT0S --assigned_to ${IBM_CLOUD_USERNAME} --priority "low" --deployment_impact "small" --deployment_method "fully_automated" \
  --planned_duration 1 --output json 1> ${TICKET_DIR}/data.json && break || sleep 2
done
if [ "$?" -ne 0 ]; then
    echo "Failed to create ServiceNow change request."
    exit 1
fi

ticket_num=$(jq -r '.[0].number' ${TICKET_DIR}/data.json)
if [[ -n "$ticket_num" ]]; then
  SN_URL="https://watson.service-now.com"
  if [[ $IBM_CLOUD_ENDPOINT =~ 'test' ]]; then
    SN_URL="https://watsontest.service-now.com"
  fi
  echo "ServiceNow change request created: $SN_URL/nav_to.do?uri=change_request.do?sysparm_query=number=$ticket_num"
else
  echo "Failed to find the change request id"
  cat ${TICKET_DIR}/data.json
  exit 1
fi
