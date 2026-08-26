#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO

set -eu

work_root="${PWD}"
echo "validate-globals-scan.yaml: work_root=${work_root}"

echo "validate-globals-scan.yaml: validating globals"
${PATH_TO_GENCTL_CI}/scripts/validate_globals_scan.sh ${PATH_TO_WORKSPACE_REPO}
