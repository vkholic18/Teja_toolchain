#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Used in workspace tests ###
export PATH_TO_BRT="${PATH_TO_RESOURCELOCK_REPO}/${MASCD_BRT_POOL}"
export BRT_ENVIRONMENT_NAME=$(yq -r '.deployment.iks_cluster_name // ""' "${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml" | sed -E 's/(dal)[0-9]{2}/\1/')
export NEED_TO_RUN_DYNAMIC_SCAN=$(yq ". | has(\"dynamic_scan\")" ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export APIKEY_ALIAS=$(yq -r '.deployment.api_key_alias | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)

# The save artifacts in PR to master of razee deals only with the first image
export SAVE_ARTIFACTS_ONLY_FIRST_IMAGE_MODE="true"
export SAVE_ARTIFACTS_SKIP_PACKAGES="true"

# Extract the endpoint, this gives us stuff like eu-gb, us-south, etc
ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)


export LOCK_CLAIMED_MSG="${ORG_AND_REPO} ${PIPELINE_TYPE} run ${BUILD_NUMBER} - 1P_INFO: ${PIPELINE_ID}/${PIPELINE_RUN_ID}/${ENDPOINT}"

# This is to simulate the fact that in the Concourse task we don't use the paramter of the pipeline params
# A better approach would be pass the parameter in Concourse but in that case need to change the if to check for = "false" instead of -z 
# (https://github.ibm.com/genctl-cicd/genctl-ci/blob/44999dd48819a4cf5fa8b8165db9f368772d580d/scripts/run_workspace_tests.sh#L71)
export RAZEE_HOTFIX=""

### Used in build ###
export UPLOAD="false"

### Used in auto-merge ###
export APPROVE_BEFORE_MERGE="true"
