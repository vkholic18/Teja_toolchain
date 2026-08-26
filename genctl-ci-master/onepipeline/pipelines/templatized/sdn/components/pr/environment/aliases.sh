#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Aliases are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

### Used in check pr title ###
export PR_NUMBER=${PR_ID}
export WORKSPACE_ORG=${PIPELINE_REPO_ORG}
export WORKSPACE_REPO=${PIPELINE_REPO_NAME} 
export TOKEN=${GITHUB_API_KEY}

### Used in check PR has label ###
export GHE_API_URL=${IBM_GITHUB_API_URI_BASE}
export REPOSITORY_NAME=${ORG_AND_REPO}

### Used in scan genlog ###
export SCAN_PATH=${PATH_TO_WORKSPACE_REPO}

### Used in build ###
export CC_GITHUB_TOKEN=${GITHUB_API_KEY}
export CC_TRAVIS_API_ENDPOINT=${TRAVIS_API_ENDPOINT}
export CC_TRAVIS_CLI_VERSION=${TRAVIS_CLI_VERSION}
export CC_REPO_BRANCH=${PR_BASEBRANCH}
export CC_REPO_NAME=${PIPELINE_REPO_NAME}
export CC_REPO_ORG=${PIPELINE_REPO_ORG}
export CC_ARTIFACTORY_DEBIAN_REPO_PATH=${ARTIFACTORY_DEBIAN_SANDBOX_REPO_PATH}
export CC_ARTIFACTORY_RPM_REPO_PATH=${ARTIFACTORY_RPM_SANDBOX_REPO_PATH}
export CC_ARTIFACTORY_SANDBOX_DOCKER_URL=${ARTIFACTORY_SANDBOX_DOCKER_URL}

### Used also in build (Upload related) ###
export SKIP_UPLOAD_PACKAGES=${SKIP_UPLOAD_PACKAGES_ON_PR_PIPELINE}

### Used in check pr has label ###
export GHE_API_TOKEN=${GH_TOKEN}