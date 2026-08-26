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
    # This function does what is needed to "tear-down" the run of the BRT
    # It receives arguments used to release the lock
    COS_FFSLD_STTAUS=${1} # Status of FFSLD COS status
    ALR=${2} # Either the name of the lock acquired or a string indicating that it was not acquired
    B_P=${3} # The path to the lock directory
    LCM=${4} # String used for git commit when releasing
    ATT=${5} # Max attempts to release lock
    SLP=${6} # Sleep time between attempts for lock release
    EXIT_CODE=${7} #exit code from last function before entering ensure
    NTRDS=${8} #a string indicating if need to run or not dynamic scan - either true or false

    if [[ ${COS_FFSLD_STTAUS} == false ]]
    then
    echo "trapped for ensure with executed code: ${EXIT_CODE}"
        echo NEED_TO_RUN_DYNAMIC_SCAN: ${NTRDS}
        # First check if we have the lock
        # If we do have it, we need to scale up, rollback and then release the lock
        # If we do NOT have it, then we don't have to do anything
        if [[ ${ALR} != "NOT_ACQUIRED" ]]; then
            # if dynamic scan defined in pipeline.yaml and all functions under trap finished successfully
            # do not release lock and continue to dynamic scan
            if [[ ${NTRDS} == "true" && ${EXIT_CODE} -eq 0 ]]; then
                echo "This workspace test includes dynamic scan testing and BRT finished successfully. \
                Scale up razee controller, rollback environment and release lock will be after dynamic scan execution."
            else
                echo "Proceeding to scale up razee controller, rollback environment and release lock."
                ### Scale up ###
                export FF_SETLD_REPLICAS=${RAZEE_FF_SETLD_REPLICAS_MAX}

                ${PATH_TO_GENCTL_CI}/scripts/scale_ffsld_controller.sh

                if [[ $? -eq 0 ]] ; then
                    ### Roll to dev-integration ###
                    ${PATH_TO_GENCTL_CI}/scripts/rollback_environment_to_dev_integration.sh
                fi

                # If needed, release lock
                release_lock_if_acquired ${ALR} ${B_P} "${LCM}" ${ATT} ${SLP}
            fi
        else
            echo "Lock was not acquired, no need for any special tear-down actions..."
        fi
    else
        echo "cos enablement status is : ${COS_FFSLD_STTAUS}"
        echo "trapped for ensure with executed code: ${EXIT_CODE}"
        echo NEED_TO_RUN_DYNAMIC_SCAN: ${NTRDS}
        # First check if we have the lock
        # If we do have it, we need to scale up, rollback and then release the lock
        # If we do NOT have it, then we don't have to do anything
        if [[ ${ALR} != "NOT_ACQUIRED" ]]; then
            # if dynamic scan defined in pipeline.yaml and all functions under trap finished successfully
            # do not release lock and continue to dynamic scan
            if [[ ${NTRDS} == "true" && ${EXIT_CODE} -eq 0 ]]; then
                echo "This workspace test includes dynamic scan testing and BRT finished successfully. \
                Reconnect cos remote resource to scale up razee controller, rollback environment and release lock will be after dynamic scan execution."
            else

                if [[ "${USE_QZ2_WORKER}" == true ]]; then
                    # Source tekton api utils
                    source ${PATH_TO_GENCTL_CI}/onepipeline/utils/tekton_api_utils.sh
                    
                    # Set few variables
                    MAX_ATTEMPTS_BUSY_WAIT=${MAX_ATTEMPTS_BUSY_WAIT:-960}
                    SLEEP_TIME_BUSY_WAIT=${SLEEP_TIME_BUSY_WAIT:-30}
                    ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)
                    BASE_URL="api.${ENDPOINT}.devops.cloud.ibm.com"

                    CURRENT_PIPELINE_RUNS=$(get_data pending-tasks)

                    FORMATTED_PIPELINES=""
                    COUNTER=1
                    for pipeline_id in ${CURRENT_PIPELINE_RUNS}; do
                        # Remove "async-" prefix if present
                        clean_id=${pipeline_id#"async-"}
                        # Add to formatted string with genctl-env-N prefix
                        if [ -z "${FORMATTED_PIPELINES}" ]; then
                            FORMATTED_PIPELINES="genctl-env-${COUNTER}/${clean_id}"
                        else
                            FORMATTED_PIPELINES="${FORMATTED_PIPELINES} genctl-env-${COUNTER}/${clean_id}"
                        fi
                        COUNTER=$((COUNTER + 1))
                    done

                    # Update the variable with the formatted version
                    GENCTL_CLEANUP_PIPELINES="${FORMATTED_PIPELINES}"

                    echo "Formatted pipeline IDs: ${GENCTL_CLEANUP_PIPELINES}"

                    #track_for_completion
                    wait_until_all_pipeline_runs_finish "${BASE_URL}" \
                    "${PIPELINE_ID}" "${GENCTL_CLEANUP_PIPELINES}" \
                    "${MAX_ATTEMPTS_BUSY_WAIT}" "${SLEEP_TIME_BUSY_WAIT}"
                fi
                echo "Proceeding to reconnect cos remote resource"

                ${PATH_TO_GENCTL_CI}/scripts/reconnect_cos_remote_resource.sh

                # If needed, release lock
                release_lock_if_acquired ${ALR} ${B_P} "${LCM}" ${ATT} ${SLP}
                
            fi
        else
            echo "Lock was not acquired, no need for any special tear-down actions..."
        fi
    fi

}

# Evaluates if for given ws, configured env is has disabled tarditional ffsld controller in globals repo
source ${PATH_TO_GENCTL_CI}/onepipeline/jobs/evaluate_status_of_cos_ffsld.sh

#debug prupose only
echo "COS_FFSLD_ENABLED: " ${COS_FFSLD_ENABLED}

# In the ensure function we could just access them as they are environment variables, but we prefer pass them to make this little bit safer...
trap 'ensure ${COS_FFSLD_ENABLED} ${ACQUIRE_LOCK_RESULT} ${PATH_TO_BRT} "${LOCK_CLAIMED_MSG}" 360 10 "$?" ${NEED_TO_RUN_DYNAMIC_SCAN} ' EXIT

# Used for GHE checks
export FULL_CHECK_STR="${CHECKS_PREFIX}/${WORKSPACE_TESTS_CHECK_LABEL}"

# Set pending status
set_ghe_commit_status "pending" "${WORKSPACE_TESTS_CHECK_LABEL} starts to run." "${FULL_CHECK_STR}"
echo -e "${BYellow}Workspace Tests starts at: $(date)............. ${NC}"
START=$(date +%s)
# Try to acquire the lock
export ACQUIRE_LOCK_RESULT="NOT_ACQUIRED"

# Acquire lock should not stop on error
set +e
acquire_lock ${PATH_TO_BRT} ${BRT_ENVIRONMENT_NAME} "${LOCK_CLAIMED_MSG}" 900 10

if [[ ${ACQUIRE_LOCK_RESULT} == "NOT_ACQUIRED" ]]
then
    echo "Could not acquire lock, exiting...."
    set_ghe_commit_status "failure" "${WORKSPACE_TESTS_CHECK_LABEL} starts to run." "${FULL_CHECK_STR}"
    exit 1
fi

# Set exit on job
export EXIT_ON_JOB_FAILURE="true"

# Set exit on task
export EXIT_ON_TASK_FAILURE="true"

### Scale up ###
export FF_SETLD_REPLICAS=${RAZEE_FF_SETLD_REPLICAS_MAX}

# # Evaluates if for given ws, configured env is has disabled tarditional ffsld controller in globals repo
# source ${PATH_TO_GENCTL_CI}/onepipeline/jobs/evaluate_status_of_cos_ffsld.sh

if [[ ${COS_FFSLD_ENABLED} == false ]]
then

    run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${WORKSPACE_TESTS_CHECK_LABEL} \
    "scale-up-ffsld-controller" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/scale_ffsld_controller.sh

    ### Roll environment to default rule ###
    run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${WORKSPACE_TESTS_CHECK_LABEL} \
    "roll-environment-to-default-rule" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/roll_environment_to_default_rule.sh

    ### Scale down ###
    export FF_SETLD_REPLICAS=${RAZEE_FF_SETLD_REPLICAS_MIN}

    run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${WORKSPACE_TESTS_CHECK_LABEL} \
    "scale-down-ffsld-controller" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/scale_ffsld_controller.sh

    ### Validate razee cluster ###
    run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${WORKSPACE_TESTS_CHECK_LABEL} \
    "validate-razee-cluster" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/validate_razee_cluster.sh

    ### Validate feature flags ###
    run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${WORKSPACE_TESTS_CHECK_LABEL} \
    "validate-featureflags" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/validate_featureflag.sh

else
    echo "COS enabled for the env"
    source ${PATH_TO_GENCTL_CI}/scripts/update_dev_regions_env_config/update_dev_regions_env_config.sh

    ## Scale razee ffsld resource ###
    run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${WORKSPACE_TESTS_CHECK_LABEL} \
    "disconnect-cos-remote-resource-and-roll-env-to-default-rules" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/scale_ffsld_controller.sh

    ### Validate razee cluster ###
    run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${WORKSPACE_TESTS_CHECK_LABEL} \
    "validate-razee-cluster" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/validate_razee_cluster.sh

    ### Validate feature flags ###
    run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${WORKSPACE_TESTS_CHECK_LABEL} \
    "validate-featureflags" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/validate_featureflag.sh

    ### Validate genctl validation subpipelines ###
    run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${WORKSPACE_TESTS_CHECK_LABEL} \
    "validate-genctl-cluster-subpipeline" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/validate_genctl_validation_subpipeline.sh

fi

# if [[ -f "${CI_TEMP_DIR}/${EVIDENCE_IN_PR_PREREQ_COMMANDS_FILE_NAME}" ]]
# then
#     # Source preparation file in order to be able to collect evidence
#     source "${CI_TEMP_DIR}/${EVIDENCE_IN_PR_PREREQ_COMMANDS_FILE_NAME}"
# else
#     echo "At this point, we expected to have a file in ${CI_TEMP_DIR}/${EVIDENCE_IN_PR_PREREQ_COMMANDS_FILE_NAME}"
#     echo "Will exit with error..."
#     exit 1
# fi

if [[ ! -z "${RUN_BRT_AND_NGDC_IN_PR_TO_MASTER}" && "${RUN_BRT_AND_NGDC_IN_PR_TO_MASTER}" == "true" ]]
then
    ### This triggers two parallell subpipelines; one in TAAS and one in NGDC worker ###
    echo "Will run BRT and NGDC in parallell..."
    run_job "BRT_AND_NGDC" ${EXIT_ON_JOB_FAILURE} \
    ${PATH_TO_GENCTL_CI}/onepipeline/jobs/brt_and_ngdc_v11_er.sh
else
    ### Run workspace tests - This runs in a sub-pipeline in TAAS worker ###
    echo "Will run regular BRT..."
    run_task_alternative ${SET_GHE_STATUSES} ${CHECKS_PREFIX} ${WORKSPACE_TESTS_CHECK_LABEL} \
    "run-tests" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/onepipeline/scripts/brt_v11_er.sh
fi

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Workspace Tests ends at: $(date)............. ${NC}"
echo -e "${BYellow}Workspace Tests took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete............. ${NC}" 

# If we made it to here then is a success
set_ghe_commit_status "success" "${WORKSPACE_TESTS_CHECK_LABEL} finished running" "${FULL_CHECK_STR}"