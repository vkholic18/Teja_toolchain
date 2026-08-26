#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

set -e

if [[ -f "${PATH_TO_WORKSPACE_REPO}/hack/ci/jinja_validation.sh" ]]; then
    ## Validate jinja2 files ##
    echo "here will run the script to validate jinja2"
else
    echo "no jinja2 validation file present in ${PATH_TO_WORKSPACE_REPO}/hack/ci/"
    exit 0
fi
