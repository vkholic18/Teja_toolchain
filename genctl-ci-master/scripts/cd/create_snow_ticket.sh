#!/usr/bin/env bash

##
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
##
set -ux

# Create necessary directories to populate later
# These vars are defined in vars.sh for use throughout the job
mkdir ${TICKET_DIR}

# without this go get will fail
echo "machine github.ibm.com login ${GHE_USERNAME} password ${MDS_GITHUB_APIKEY}" > ~/.netrc
# install snowgo
go install github.ibm.com/genctl-cicd/snowgo/v3@${SNOWGO_VERSION}

set -x
snowgo -json -j "${JIRA_URL}" -pr ${PR_HTML_URL} -pu ${PIPELINE_RUN_URL} -rm ${META_DIR}/meta.json -sn $SERVICENOW_URL ${SNOWGO_FLAGS} > ${TICKET_DIR}/data.json
{ set +x; } 2>/dev/null

jq -r .CRNumber ${TICKET_DIR}/data.json
