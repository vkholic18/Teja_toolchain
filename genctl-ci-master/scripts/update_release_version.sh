#!/usr/bin/env bash

##
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
##
set -u

# Below Environment properties have to be set before running the script. 
# PATH_TO_GENCTL_CI
# CONFIG_FILE_PATH, JIRA_USERNAME, JIRA_PASSWORD, JIRA_URL, SKIP_UPDATE_RELEASE_VERSION

export CONFIG_FILE_PATH=${CONFIG_FILE_PATH:-"changelog-config/config.json"}
export DRY_RUN=${DRY_RUN:-"false"}
export JIRA_URL=${JIRA_URL:-""}

if [[ $SKIP_UPDATE_RELEASE_VERSION = true ]]; then
    echo "Nothing to do. No JIRA updates will be performed, just exiting"
    exit 0
fi

source ${PATH_TO_GENCTL_CI}/scripts/retry.sh

if [[ -f "$CONFIG_FILE_PATH" ]]; then
    export JIRA_CERT_FILE="${PATH_TO_GENCTL_CI}/certificates/jira.crt"

    # Set the path to the update release version directory (Relative from current location) for readability
    UPDATE_RELEASE_VERSION_DIR="${PATH_TO_GENCTL_CI}/scripts/update_release_version"

    retry python3 -m pip install -q ${PATH_TO_GENCTL_CI}/tools/ci_python_tools
    retry python3 -m pip install -q -r ${UPDATE_RELEASE_VERSION_DIR}/requirements.txt

    python3 ${UPDATE_RELEASE_VERSION_DIR}/update_release_version.py
else

    echo "In order to update release version field in JIRA, we need the list of JIRAs to update which comes from AutoSemver"
    echo "File was expected to be in ${CONFIG_FILE_PATH} but for some reason it wasn not there, will exit with error"
    exit 1
fi