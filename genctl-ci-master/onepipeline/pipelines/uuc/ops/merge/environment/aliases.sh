#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

export GITHUB_TOKEN=${GH_TOKEN}
export IBMCLOUD_API_KEY=${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}

export REPOSITORY_NAME=${ORG_AND_REPO}
export GHE_API_URL=${IBM_GITHUB_API_URI_BASE}
export GHE_API_TOKEN=${GH_TOKEN}

# Used to create the automatic PRs (clconc)
export AUTO_PR_GITHUB_TOKEN=${GHE_ACCESS_TOKEN}
