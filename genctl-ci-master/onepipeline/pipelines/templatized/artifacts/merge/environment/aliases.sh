#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Aliases are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

### Used for searching cra setup ###
export WORKSPACE_PATH=${PATH_TO_WORKSPACE_REPO}

### Used in autosemver ###
export WORKSPACE_PATH=${PATH_TO_WORKSPACE_REPO}
export GITHUB_URL=${IBM_GITHUB_URL}
export GITHUB_API_URL=${IBM_GITHUB_API_URI_BASE}
export DEFAULT_BRANCH=${REPO_MAIN_BRANCH}

### Used in build (For upload) ###
export CC_GITHUB_TOKEN=${GITHUB_API_KEY}
export CC_TRAVIS_API_ENDPOINT=${TRAVIS_API_ENDPOINT}
export CC_TRAVIS_CLI_VERSION=${TRAVIS_CLI_VERSION}
export CC_REPO_BRANCH=${PIPELINE_RUN_BRANCH}
export CC_REPO_NAME=${PIPELINE_REPO_NAME}
export CC_REPO_ORG=${PIPELINE_REPO_ORG}
export CC_ARTIFACTORY_DEBIAN_REPO_PATH=${ARTIFACTORY_DEBIAN_SANDBOX_REPO_PATH}
export CC_ARTIFACTORY_RPM_REPO_PATH=${ARTIFACTORY_RPM_SANDBOX_REPO_PATH}
export CC_ARTIFACTORY_SANDBOX_DOCKER_URL=${ARTIFACTORY_SANDBOX_DOCKER_URL}
export CC_GO_IMAGE_PATH=${GOLANG_CI_IMAGE_PATH}
export CC_GO_IMAGE_TAG=${GOLANG_CI_IMAGE_MANIFEST_TAG}
export CC_ARTIFACTORY_GENERIC_REPO_PATH=${ARTIFACTORY_GENERIC_REPO_PATH}
export CC_ARTIFACTORY_BASE_URL=${ARTIFACTORY_BASE_URL}
export CC_ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH=${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}

### Used also in build (Upload related) ###
export SKIP_UPLOAD_PACKAGES=${SKIP_UPLOAD_PACKAGES_ON_MERGE_PIPELINE}
export UPLOAD=${UPLOAD_TO_REGISTRY_FLAG} # This is for docker images