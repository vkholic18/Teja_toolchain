#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Aliases are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

### Used in autosemver ###
export WORKSPACE_PATH=${PATH_TO_WORKSPACE_REPO}
export GITHUB_URL=${IBM_GITHUB_URL}
export GITHUB_API_URL=${IBM_GITHUB_API_URI_BASE}
export DEFAULT_BRANCH=${REPO_MAIN_BRANCH}
export CREATE_TAG_MODE=${SEMVER_CREATE_TAG_MODE_GOMOD}

### Used in upload to COS, Launchdarkly ###
export COMPONENT=${PIPELINE_REPO_NAME}

### Used in Launchdarkly ###
export DEV_REGIONS_FILE=${DEV_REGIONS_MERGE_TO_MASTER_FILE}

# Used in inventory update
export GHE_TOKEN=${GH_TOKEN}