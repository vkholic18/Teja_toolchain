#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Aliases are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline


export GHE_API_URL=${IBM_GITHUB_API_URI_BASE}
export GHE_API_TOKEN=${GH_TOKEN}

export REMOTE_BRANCH=${INTEGRATION_TESTING_BRANCH}
export SMOTAINER_INTEGRATION_BRANCH=${INTEGRATION_TESTING_BRANCH}
export DOCKER_REG=${ARTIFACTORY_DOCKER_STAGING_URL}
export DOCKER_REG_ICR=${IBMCLOUD_CR_URL_ONEPIPELINE}
export DOCKER_REG_ICR_SANDBOX=${VPC_ICR_SANDBOX_URL}
export DOCKER_REG_ICR_BACKUP=${IBMCLOUD_CR_URL_ONEPIPELINE_BACKUP}
export WCP_ARTIFACTORY_USERNAME=${ARTIFACTORY_USER}

### Used in workspace tests ###
export GENCTL_VETTED_VERSIONS=${GENCTL_VETTED_VERSIONS_FILE}
export VETTED_VERSION_REPO=${PATH_TO_VETTED_VERSIONS_REPO}
export RIAS_GLOBALS_REPO=${PATH_TO_RIAS_GLOBALS_REPO}

### Used in update vetted versions ###
export COMPONENT_FOR_VETTED_VERSION="${SMOTAINER_COMPONENT_NAME}"
export VERSION_FILE=${GENCTL_VETTED_VERSIONS_FILE}
export VETTED_VERSIONS_REPO_NAME=${GENCTL_VETTED_VERSIONS_REPO_NAME}
export DEV_REGIONS_VETTED_VERSIONS_REPO_NAME=${DEV_REGIONS_REPO_NAME}
export DEV_REGIONS_VETTED_VERSIONS_FILE=${DEV_REGIONS_MERGE_TO_MASTER_FILE}
