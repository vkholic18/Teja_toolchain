#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================


# workspace information for python script
export WORKSPACE_ORG=$(get_env "WORKSPACE_REPO_ORG")
export WORKSPACE_REPO=$(get_env "WORKSPACE_REPO_NAME")
export GITHUB_API_URL=$(get_env "GITHUB_API_URL")
export PR_NUMBER=$(get_env "PR_URL" | grep -o '[^/]*$')
