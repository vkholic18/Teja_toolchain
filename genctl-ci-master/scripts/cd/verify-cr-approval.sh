#!/usr/bin/env bash

## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================

set -eu

ticket_num=$(jq -r '.[0].number' ${TICKET_DIR}/data.json)
ibmcloud oss cr get -n ${ticket_num} --apikey ${IBM_CLOUD_API_KEY} --endpoint ${IBM_CLOUD_ENDPOINT} --output json > cr-data.json
SN_URL="https://watson.service-now.com"
if [[ $IBM_CLOUD_ENDPOINT =~ 'test' ]]; then
  SN_URL="https://watsontest.service-now.com"
fi
timeout=$(date -d "+1 hour" +%s)
shopt -s nocasematch
while [[ $(jq -r .state cr-data.json) =~ ^(New|Assess|Authorize)$ ]]; do
  echo "Check if change request $ticket_num is approved"
  if [ $timeout -lt $(date +%s) ]; then
    echo "Timeout waiting change request approval: $SN_URL/nav_to.do?uri=change_request.do?sysparm_query=number=$ticket_num"
    exit 1
  fi
  sleep 60
  ibmcloud oss cr get -n ${ticket_num} --apikey ${IBM_CLOUD_API_KEY} --endpoint ${IBM_CLOUD_ENDPOINT} --output json > cr-data.json
done

# check if the ticket is not executable
if ! [[ $(jq -r .state cr-data.json) =~ ^(Scheduled|Implement)$ ]]; then
  echo "Canceling, because state of the change request is $(jq -r .state cr-data.json): $SN_URL/nav_to.do?uri=change_request.do?sysparm_query=number=$ticket_num"
  exit 1
fi

echo "Change request is approved: $SN_URL/nav_to.do?uri=change_request.do?sysparm_query=number=$ticket_num"
