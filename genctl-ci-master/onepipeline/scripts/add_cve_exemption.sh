#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

##################### Pre-Requisites ####################################
### 1. Install ibmcloud                                               ###
### 2. Install container registry plugin - ibmcloud plugin install cr ###
### 3. Install jq and awk                                             ###
### 4. Login to OnePipeLineCI cloud account                           ###
#########################################################################

usage() {  
  echo "Usage: $0 <image>"
  echo "Eg: $0 us.icr.io/genctl-cicd-onepipeline/hostos/hostos-validate-release:tag" 1>&2
}

if [ $# -eq 0 ]
  then
    usage
fi

IMAGE=$1
REPO=$(echo $IMAGE | awk -F ':' '{print $1}')
ibmcloud cr va $IMAGE --output json > output.json
unexempted_cves=$(jq -r '.[].vulnerabilities | .[] | select(.cve_exempt == false).cve_id' output.json | wc -l)
if [ "$unexempted_cves" -eq "0" ]; then
  echo "No unexempted CVE vulnerabilities found in the image: $IMAGE";
else
  echo "Total $unexempted_cves unexempted CVEs found in the image: $IMAGE and adding them to container registry"
  jq -r '.[].vulnerabilities | .[] | select(.cve_exempt == false).cve_id' output.json | while read i;
  do
    echo -e "ibmcloud cr exemption-add --scope $REPO --issue-type cve --issue-id $i"
    ibmcloud cr exemption-add --scope $REPO --issue-type cve --issue-id $i
  done
fi
