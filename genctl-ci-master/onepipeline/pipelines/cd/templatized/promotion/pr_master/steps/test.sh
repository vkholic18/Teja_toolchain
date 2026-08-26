#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Define type of pipeline (Used to search overrides)
# Some promotion pipelines use the non-standard PIPELINE_TYPE as 'promotion'
if [[ "${PIPELINE_REPO_NAME}" == *prod ]] || [[ "${PIPELINE_REPO_NAME}" == "staging" ]]; then
  PIPELINE_TYPE="promotion"
else
  PIPELINE_TYPE="pr"
fi
echo "PIPELINE_TYPE is ${PIPELINE_TYPE}"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_PLATFORM_INVENTORY_REPO="${WORKSPACE}/${PLATFORM_INVENTORY_REPO_NAME}"
export PATH_TO_VETTED_VERSIONS_REPO="${WORKSPACE}/${GENCTL_VETTED_VERSIONS_REPO_NAME}"
export PATH_TO_VV_UPDATED="" # Not supported in OnePipeline yet
export PATH_TO_MDS_REPO="${WORKSPACE}/${MICRO_DEPLOY_SERVER_REPO_NAME}"
export PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO="${WORKSPACE}/${GENESIS_DEPLOY_ARTIFACTS_REPO_NAME}"
export PATH_TO_RIAS_RELEASE_REPO="${WORKSPACE}/${RIAS_RELEASE_REPO_NAME}"
export PATH_TO_RIAS_ETCD_RELEASE_REPO="${WORKSPACE}/${RIAS_ETCD_RELEASE_REPO_NAME}"
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_RIAS_ETCD_GLOBALS_REPO="${WORKSPACE}/${RIAS_ETCD_GLOBALS_REPO_NAME}"
export PATH_TO_GENCTL_GLOBALS_REPO="${WORKSPACE}/${GENCTL_GLOBALS_REPO_NAME}"
export PATH_TO_DEV_REGIONS_REPO="${WORKSPACE}/${DEV_REGIONS_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the SSH - needed for repo clones in get-promotion-repo.sh
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

RELEASE_BUNDLE="-RB-"

function ensure(){
    # This function ensures that the ffsld is scaled up, if it was scaled down
    # It also sends a slack to notify the end of the promotion tests, in case of failures
    COS_FFSLD_STATUS=$(get_env cos-ffsld-enabled)
    echo "COS_FFSLD_STATUS: $COS_FFSLD_STATUS"
    echo "TRAP called."
    # Skip ffsld scaled up when branch is release bundle
    if [[ $PR_BRANCH == *$RELEASE_BUNDLE* ]]; then
      echo "$PR_BRANCH contains $RELEASE_BUNDLE, skipping"
      return 0
    fi

    if [[ $COS_FFSLD_STATUS == false ]]; then
      if [[ ${FF_SETLD_REPLICAS} == ${RAZEE_FF_SETLD_REPLICAS_MIN} ]]; then
          ### Scale up ###
          export FF_SETLD_REPLICAS=${RAZEE_FF_SETLD_REPLICAS_MAX}
          echo "Job failed. Scaling ffsld back up ..."
          ${PATH_TO_GENCTL_CI}/scripts/scale_ffsld_controller_promotion.sh
      elif [[ ${FF_SETLD_REPLICAS} == ${RAZEE_FF_SETLD_REPLICAS_MAX} ]]; then
        echo "ffsld is already scaled up. Skipping the scale operation."
      else
        echo "Unknown error. Manually verify that the cluster has ${RAZEE_FF_SETLD_REPLICAS_MAX} ffsld replicas."
      fi
    else
      echo "scale up the ffsld controller"
      export RECONNECT_COS=true
      ${PATH_TO_GENCTL_CI}/scripts/scale_ffsld_controller_promotion.sh
    fi

    ## Send slack notification to announce the end of the promotion tests ###
    echo "Sending slack message to notify cluster unlock"
    export SLACK_ICON=":scm-unlock:"
    export STATUS="Unlocking cluster for promotion testing"
    export STATUS_OPS="Unlocking cluster for OPS promotion testing"
    ${PATH_TO_GENCTL_CI}/scripts/cd/go-notify-promotion-tests.sh

}

# On failure or cancellation, scale down the ffdld controller
trap 'ensure' EXIT SIGTERM SIGINT

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if exit when a job fails
export EXIT_ON_JOB_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

# Get the environment.yaml from the promotion repo
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "get-promotion-repo" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/get-promotion-repo.sh

# Check and wait until the master and deployed_artifacts branches match
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "check-inflight-deployments" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/tasks/check-inflight-deployments.sh

# Run promotion tests
run_job "RUN_PROMOTION_TESTS" ${EXIT_ON_JOB_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/jobs/run_promotion_tests.sh
