#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Aliases are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

### Used in autosemver ###
export GITHUB_URL=${IBM_GITHUB_URL}
export GITHUB_API_URL=${IBM_GITHUB_API_URI_BASE}
export GH_PAGE_ORG_REPO="${CHANGELOG_ORG_NAME}/${CHANGELOG_REPO_NAME}"
export DEFAULT_BRANCH=${REPO_MAIN_BRANCH}
export CREATE_TAG_MODE=${DEFAULT_SEMVER_CREATE_TAG_MODE}

### Used in CRA setup ###
export WORKSPACE_PATH=${PATH_TO_WORKSPACE_REPO}

### Used in create a release bundle ###
export ARTIFACTORY_URL=${ARTIFACTORY_DOCKER_URL}
export ARTIFACTORY_PROD_URL=${ARTIFACTORY_DOCKER_URL}
export ARTIFACTORY_SANDBOX_URL=${ARTIFACTORY_SANDBOX_DOCKER_URL}
export ARTIFACTORY_LOGIN=${ARTIFACTORY_USER}
export REPOSITORY=${PIPELINE_REPO_NAME}
export MAKE_TARGET=${HOSTOS_MAKE_TARGET}
export ARTIF_USER=${ARTIFACTORY_USER}

export ICR_URL_TO_PUSH_ON_PREPARE_LOW_LEVEL_RELEASE_BUNDLE=${IBMCLOUD_CR_URL_ONEPIPELINE}

### Used in save_artifacts ###
export WCP_ARTIFACTORY_USERNAME=${ARTIFACTORY_USER}

### Used in prepare for ICR scan ###
export IBMCLOUD_KEY_FOR_PREPARE_FOR_ICR_SCAN=${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}

### Used in update vetted versions ###
export VERSION_FILE=${GENCTL_VETTED_VERSIONS_FILE}
export VETTED_VERSIONS_REPO_NAME=${GENCTL_VETTED_VERSIONS_REPO_NAME}
export DEV_REGIONS_VETTED_VERSIONS_REPO_NAME=${DEV_REGIONS_REPO_NAME}
export DEV_REGIONS_VETTED_VERSIONS_FILE=${DEV_REGIONS_MERGE_TO_MASTER_FILE}
export COMPONENT_FOR_VETTED_VERSION=${PIPELINE_REPO_NAME}

### Used in prepare high level release bundle ###
export ARTIFACTORY_DOCKER_URL_FOR_PREPARE_GENCTL_RELEASE_BUNDLE=${ARTIFACTORY_DOCKER_URL}
export ICR_URL_TO_PUSH_ON_PREPARE_GENCTL_RELEASE_BUNDLE=${IBMCLOUD_CR_URL_ONEPIPELINE}
export ARTIFACTORY_DOCKER_URL_FOR_PREPARE_RIAS_RELEASE_BUNDLE=${ARTIFACTORY_DOCKER_URL}
export ICR_URL_TO_PUSH_ON_PREPARE_RIAS_RELEASE_BUNDLE=${IBMCLOUD_CR_URL_ONEPIPELINE}
export GENCTL_NEXTGEN_SERVICE_DEPLOYER_RELEASE_IMAGE_NAME=${NEXTGEN_SERVICE_DEPLOYER_RELEASE_IMAGE_NAME}

# Used in inventory update
export GHE_TOKEN=${GH_TOKEN}