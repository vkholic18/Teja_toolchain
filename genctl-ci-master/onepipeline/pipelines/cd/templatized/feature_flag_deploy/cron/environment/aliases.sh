#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Inherited from CI templates ###
export REPOSITORY_NAME=${ORG_AND_REPO}
export GHE_API_URL=${IBM_GITHUB_API_URI_BASE}
export GHE_API_TOKEN=${GH_TOKEN}

### Used in scale up, scale down, validate razee cluster and validate feature flags, workspace tests ###
export WCP_ARTIFACTORY_USERNAME=${ARTIFACTORY_USER}

### Used in scale up, scale down, validate razee cluster and validate feature flags ###
export ART_URL=${ARTIFACTORY_DOCKER_PROD_URL}
export IMG_TO_RUN_PATH=${GOLANG_CI_IMAGE_PATH}
export IMG_TO_RUN_TAG=${GOLANG_CI_IMAGE_TAG}

### Used in validate featureflags ###
export FAIL_IF_ERROR=${VALIDATE_FEATUREFLAGS_FAIL_IF_ERROR}

### Used in go-notify slack notification ###
export GH_API_ENDPOINT=${IBM_GITHUB_API_URI_BASE}

### General aliases used for configuration checks
export WORKSPACE_REPO_NAME=${PIPELINE_REPO_NAME}
export WORKSPACE_REPO_ORG=${PIPELINE_REPO_ORG}
export PATH_TO_WORKSPACE_REPO="${WORKSPACE}/${WORKSPACE_REPO_NAME}"
export PR_NUMBER=${PR_ID}
