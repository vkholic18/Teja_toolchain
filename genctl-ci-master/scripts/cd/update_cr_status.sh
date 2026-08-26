#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

set -eux

# Currently only featureflag and razee deploys are automated, so exit immediately if not
deploy_type="$(jq -r .DeployType ${TICKET_DIR}/data.json)"
if [[ "${deploy_type}" != "featureflag" && \
      "${deploy_type}" != "razee" ]]; then
  { echo skipping; } 2> /dev/null
  exit 0
fi

ticket_num=$(jq -r .CRNumber ${TICKET_DIR}/data.json)
# supported states are close, cancel, or implement
if [[ "$CR_STATE" == "close" || "$CR_STATE" == "cancel" ]]; then
  if [[  -f "failed-task/task" ]]; then
    CLOSE_NOTES="$(cat failed-task/task) failed"
    CLOSE_CATEGORY="successful_issues"
  fi
  ${PATH_TO_SERVICE_NOW_CLI} ${SNOW_CLI_FLAGS} -t ${MDS_SERVICENOW_IAM_APIKEY} ${CR_STATE} ${ticket_num} --implement=false --category ${CLOSE_CATEGORY} --notes "${CLOSE_NOTES}"
  if [[ "$SNOW_CLI_FLAGS" == "--test" ]]; then
    IBM_CLOUD_ENDPOINT="https://test.cloud.ibm.com"
  fi
  tasks=$(ibmcloud oss task list --cn ${ticket_num} --endpoint ${IBM_CLOUD_ENDPOINT} --apikey ${MDS_SERVICENOW_IAM_APIKEY} | awk '{print $1}' | tail -n+2)
  for task in $tasks; do
     ibmcloud oss task close --tn $task --cn ${ticket_num} --endpoint ${IBM_CLOUD_ENDPOINT} --apikey ${MDS_SERVICENOW_IAM_APIKEY}
  done
else
  ${PATH_TO_SERVICE_NOW_CLI} ${SNOW_CLI_FLAGS} -t ${MDS_SERVICENOW_IAM_APIKEY} ${CR_STATE} ${ticket_num}
fi
