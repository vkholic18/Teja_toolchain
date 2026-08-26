#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Source lock utils
source ${PATH_TO_GENCTL_CI}/tools/lock_and_queue_utils/lock.sh

# Configuration required for working with the git remote (Needed for acquire/release lock)
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

# Here we can't use run_task since we need a different approach for GitHub checks and ensure behavior

function ensure(){
    # This function ensures that the ffsld is scaled up, if it was scaled down
    # It also sends a slack to notify the end of the promotion tests, in case of failures
    COS_FFSLD_STATUS=$(get_env cos-ffsld-enabled)
    echo "COS_FFSLD_STATUS: $COS_FFSLD_STATUS"
    echo "TRAP called."
    # Skip ffsld scaled up when branch is release bundle
    if [[ $PR_BRANCH == *$RELEASE_BUNDLE* ]]; then return 0; fi
    
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
      export RECONNECT_COS=true
      ${PATH_TO_GENCTL_CI}/scripts/scale_ffsld_controller_promotion.sh
    fi

    ### Send slack notification to announce the end of the promotion tests ###
    echo "Sending slack message to notify cluster unlock"
    export SLACK_ICON=":scm-unlock:"
    export STATUS="Unlocking cluster for promotion testing"
    export STATUS_OPS="Unlocking cluster for OPS promotion testing"
    ${PATH_TO_GENCTL_CI}/scripts/cd/go-notify-promotion-tests.sh

}

# On failure or cancellation, scale down the ffdld controller
trap 'ensure' EXIT SIGTERM SIGINT

# Used for GHE checks
export FULL_CHECK_STR="${CHECKS_PREFIX}/${PROMOTION_TESTS_CHECK_LABEL}"

# Set pending status
set_ghe_commit_status "pending" "${PROMOTION_TESTS_CHECK_LABEL} starts to run." "${FULL_CHECK_STR}"

echo -e "${BYellow}Promotion Tests starts at: $(date)............. ${NC}"

START=$(date +%s)
RELEASE_BUNDLE="-RB-"
# Set exit on task
export EXIT_ON_TASK_FAILURE="true"

### Scale down ###
# Skip razee lock for when branch is release bundle, "-RB-"
if [[ ! $PR_BRANCH == *$RELEASE_BUNDLE* ]]; then
  export FF_SETLD_REPLICAS=${RAZEE_FF_SETLD_REPLICAS_MIN}
  run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${PROMOTION_TESTS_CHECK_LABEL} \
  "scale-down-ffsld-controller" ${EXIT_ON_TASK_FAILURE} \
  ${PATH_TO_GENCTL_CI}/scripts/scale_ffsld_controller_promotion.sh
 
  ## Send slack notification to announce the start of the promotion tests ###
  export SLACK_ICON=":scm-lock:"
  export STATUS="Locking cluster for promotion testing"
  export STATUS_OPS="Locking cluster for OPS promotion testing"
  ${PATH_TO_GENCTL_CI}/scripts/cd/go-notify-promotion-tests.sh
fi

COS_FFSLD_ENABLED=$(get_env cos-ffsld-enabled)
echo "COS FFSLD ENABLED: ${COS_FFSLD_ENABLED}"

### Validate promotion pipeline ###
run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${PROMOTION_TESTS_CHECK_LABEL} \
"validate-promotion-pipeline" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/validate_promotion_pipeline.sh

### Create promotion test configurations ###
run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${PROMOTION_TESTS_CHECK_LABEL} \
"create-promotion-test-configurations" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/create-promotion-test-configurations.sh

## Validate razee cluster ###
run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${PROMOTION_TESTS_CHECK_LABEL} \
"validate-razee-cluster" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/validate_razee_cluster_for_promotion.sh

# If USE_QZ2_WORKER is enabled and we have a genctl cluster, trigger QZ2 validation subpipeline
if [[ "${USE_QZ2_WORKER}" == "true" ]]; then
    # Retrieve the mzone name and worker ID set by validate_razee_cluster_for_promotion.sh
    GENCTL_MZONE_NAME=$(get_env genctl-mzone-name "")
    GENCTL_WORKER_ID=$(get_env genctl-worker-id "")

    if [[ ! -z "${GENCTL_MZONE_NAME}" ]] && [[ ! -z "${GENCTL_WORKER_ID}" ]]; then
        echo "=========================================="
        echo "Triggering QZ2 Validation Subpipeline"
        echo "MZONE: ${GENCTL_MZONE_NAME}"
        echo "Worker: ${GENCTL_WORKER_ID}"
        echo "=========================================="

        # Trigger the qz2-cluster-validations subpipeline
        # Use relative path since we're in the correct workspace context (one-pipeline-config-repo)
        ${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_v11_brt.sh \
            "qz2-cluster-validations" \
            "${GENCTL_WORKER_ID}" \
            "true" \
            "onepipeline/pipelines/cd/templatized/promotion/pr_master/.pipeline-config.yaml" \
            "${GENCTL_MZONE_NAME}"

        echo "QZ2 validation subpipeline completed successfully"
    else
        echo "No genctl cluster detected for QZ2 validation (MZONE: '${GENCTL_MZONE_NAME}', Worker: '${GENCTL_WORKER_ID}')"
    fi
fi

### Run promotion tests ###
run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${PROMOTION_TESTS_CHECK_LABEL} \
"run-promotion-tests" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/promotion_tests.sh

### Scale up ###
# Skip razee unlock for when branch is release bundle, "-RB-"
if [[ ! $PR_BRANCH == *$RELEASE_BUNDLE* ]]; then
  if [[ ${COS_FFSLD_ENABLED} == false ]]; then
    export FF_SETLD_REPLICAS=${RAZEE_FF_SETLD_REPLICAS_MAX}
    run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${PROMOTION_TESTS_CHECK_LABEL} \
    "scale-up-ffsld-controller" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/scale_ffsld_controller_promotion.sh
  else
    echo "Proceeding to reconnect cos remote resource"
    export RECONNECT_COS=true
    run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${PROMOTION_TESTS_CHECK_LABEL} \
    "reconnect_cos_remote_resource" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/scale_ffsld_controller_promotion.sh
  fi

  ## Send slack notification to announce the end of the promotion tests ###
  export SLACK_ICON=":scm-unlock:"
  export STATUS="Unlocking cluster for promotion testing"
  export STATUS_OPS="Unlocking cluster for OPS promotion testing"
  ${PATH_TO_GENCTL_CI}/scripts/cd/go-notify-promotion-tests.sh
fi

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Promotion Tests ends at: $(date)............. ${NC}"

echo -e "${BYellow}Promotion Tests took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete............. ${NC}"

# If we made it to here then is a success
set_ghe_commit_status "success" "${PROMOTION_TESTS_CHECK_LABEL} finished running" "${FULL_CHECK_STR}"