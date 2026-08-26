#!/bin/bash -eux
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2021
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
## expected environment vars
##  JENKINS_USERNAME: ((ads-jenkins-username))
##  JENKINS_API_KEY:  ((ads-jenkins-apikey))
##  JOB_NAME: ((ads-upload-ff-job-name))
##  JENKINS_URL: https://sys-wcp-genctl-team-cd-jenkins.swg-devops.com
##  QUEUE_TIMEOUT: 3600 #60 minutes
##  ARTIFACTORY_ID: wcp-genctl-sandbox-generic-local # hard-code to temporary path for now, until final path is revealed later
##  LD_API_KEY_ID: ((launch-darkly-relay-proxy-id))
##  ENVIRONMENT: ((launch-darkly-upload-environment))
##  PFX_FILE_ID: signing-pfx-file

set -euxo pipefail

# this task only deploys featureflag or iks razee deploys, so exit immediately if not
deploy_type="$(jq -r .DeployType ticket/data.json)"
provider_type="$(jq -r .ProviderType ticket/data.json)"
if [[ "${deploy_type}" != "featureflag" && \
      ( "${provider_type}" != "iks" || "${deploy_type}" != "razee" ) ]]; then
  { echo skipping; } 2> /dev/null
  exit 0
fi


{ echo -e "\n\n\nUPLOADING LAUNCHDARKLY\n"; } 2> /dev/null
genctl-ci-repo/scripts/cd/startJenkinsPipeline.sh "ARTIFACTORY_ID=${ARTIFACTORY_ID}" "LD_API_KEY_ID=${LD_API_KEY_ID}" "ENVIRONMENT=${ENVIRONMENT}" "PFX_FILE_ID=signing-pfx-file"
{ echo -e "UPLOADING LAUNCHDARKLY - DONE\n\n\n"; } 2> /dev/null
