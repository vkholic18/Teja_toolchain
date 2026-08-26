#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
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

### Used in check pr title ###
export WORKSPACE_ORG=${PIPELINE_REPO_ORG}
export WORKSPACE_REPO=${PIPELINE_REPO_NAME} 
export TOKEN=${GITHUB_API_KEY}

### Used in verify PR head ###
export SKIP_VERIFY_PR_HEAD=${SKIP_CHECK_PR_TO_MASTER_IS_FROM_DEV_INT}
export EXPECTED_PR_HEAD_ORG_AND_REPO=${ORG_AND_REPO}
export EXPECTED_PR_HEAD_BRANCH=${MASCD_INTEGRATION_BRANCH_NAME}

### Used in build ###
export CC_REPO_BRANCH=${PR_BASEBRANCH}
export CC_REPO_NAME=${PIPELINE_REPO_NAME}
export CC_REPO_ORG=${PIPELINE_REPO_ORG}
export CC_ARTIFACTORY_SANDBOX_DOCKER_URL=${ARTIFACTORY_SANDBOX_DOCKER_URL}
export CC_GO_IMAGE_PATH=${GOLANG_CI_IMAGE_PATH}
export CC_GO_IMAGE_TAG=${GOLANG_CI_IMAGE_MANIFEST_TAG}
export CC_ARTIFACTORY_BASE_URL=${ARTIFACTORY_BASE_URL}
export ART_URL=${ARTIFACTORY_DOCKER_PROD_URL}
export ARTIFACTORY_DOCKER_PROXY_URL=${ARTIFACTORY_DOCKER_PROXY_URL}
export TR_ARTIFACTORY_ACCESS_TOKEN=${CC_ARTIF_ACCESS_TOKEN}
export TR_ARTIFACTORY_LOGIN=${ARTIFACTORY_USER}

### Used in auto-merge ###
export PR_SHA=${PR_HEADSHA}
export TOKEN=${GHE_PAT}

### Used for docker images upload
export UPLOAD=${UPLOAD_TO_REGISTRY_FLAG}

### Used for package upload
export SKIP_UPLOAD_PACKAGES=${SKIP_UPLOAD_PACKAGES_ON_PR_PIPELINE}
