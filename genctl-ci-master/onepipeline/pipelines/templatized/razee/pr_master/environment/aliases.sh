#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Aliases are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

### Used in CRA setup ###
export WORKSPACE_PATH=${PATH_TO_WORKSPACE_REPO}

### Used in verify PR head, auto-merge ###
export PR_NUMBER=${PR_ID}
export REPOSITORY_NAME=${ORG_AND_REPO}
export GHE_API_URL=${IBM_GITHUB_API_URI_BASE}
export GHE_API_TOKEN=${GH_TOKEN}

### Used in verify PR head ###
export SKIP_VERIFY_PR_HEAD=${SKIP_CHECK_PR_TO_MASTER_IS_FROM_DEV_INT}
export EXPECTED_PR_HEAD_ORG_AND_REPO=${ORG_AND_REPO}
export EXPECTED_PR_HEAD_BRANCH=${MASCD_INTEGRATION_BRANCH_NAME}

### Used in build ###
export CC_GITHUB_TOKEN=${GITHUB_API_KEY}
export CC_TRAVIS_API_ENDPOINT=${TRAVIS_API_ENDPOINT}
export CC_TRAVIS_CLI_VERSION=${TRAVIS_CLI_VERSION}
export CC_REPO_BRANCH=${PR_BASEBRANCH}
export CC_REPO_NAME=${PIPELINE_REPO_NAME}
export CC_REPO_ORG=${PIPELINE_REPO_ORG}
export CC_ARTIFACTORY_DEBIAN_REPO_PATH=${ARTIFACTORY_DEBIAN_SANDBOX_REPO_PATH}
export CC_ARTIFACTORY_GENERIC_REPO_PATH=${ARTIFACTORY_GENERIC_REPO_PATH}
export CC_ARTIFACTORY_RPM_REPO_PATH=${ARTIFACTORY_RPM_SANDBOX_REPO_PATH}
export CC_ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH=${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}
export CC_ARTIFACTORY_SANDBOX_DOCKER_URL=${ARTIFACTORY_SANDBOX_DOCKER_URL}
export CC_GO_IMAGE_PATH=${GOLANG_CI_IMAGE_PATH}
export CC_GO_IMAGE_TAG=${GOLANG_CI_IMAGE_MANIFEST_TAG}
export CC_ARTIFACTORY_BASE_URL=${ARTIFACTORY_BASE_URL}

### Used in scale up, scale down, validate razee cluster and validate feature flags, workspace tests ###
export WCP_ARTIFACTORY_USERNAME=${ARTIFACTORY_USER}
# export WCP_ARTIFACTORY_PASSWORD=${ARTIFACTORY_API_KEY} Unneeded as per https://github.ibm.com/genctl-cicd/genctl-ci/pull/3350

### Used in scale up, scale down, validate razee cluster and validate feature flags ### (Can be removed soon)
export IMG_TO_RUN_PATH=${GOLANG_CI_IMAGE_PATH}
export IMG_TO_RUN_TAG=${GOLANG_CI_IMAGE_TAG}

export ART_URL=${ARTIFACTORY_DOCKER_PROD_URL}

### Used in scale up, scale down, validate razee cluster and validate feature flags with Ubuntu image ###
export BRT_IMG_TO_RUN_PATH=${BRT_CI_IMAGE_PATH}
export BRT_IMG_TO_RUN_TAG=${BRT_CI_IMAGE_TAG}

### Used in validate featureflags ###
export FAIL_IF_ERROR=${VALIDATE_FEATUREFLAGS_FAIL_IF_ERROR}

### Used in workspace tests ###
export GENCTL_VETTED_VERSIONS=${GENCTL_VETTED_VERSIONS_FILE}
export SMOTAINER_INTEGRATION_BRANCH=${INTEGRATION_TESTING_BRANCH}
export VETTED_VERSION_REPO=${PATH_TO_VETTED_VERSIONS_REPO}
export RIAS_GLOBALS_REPO=${PATH_TO_RIAS_GLOBALS_REPO}

### Used in auto-merge ###
export PR_SHA=${PR_HEADSHA}




# !!! Check if still needed !!!
export CI_CHECKS_PREFIX=${CHECKS_PREFIX}
export REPO_DIR=${PATH_TO_WORKSPACE_REPO}
