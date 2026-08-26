#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Aliases are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

### Used in upload to COS, Launchdarkly ###
export COMPONENT=${PIPELINE_REPO_NAME}

### Used in autosemver ###
export WORKSPACE_PATH=${PATH_TO_WORKSPACE_REPO}
export GITHUB_URL=${IBM_GITHUB_URL}
export GITHUB_API_URL=${IBM_GITHUB_API_URI_BASE}
export GH_PAGE_ORG_REPO="${CHANGELOG_ORG_NAME}/${CHANGELOG_REPO_NAME}"
export DEFAULT_BRANCH=${REPO_MAIN_BRANCH}
export CREATE_TAG_MODE=${DEFAULT_SEMVER_CREATE_TAG_MODE}

### Used in retag ###
export IBMCLOUD_KEY_FOR_RETAG=${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}
# Note that we pull and push from same registry
#export MARINA_DOCKER_URL=${MARINA_BASE_URL} --> Commented since reaching marina is not working in One-Pipeline

### Used in Launchdarkly ###
export DEV_REGIONS_FILE=${DEV_REGIONS_MERGE_TO_MASTER_FILE}

# Used in inventory update
export GHE_TOKEN=${GH_TOKEN}