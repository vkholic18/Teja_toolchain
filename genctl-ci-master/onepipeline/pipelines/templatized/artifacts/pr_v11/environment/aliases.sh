#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Aliases are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

### Used for searching cra setup ###
export WORKSPACE_PATH=${PATH_TO_WORKSPACE_REPO}

### Used in check pr title ###
export PR_NUMBER=${PR_ID}
export WORKSPACE_ORG=${PIPELINE_REPO_ORG}
export WORKSPACE_REPO=${PIPELINE_REPO_NAME} 
export TOKEN=${GITHUB_API_KEY}

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
export ARTIFACTORY_URL=${ARTIFACTORY_DOCKER_PROD_URL}

export CC_ARTIFACTORY_GENERIC_REPO_PATH=${ARTIFACTORY_GENERIC_REPO_PATH}
export CC_GO_IMAGE_PATH=${GOLANG_CI_IMAGE_PATH}
export CC_GO_IMAGE_TAG=${GOLANG_CI_IMAGE_MANIFEST_TAG}
export CC_ARTIFACTORY_BASE_URL=${ARTIFACTORY_BASE_URL}
export CC_ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH=${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}

### Used also in build (Upload related) ###
export SKIP_UPLOAD_PACKAGES=${SKIP_UPLOAD_PACKAGES_ON_PR_PIPELINE}
export UPLOAD=${UPLOAD_TO_REGISTRY_FLAG} # This is for docker images

### Used in travis for vpc-vault ###
export TR_ARTIFACTORY_ACCESS_TOKEN=${CC_ARTIF_ACCESS_TOKEN}
export TR_ARTIFACTORY_LOGIN=${ARTIFACTORY_USER}

# To have same effect that in concourse of in this template not having SKIP_CHECK_PR_TITLE
export SKIP_CHECK_PR_TITLE=${SKIP_CHECK_PR_TITLE_ARTIFACTS}

export CC_ARTIFACTORY_HOST=${ARTIFACTORY_DOCKER_URL}
export CC_ARTIFACTORY_DEBIAN_REPO_PATH=${ARTIFACTORY_DEBIAN_SANDBOX_REPO_PATH}
export CC_GIT_SHA=$(load_repo app-repo commit)

# Travis
export TR_ARTIFACTORY_LOGIN=${ARTIFACTORY_USER}
export TR_ARTIFACTORY_ACCESS_TOKEN=${CC_ARTIF_ACCESS_TOKEN}
export VPC_ICR_URL=${VPC_ICR_SANDBOX_URL}
