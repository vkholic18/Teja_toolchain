#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Aliases are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

### Used in check if PR has label ###
export GHE_API_URL=${IBM_GITHUB_API_URI_BASE}
export REPOSITORY_NAME=${ORG_AND_REPO}

export LABEL_TO_SEARCH=${NGDC_DEPLOY_LABEL}

### Used in CRA setup ###
export WORKSPACE_PATH=${PATH_TO_WORKSPACE_REPO}

### Used in check pr title ###
export PR_NUMBER=${PR_ID}
export WORKSPACE_ORG=${PIPELINE_REPO_ORG}
export WORKSPACE_REPO=${PIPELINE_REPO_NAME} 
export TOKEN=${GITHUB_API_KEY}

### Used in create a release bundle ###
export ARTIFACTORY_SANDBOX_URL=${ARTIFACTORY_SANDBOX_DOCKER_URL}
export ARTIFACTORY_LOGIN=${ARTIFACTORY_USER}
export REPOSITORY=${PIPELINE_REPO_NAME}
export ARTIFACTORY_URL=${ARTIFACTORY_DOCKER_STAGING_URL}
export ARTIFACTORY_PROD_URL=${ARTIFACTORY_DOCKER_URL}
export ARTIF_USER=${ARTIFACTORY_USER}

export ICR_URL_TO_PUSH_ON_PREPARE_LOW_LEVEL_RELEASE_BUNDLE=${VPC_ICR_SANDBOX_URL}

### Used in deploy dal ###
export WCP_ARTIFACTORY_USERNAME=${ARTIFACTORY_USER}
export GITHUB_API_URL=${IBM_GITHUB_API_URI_BASE}
export SKIP_SMOKE_TESTS=${SKIP_DEPLOY_DAL} # Here we can assume that if we skip deploy dal we should skip smoke tests too
export PACKAGE=${PIPELINE_REPO_NAME}
export MDS_CONFIG_TEMPLATE=${MDS_CONFIG_HOSTOS_BRT_TEMPLATE_FILE}
#export WORKSPACE_REPO_NAME=${PIPELINE_REPO_NAME} # This is needed ONLY for Deploy Dal on razee workspaces
export GHE_API_TOKEN=${GH_TOKEN}
export ENV_REPO_ORG=${MZONE_NEXTGEN_ENVIRONMENT_ORG_NAME}
export ENV_REPO_REF=${MZONE_NEXTGEN_ENVIRONMENT_BRANCH}
export PLATFORM_INVENTORY_REF=${PLATFORM_INVENTORY_BRANCH}
export PLATFORM_INVENTORY_ORG=${PLATFORM_INVENTORY_ORG_NAME}
export GENCTL_VETTED_VERSIONS=${GENCTL_VETTED_VERSIONS_FILE}

export LOCK_SOURCE=${GENCTL_CI_CLAIM_LOCK_DIRECTORY}
export LOCK_DESTINATION=${GENCTL_CI_RELEASE_LOCK_DIRECTORY}
export ART_URL=${ARTIFACTORY_DOCKER_PROD_URL}
export IMG_TO_RUN_PATH=${GOLANG_CI_IMAGE_PATH} 
export IMG_TO_RUN_TAG=${GOLANG_CI_IMAGE_TAG}

export RIAS_DEPLOY_COMPONENT_TYPE="${COMPONENT}"
export COMPONENT_FOR_VETTED_VERSION=${PIPELINE_REPO_NAME}

### For NGDC ###

# CD script uses slightly different name for the path to the CD repo
export PATH_TO_GENCTL_CD=${PATH_TO_GENCTL_CD_REPO}