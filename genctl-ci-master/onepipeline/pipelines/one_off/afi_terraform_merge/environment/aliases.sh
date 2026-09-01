#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

export TF_WORKSPACE=${workspace_name:-}
export WORKSPACE_REPO_NAME=${PIPELINE_REPO_NAME:-}
export PATH_TO_WORKSPACE_REPO="${WORKSPACE}/${WORKSPACE_REPO_NAME}"
export PATH_TO_WORKSPACE=${PATH_TO_WORKSPACE_REPO}
