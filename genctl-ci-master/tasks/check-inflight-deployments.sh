#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script checks if there are any inflight deployments by comparing the environment.yaml
# on master and deployed_artifacts branches.

# =============================================================================================
set -eu

# Set default variables
export IS_ONE_PIPELINE_RUN=${IS_ONE_PIPELINE_RUN:-"false"}

# Source necessary tools
source ${PATH_TO_GENCTL_CI}/scripts/retry.sh

# Overrides for OnePipeline
if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
  export PROMOTE_FROM_ORG=${CD_PROMOTION_FROM_ORG}
  export PROMOTION_YAMLS_DIR="${WORKSPACE}/promotion-repo"
  export PIPELINE_TIMEOUT=${INTEGRATION_TESTING_TIMEOUT_MINS}
fi

export DEPLOYED_ARTIFACT_REPO=$PROMOTE_FROM_ORG/$(cat ${PROMOTION_YAMLS_DIR}/promotion_repo_name)
master_environment_yaml=${PROMOTION_YAMLS_DIR}/master_environment.yaml
deployed_artifacts_environment_yaml=${PROMOTION_YAMLS_DIR}/deployed_artifacts_environment.yaml

# Check to see if the repo has a deployed_artifacts branch, if not then exit cleanly.
if [ ! -f "$deployed_artifacts_environment_yaml" ]; then
  echo "No deployed_artifacts_branch defined, exiting this task and continuing pipeline"
  exit 0
else
  source ${PATH_TO_GENCTL_CI}/scripts/retry.sh
  retry python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/check_inflight_deployments/requirements.txt
  python3 ${PATH_TO_GENCTL_CI}/scripts/check_inflight_deployments/check-inflight-deployments.py ${master_environment_yaml} ${deployed_artifacts_environment_yaml}
fi
