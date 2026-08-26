#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Inherited from CI templates ###
export REPOSITORY_NAME=${ORG_AND_REPO}
export GHE_API_URL=${IBM_GITHUB_API_URI_BASE}
export GHE_API_TOKEN=${GH_TOKEN}

### Used in verify PR head ###
export SKIP_VERIFY_PR_HEAD=${SKIP_CHECK_PR_TO_MASTER_IS_FROM_DEV_INT}
export EXPECTED_PR_HEAD_ORG_AND_REPO=${ORG_AND_REPO}
export EXPECTED_PR_HEAD_BRANCH=${MASCD_INTEGRATION_BRANCH_NAME}

### Used in build ###
export CC_GITHUB_TOKEN=${GITHUB_API_KEY}
export CC_REPO_BRANCH=${PIPELINE_REPO_BRANCH}
export CC_REPO_NAME=${PIPELINE_REPO_NAME}
export CC_REPO_ORG=${PIPELINE_REPO_ORG}
export CC_ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH=${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}

### Need to use private endpoint for qz2 workers
export CC_ARTIFACTORY_SANDBOX_DOCKER_URL=${ARTIFACTORY_SANDBOX_DOCKER_URL_PRIVATE}
export ARTIFACTORY_DOCKER_PROD_URL=${ARTIFACTORY_DOCKER_PROD_URL_PRIVATE}

export CC_GO_IMAGE_PATH=${GOLANG_CI_IMAGE_PATH}
export CC_GO_IMAGE_TAG=${GOLANG_CI_IMAGE_MANIFEST_TAG}
export CC_ARTIFACTORY_BASE_URL=${ARTIFACTORY_BASE_URL}

### Used in scale up, scale down, validate razee cluster and validate feature flags, workspace tests ###
export WCP_ARTIFACTORY_USERNAME=${ARTIFACTORY_USER}

### Used in scale up, scale down, validate razee cluster and validate feature flags ###
export ART_URL=${ARTIFACTORY_DOCKER_PROD_URL_PRIVATE}
export IMG_TO_RUN_PATH=${GOLANG_CI_IMAGE_PATH}
export IMG_TO_RUN_TAG=${GOLANG_CI_IMAGE_TAG}

### Used in validate featureflags ###
export FAIL_IF_ERROR=${VALIDATE_FEATUREFLAGS_FAIL_IF_ERROR}

### Used in promotion tests ###
export GENCTL_VETTED_VERSIONS=${GENCTL_VETTED_VERSIONS_FILE}
export SMOTAINER_INTEGRATION_BRANCH=${INTEGRATION_TESTING_BRANCH}
export VETTED_VERSION_REPO=${PATH_TO_VETTED_VERSIONS_REPO}
export RIAS_GLOBALS_REPO=${PATH_TO_RIAS_GLOBALS_REPO}

# !!! Check if still needed !!!
export CI_CHECKS_PREFIX=${CHECKS_PREFIX}
export REPO_DIR=${PATH_TO_WORKSPACE_REPO}

### Used in go-notify slack notification ###
export GHE_USERNAME=${VAULT_GIT_CONFIG_USERNAME}
export GHE_APIKEY=${GHE_RO_TOKEN}
export SLACK_GROUP=${GO_NOTIFY_SLACK_GROUP}
export GH_API_ENDPOINT=${IBM_GITHUB_API_URI_BASE}
