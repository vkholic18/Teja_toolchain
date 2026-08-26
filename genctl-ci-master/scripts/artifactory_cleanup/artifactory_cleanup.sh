#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO

set -eu

source ${PATH_TO_GENCTL_CI}/scripts/retry.sh

echo DAYS_PASSED_FOR_ZERO_DOWNLOADS: ${DAYS_PASSED_FOR_ZERO_DOWNLOADS}
echo DAYS_PASSED_SINCE_LAST_DOWNLOAD: ${DAYS_PASSED_SINCE_LAST_DOWNLOAD}
echo CLEANUP_DRY_RUN: ${CLEANUP_DRY_RUN}
echo REPOS_TO_SCAN: ${REPOS_TO_SCAN}
echo QUERY_LIMIT: ${QUERY_LIMIT}
echo QUERY_MODE: ${QUERY_MODE}
echo ARTIFACT_TYPE: ${ARTIFACT_TYPE}
echo ARTIFACTS_PATH: ${ARTIFACTS_PATH}

# Before running tests install ci_python_tools package (Required in different tests)
retry python3 -m pip install -q ${PATH_TO_GENCTL_CI}/tools/ci_python_tools

echo "running artifactory_cleanup/artifactory_cleanup.py"
python3 ${PATH_TO_GENCTL_CI}/scripts/artifactory_cleanup/artifactory_cleanup.py
