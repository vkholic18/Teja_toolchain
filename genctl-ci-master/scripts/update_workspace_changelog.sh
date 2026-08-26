#!/usr/bin/env bash

##
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
##

# Below Environment properties have to be set before running the script. 
# PATH_TO_GENCTL_CI

set -eu

export CONFIG_FILE_PATH=${CONFIG_FILE_PATH:-"changelog-config/config.json"}
export GH_PAGE_REPO_PATH=${GH_PAGE_REPO_PATH:-"changelog-repo"}
export GH_PAGE_ORG_REPO=${GH_PAGE_ORG_REPO:-""}
export GITHUB_API_URL=${GITHUB_API_URL:-""}

if [[ -f "$CONFIG_FILE_PATH" ]]; then
    source ${PATH_TO_GENCTL_CI}/scripts/retry.sh
    retry python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/versioning/requirements.txt
    python3 ${PATH_TO_GENCTL_CI}/scripts/versioning/update_workspace_changelog.py
fi