#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

export CC_TRAVIS_API_ENDPOINT=${TRAVIS_API_ENDPOINT}

export CC_PR_ID=${PR_ID}
export CC_REPO_ORG=${PIPELINE_REPO_ORG}
export CC_REPO_NAME=${PIPELINE_REPO_NAME}


# Since we are in a PR, the branch is the base branch of the PR
export CC_REPO_BRANCH=${PR_BASEBRANCH}

# Since we are in a PR, the SHA is the SHA of the head branch
export CC_GIT_SHA=${PR_HEADSHA}

export REPOSITORY_WORKSPACE_REPO_NAME=$CC_REPO_NAME

export CC_TRAVIS_CLI_VERSION="${TRAVIS_CLI_VERSION}"
export CC_GO_IMAGE_PATH="${GOLANG_CI_IMAGE_PATH}"
export CC_ARTIFACTORY_HOST="${ARTIFACTORY_SANDBOX_DOCKER_URL}"
export CC_ARTIFACTORY_GENERIC_REPO_PATH="${ARTIFACTORY_GENERIC_REPO_PATH}"
export VPC_ICR_URL="${VPC_ICR_SANDBOX_URL}"
