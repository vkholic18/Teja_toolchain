#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

export PATH_TO_RELEASE_ENVIRONMENT=${WORKSPACE}/release-environment

### Used in workspace tests ###
export PATH_TO_BRT="${PATH_TO_RESOURCELOCK_REPO}/${MASCD_BRT_POOL}"
export BRT_ENVIRONMENT_NAME=$(yq -r '.deployment.iks_cluster_name | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)

export RAZEE_HOTFIX=""
export USE_LOCALLY_BUILT_SMOTAINER_IMAGE="true"

export CSI_NAMESPACE="qa-test"
export DOCKER_NAME="amd64_qa_test_smotainer"
export ICR_MIGRATION_MODE="true"

