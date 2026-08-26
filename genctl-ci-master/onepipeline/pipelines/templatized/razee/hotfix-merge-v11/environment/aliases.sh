#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
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
export DEFAULT_BRANCH=${REPO_MAIN_BRANCH}
export CREATE_TAG_MODE=${DEFAULT_SEMVER_CREATE_TAG_MODE}

### Used in build ###
export CC_ARTIFACTORY_HOST=${ARTIFACTORY_DOCKER_URL}
export CC_GITHUB_TOKEN=${GITHUB_API_KEY}
export CC_ARTIFACTORY_SANDBOX_DOCKER_URL=${ARTIFACTORY_SANDBOX_DOCKER_URL}
export CC_ARTIFACTORY_GENERIC_REPO_PATH=${ARTIFACTORY_GENERIC_REPO_PATH}
export CC_ARTIFACTORY_DEBIAN_REPO_PATH=${ARTIFACTORY_DEBIAN_SANDBOX_REPO_PATH}
export CC_ARTIFACTORY_RPM_REPO_PATH=${ARTIFACTORY_RPM_SANDBOX_REPO_PATH}
export CC_ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH=${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}
export UPLOAD=${UPLOAD_TO_REGISTRY_FLAG}
export CC_TRAVIS_API_ENDPOINT=${TRAVIS_API_ENDPOINT}
export CC_TRAVIS_CLI_VERSION=${TRAVIS_CLI_VERSION}
export CC_REPO_BRANCH=${PIPELINE_RUN_BRANCH}
export CC_REPO_NAME=${PIPELINE_REPO_NAME}
export CC_REPO_ORG=${PIPELINE_REPO_ORG}
export CC_GO_IMAGE_PATH=${GOLANG_CI_IMAGE_PATH}
export CC_GO_IMAGE_TAG=${GOLANG_CI_IMAGE_MANIFEST_TAG}
export CC_ARTIFACTORY_BASE_URL=${ARTIFACTORY_BASE_URL}
#export MARINA_DOCKER_URL=${MARINA_BASE_URL} --> Commented since reaching marina is not working in One-Pipeline

### Used in ICCR ###
export IBMCLOUD_URL=${IBMCLOUD_CR_URL_ONEPIPELINE}
export WCP_ARTIFACTORY_USERNAME=${ARTIFACTORY_USER}
export IBMCLOUD_KEY=${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}
export IBMCLOUD_KEY_FOR_PREPARE_FOR_ICR_SCAN=${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}

### Used in Launchdarkly ###
export DEV_REGIONS_FILE=${DEV_REGIONS_MERGE_TO_MASTER_FILE}
export TR_ARTIFACTORY_LOGIN=${ARTIFACTORY_USER}
export TR_ARTIFACTORY_ACCESS_TOKEN=${CC_ARTIF_ACCESS_TOKEN}
export VPC_ICR_URL="${VPC_ICR_SANDBOX_URL}"

### Used also in build (Upload related) ###
export SKIP_UPLOAD_PACKAGES=${SKIP_UPLOAD_PACKAGES_ON_MERGE_PIPELINE}

# Used in inventory update
export GHE_TOKEN=${GH_TOKEN}
