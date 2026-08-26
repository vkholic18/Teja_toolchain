#!/bin/bash -eux
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2021
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

{ echo -e "\n\n\nUPDATING LAUNCHDARKLY\n"; } 2> /dev/null
# without this ffedex will fail
set +x # hide password from console
echo "machine github.ibm.com login ${GHE_USERNAME} password ${MDS_GITHUB_APIKEY}" > ~/.netrc
{ set -x; } 2>/dev/null

genctl-cd-repo/scripts/razee/execute_ffedex.sh "deploy-eyaml/environment.json" "$(jq -r .CRNumber ticket/data.json)"
{ echo -e "UPDATING LAUNCHDARKLY - DONE\n\n\n"; } 2> /dev/null
