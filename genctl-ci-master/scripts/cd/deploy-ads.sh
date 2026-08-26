#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2021
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
## deploy-ads.sh
##   Execute ADS deploy job
## 

ticket_data="$(jq tostring ticket/data.json)"
if [ -z "$ticket_data" ]; then
    echo "ERROR: Change Request number is a required argument"
    exit 1
fi

test_config="$(jq tostring test-config/config.json)"
if [ -z "$test_config" ]; then
    echo "ERROR: Test config is a required argument"
    exit 1
fi

if [[ -z "${JENKINS_USERNAME}" || -z "${JENKINS_API_KEY}" ]]; then
    echo "ERROR: JENKINS_USERNAME and JENKINS_API_KEY are required to be set"
    exit 1
fi

if [ -z "${SERVICENOW_URL}" ]; then
    echo "ERROR: SERVICENOW_URL is a required argument"
    exit 1
fi

if [ -z "${ADS_REPO_BRANCH}" ]; then
    echo "ERROR: ADS_REPO_BRANCH is a required argument"
    exit 1
fi

if [ -z "${ADS_GOKU_TAG}" ]; then
    echo "INFO: ADS_GOKU_TAG unset, using default"
fi

run_brt="false"
if [[ "$(cat run-brt/value 2> /dev/null)" == "true" ]]; then
    run_brt="true"
fi

urgent="false"
if [[ "$(cat label-urgent/value 2> /dev/null)" == "true" ]]; then
    urgent="true"
fi

threadID=$(cat slack-info/threadID)
user=$(cat slack-info/slack-handle)

genctl-ci-repo/scripts/cd/startJenkinsPipeline.sh "ticketData=${ticket_data}" "testConfig=${test_config}" "servicenowURL=${SERVICENOW_URL}" "slackThreadID=${threadID}" "slackUser=${user}" "slackGroup=${SLACK_GROUP}" "adsRepoBranch=${ADS_REPO_BRANCH}" "gokuVersion=${ADS_GOKU_TAG}" "runBRT=${run_brt}" "urgent=${urgent}" "parallel=${RUN_PARALLEL_DEPLOY}" "ibmCloudAccountID=${IBMCLOUD_ACCOUNT_ID}"
