#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

export PATH_TO_BRT="${PATH_TO_RESOURCELOCK_REPO}/${CLOUDNET_MLX_ONE_PIPELINE_POOL}"
export SDN_DEVOPS_PR_SANITY_TESTS_ENVIRONMENT_NAME=$(yq -r '.env_for_sanity_tests | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)

# Extract the endpoint, this gives us stuff like eu-gb, us-south, etc
ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)
export LOCK_CLAIMED_MSG="${ORG_AND_REPO} ${PIPELINE_TYPE} run ${BUILD_NUMBER} - 1P_INFO: ${PIPELINE_ID}/${PIPELINE_RUN_ID}/${ENDPOINT}"

export CRONJOB_BRANCH=$(get_env cronjob-branch)