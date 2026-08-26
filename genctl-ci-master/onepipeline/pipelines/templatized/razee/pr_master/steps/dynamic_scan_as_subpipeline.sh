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

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="razee"

export PIPELINE_TYPE="pr"

# Define the repositories to be cloned
REPOS_TO_CLONE="
RESOURCELOCK
INTEGRATION_TESTING
GENCTL_GLOBALS
RIAS_GLOBALS
DEV_REGIONS
RIAS_ETCD_RELEASE
"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Clone required repos
clone_repos_from_env_vars "${IBM_HTTPS_BASE_URL}" "${WORKSPACE}" "${REPOS_TO_CLONE}" 

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_RESOURCELOCK_REPO="${WORKSPACE}/${RESOURCELOCK_REPO_NAME}"
export PATH_TO_INTEGRATION_TESTING_REPO="${WORKSPACE}/${INTEGRATION_TESTING_REPO_NAME}"
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_RIAS_ETCD_RELEASE_REPO="${WORKSPACE}/${RIAS_ETCD_RELEASE_REPO_NAME}"
export PATH_TO_GENCTL_GLOBALS_REPO="${WORKSPACE}/${GENCTL_GLOBALS_REPO_NAME}"
export PATH_TO_DEV_REGIONS_REPO="${WORKSPACE}/${DEV_REGIONS_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Configuration required for working with the git remote (Needed for release lock)
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

function ensure(){
    # This function does what is needed to "tear-down" the run of the dynamic scan
    # It receives arguments used to release the lock
    COS_FFSLD_STTAUS=${1}
    ALR=${2} # The name of the lock acquired
    B_P=${3} # The path to the lock directory
    LCM=${4} # String used for git commit when releasing
    ATT=${5} # Max attempts to release lock
    SLP=${6} # Sleep time between attempts for lock release

    if [[ ${COS_FFSLD_STTAUS} == false ]]
    then
        ### Scale up ###
        export FF_SETLD_REPLICAS=${RAZEE_FF_SETLD_REPLICAS_MAX}
        ${PATH_TO_GENCTL_CI}/scripts/scale_ffsld_controller.sh
        
        if [[ $? -eq 0 ]] ; then
            ### Roll to dev-integration ###
            ${PATH_TO_GENCTL_CI}/scripts/rollback_environment_to_dev_integration.sh
        fi
        
        # If needed, release lock
        release_lock_if_acquired ${ALR} ${B_P} "${LCM}" ${ATT} ${SLP}
    else
        echo "cos enablement status is : ${COS_FFSLD_STTAUS}"
        echo "trapped for ensure with executed code: ${EXIT_CODE}"
        echo "Proceeding to reconnect cos remote resource"

        ${PATH_TO_GENCTL_CI}/scripts/reconnect_cos_remote_resource.sh

        # If needed, release lock
        release_lock_if_acquired ${ALR} ${B_P} "${LCM}" ${ATT} ${SLP}
    fi
}

# We assume that the lock we acquired is the one defined in the pipeline.yaml
export PARENT_PIPELINE_ACQUIRE_LOCK_RESULT="${BRT_ENVIRONMENT_NAME}"

# We get from the parent pipeline the claimed msg, this is used to release the lock
export PARENT_PIPELINE_LOCK_CLAIMED_MSG=$(get_env ci_parent_pipeline_lock_claimed_msg)

source ${PATH_TO_GENCTL_CI}/onepipeline/jobs/evaluate_status_of_cos_ffsld.sh

# In the ensure function we could just access them as they are environment variables, but we prefer pass them to make this little bit safer...
trap 'ensure ${COS_FFSLD_ENABLED} ${PARENT_PIPELINE_ACQUIRE_LOCK_RESULT} ${PATH_TO_BRT} "${PARENT_PIPELINE_LOCK_CLAIMED_MSG}" 360 10' EXIT

# Set exit on task
export EXIT_ON_TASK_FAILURE="true"

echo -e "${BYellow}Dynamic scan starts at: $(date)............. ${NC}"
START=$(date +%s)

# This is required because since at this point pipeline_namespace is still PR; OnePipeline does not create the asset for us
# We need to explicitly create the asset
merge_to_dev_int_pipeline_id=$(get_env root_pipeline_id) # This is actually the pipeline_id of the merge to dev-integration
merge_to_dev_int_pipeline_run_id=$(get_env root_pipeline_run_id) # This is actually the pipeline_run_id of the merge to dev-integration
pipeline_run_str="pipelinerun://${merge_to_dev_int_pipeline_id}/${merge_to_dev_int_pipeline_run_id}" # This is the format that create_pipeline_asset uses

echo "We will explicitly call create_pipeline_asset with the following parameter:"
echo ${pipeline_run_str}

# Temporary fix for evidence issues
source "${ONE_PIPELINE_PATH}/tools/pipeline_utils"
init_cos_env

source "${ONE_PIPELINE_PATH}/internal/pipeline/create_pipeline_asset"
create_pipeline_asset "${pipeline_run_str}"

# Setting the pipeline_namespace property to ci 
set_env pipeline_namespace ci

# Actual execution of dynamic scan
run_task "false" ${CHECKS_PREFIX} "DYNAMIC_SCAN" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/zap/trigger_zap_scans.sh

# Bring back the pipeline_namespace property to its original value
set_env pipeline_namespace pr

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Dynamic scan ends at: $(date)............. ${NC}"
echo -e "${BYellow}Dynamic scan took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete............. ${NC}" 
