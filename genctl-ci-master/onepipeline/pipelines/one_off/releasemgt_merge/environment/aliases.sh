#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Inherited from CI templates ###
export REPOSITORY_NAME=${ORG_AND_REPO}
export GH_PAGE_ORG_REPO=${CHANGELOG_ORG_NAME}/${CHANGELOG_REPO_NAME} #from pipeline-params.yaml
export GITHUB_API_URL=${IBM_GITHUB_API_URI_BASE} #from pipeline-params.yaml
export GHE_API_TOKEN=${GH_TOKEN}
export ENV_REPO_PATH="${PATH_TO_WORKSPACE_REPO}"