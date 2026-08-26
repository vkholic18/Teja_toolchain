#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script verifies that a repository is properly configured according to the Razee/MASCD conventional commit enforcement flow

# The following environment variables need to be set before executing the script:
# WORKSPACE_PATH,PATH_TO_ANTI_PATTERNS,GITHUB_TOKEN, VAULT_GIT_CONFIG_USER_EMAIL, VAULT_GIT_CONFIG_USERNAME, ANTI_PATTERNS_SERVICE_NAME

# =============================================================================================

# Set flags
set -eu

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh
START=$(date +%s)
echo "machine github.ibm.com login ${VAULT_GIT_CONFIG_USERNAME} password ${GITHUB_TOKEN}" >> $HOME/.netrc
git config --get user.name || git config --global user.name ${VAULT_GIT_CONFIG_USER_EMAIL}
git config --get user.email || git config --global user.email ${VAULT_GIT_CONFIG_USER_EMAIL}

if [[ ${ANTI_PATTERNS_SERVICE_NAME:-} == "" ]]; then
echo "Error: var ANTI_PATTERNS_SERVICE_NAME was set to \"${ANTI_PATTERNS_SERVICE_NAME:-}\""
exit 1
fi

# Install dependencies as defined in the anti-patterns readme
# TODO call code from anti-patterns repo for satisfying dependencies
# echo "Installing dependencies..."

echo "Running scan..."

# The pipe into jq is separated so that a failure in the command is not suppressed by JQ which would
# result in a failure being ignored / bypassed since jq will return a status code of 0 for empty input.
output=$(${PATH_TO_ANTI_PATTERNS}/rias-anti-patterns estimate ${ANTI_PATTERNS_SERVICE_NAME} ${WORKSPACE_PATH} ${PATH_TO_ANTI_PATTERNS}/call_stats_from_logdna.json ${PATH_TO_ANTI_PATTERNS}/cost_from_logdna.json)
echo "$output" | jq

echo "Done"
END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Anti patterns took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"