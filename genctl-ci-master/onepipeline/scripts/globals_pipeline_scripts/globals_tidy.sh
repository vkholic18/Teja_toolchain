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

source ${PATH_TO_GENCTL_CI}/scripts/retry.sh
work_root="${PWD}"
echo "globals-tidy.yaml: work_root=${work_root}"

echo "globals-tidy.yaml: installing python dependencies"
retry python3 -m pip install ruamel.yaml

echo "globals-tidy.yaml: running globals_tidy.sh"
${PATH_TO_GENCTL_CI}/scripts/globals_tidy.sh ${PATH_TO_WORKSPACE_REPO}
