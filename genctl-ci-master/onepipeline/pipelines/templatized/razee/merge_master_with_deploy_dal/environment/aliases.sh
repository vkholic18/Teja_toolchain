#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Aliases are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

### Used in prepare genctl release bundle, prepare rias release bundle, deploy dal, smoke ###
export WCP_ARTIFACTORY_USERNAME=${ARTIFACTORY_USER}

### Used in prepare genctl release bundle, prepare rias release bundle ###
export GHE_ACCESS_TOKEN=${GITHUB_API_KEY}
export SUBMODULE=${PIPELINE_REPO_NAME}
export RELEASE_BUNDLE_IMAGE_NAME=${GENCTL_RELEASE_BUNDLE_IMAGE_NAME}

### Used in upload to COS, Launchdarkly, bump genctl ###
export COMPONENT=${PIPELINE_REPO_NAME}

### Used in deploy dal, smoke ###
export GENCTL_VETTED_VERSIONS=${GENCTL_VETTED_VERSIONS_FILE}


### Used in prepare rias release bundle, bump rias component ###
export RIAS_COMPONENT=${PIPELINE_REPO_NAME}

### Used in autosemver ###
export WORKSPACE_PATH=${PATH_TO_WORKSPACE_REPO}
export GITHUB_URL=${IBM_GITHUB_URL}
export GITHUB_API_URL=${IBM_GITHUB_API_URI_BASE}
export DEFAULT_BRANCH=${REPO_MAIN_BRANCH}
export CREATE_TAG_MODE=${DEFAULT_SEMVER_CREATE_TAG_MODE}

### Used in retag ###
export IBMCLOUD_KEY_FOR_RETAG=${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}
# Note that we pull and push from same registry
#export MARINA_DOCKER_URL=${MARINA_BASE_URL} --> Commented since reaching marina is not working in One-Pipeline

### Used in deploy dal ###
export LOCK_SOURCE=${GENCTL_CI_CLAIM_LOCK_DIRECTORY}
export LOCK_DESTINATION=${GENCTL_CI_RELEASE_LOCK_DIRECTORY}
export ART_URL=${ARTIFACTORY_DOCKER_PROD_URL}
export IMG_TO_RUN_PATH=${GOLANG_CI_IMAGE_PATH} 
export IMG_TO_RUN_TAG=${GOLANG_CI_IMAGE_TAG}

### Used in Launchdarkly ###
export DEV_REGIONS_FILE=${DEV_REGIONS_MERGE_TO_MASTER_FILE}

### Used in prepare genctl release bundle ###
export ARTIFACTORY_DOCKER_URL_FOR_PREPARE_GENCTL_RELEASE_BUNDLE=${ARTIFACTORY_DOCKER_STAGING_URL}
export ICR_URL_TO_PUSH_ON_PREPARE_GENCTL_RELEASE_BUNDLE=${VPC_ICR_SANDBOX_URL}
export GENCTL_NEXTGEN_SERVICE_DEPLOYER_RELEASE_IMAGE_NAME=${NEXTGEN_SERVICE_DEPLOYER_RELEASE_IMAGE_NAME}

### Used in prepare rias release bundle ###
export ARTIFACTORY_DOCKER_URL_FOR_PREPARE_RIAS_RELEASE_BUNDLE=${ARTIFACTORY_DOCKER_STAGING_URL}
export ICR_URL_TO_PUSH_ON_PREPARE_RIAS_RELEASE_BUNDLE=${VPC_ICR_SANDBOX_URL}

### Used in deploy dal ###
export WORKSPACE_REPO_NAME=${PIPELINE_REPO_NAME}
export GHE_API_TOKEN=${GH_TOKEN}
export MDS_CONFIG_TEMPLATE=${MDS_CONFIG_TEMPLATE_FILE}
export ENV_REPO_ORG=${MZONE_NEXTGEN_ENVIRONMENT_ORG_NAME}
export ENV_REPO_REF=${MZONE_NEXTGEN_ENVIRONMENT_BRANCH}
export PLATFORM_INVENTORY_REF=${PLATFORM_INVENTORY_BRANCH}
export PLATFORM_INVENTORY_ORG=${PLATFORM_INVENTORY_ORG_NAME}

### Used in smoke ###
export SMOTAINER_INTEGRATION_BRANCH=${INTEGRATION_TESTING_BRANCH}
export SUPPORTTED_HOSTOS_VERSIONS=${SUPPORTED_HOSTOS_RELEASE_BUNDLES_Z} 

### Used in bump ###
export GENCTL_RELEASE_BRANCH_NAME=${GENCTL_RELEASE_BRANCH}
export GENCTL_COMPONENT=${PIPELINE_REPO_NAME}

### Used in Dev MZone mgmt process ###
export DEV_REGIONS_VETTED_VERSIONS_REPO_NAME=${DEV_REGIONS_REPO_NAME}
export DEV_REGIONS_VETTED_VERSIONS_ORG_NAME=${DEV_REGIONS_ORG_NAME}
export COMPONENT_FOR_VETTED_VERSION=${PIPELINE_REPO_NAME}
export GHE_API_URL=${IBM_GITHUB_API_URI_BASE}

# Used in inventory update
export GHE_TOKEN=${GH_TOKEN}