#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Aliases are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

### Used in validate version file, Check duplicate keys in mustache templates, anti patterns, validate required deployment labels ###
export WORKSPACE_PATH=${PATH_TO_WORKSPACE_REPO}

# export WCP_ARTIFACTORY_PASSWORD=${ARTIFACTORY_API_KEY} --> OLD as per  https://github.ibm.com/genctl-cicd/genctl-ci/pull/3350

export ART_URL=${ARTIFACTORY_DOCKER_PROD_URL}
export IMG_TO_RUN_PATH=${GOLANG_CI_IMAGE_PATH}
export IMG_TO_RUN_TAG=${GOLANG_CI_IMAGE_TAG}

### Used in build ###
export UPLOAD=${UPLOAD_TO_REGISTRY_FLAG}
export CC_GITHUB_TOKEN=${GITHUB_API_KEY}
export CC_TRAVIS_API_ENDPOINT=${TRAVIS_API_ENDPOINT}
export CC_TRAVIS_CLI_VERSION=${TRAVIS_CLI_VERSION}
export CC_REPO_BRANCH=${PR_BASEBRANCH}
export CC_REPO_NAME=${PIPELINE_REPO_NAME}
export CC_REPO_ORG=${PIPELINE_REPO_ORG}
export CC_ARTIFACTORY_DEBIAN_REPO_PATH=${ARTIFACTORY_DEBIAN_SANDBOX_REPO_PATH}
export CC_ARTIFACTORY_RPM_REPO_PATH=${ARTIFACTORY_RPM_SANDBOX_REPO_PATH}
export CC_ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH=${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}
export CC_ARTIFACTORY_SANDBOX_DOCKER_URL=${ARTIFACTORY_SANDBOX_DOCKER_URL}
export CC_ARTIFACTORY_GENERIC_REPO_PATH=${ARTIFACTORY_GENERIC_REPO_PATH}
export CC_GO_IMAGE_PATH=${GOLANG_CI_IMAGE_PATH}
export CC_GO_IMAGE_TAG=${GOLANG_CI_IMAGE_MANIFEST_TAG}
export CC_ARTIFACTORY_BASE_URL=${ARTIFACTORY_BASE_URL}

# !!! Check if still needed !!!
export CI_CHECKS_PREFIX=${CHECKS_PREFIX}
export REPO_DIR=${PATH_TO_WORKSPACE_REPO}

# auto merge
export GHE_API_TOKEN=${GH_TOKEN}
export GHE_API_URL=${IBM_GITHUB_API_URI_BASE}
export REPOSITORY_NAME=${ORG_AND_REPO}
