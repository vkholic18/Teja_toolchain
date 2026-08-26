#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

export WORKSPACE_REPOSITORY_URL=$(get_env "repository")
export WORKSPACE_REPOSITORY_BRANCH=$(get_env "branch")
export WORKSPACE_REPOSITORY_NAME=$(basename ${WORKSPACE_REPOSITORY_URL})
export PATH_TO_WORKSPACE_REPO=${WORKSPACE}/${WORKSPACE_REPOSITORY_NAME}

# Gets used for all common utilities for CI/CD
export PATH_TO_CICD_UTILS="${WORKSPACE}/${CI_CD_UTILS_REPO_NAME}"
