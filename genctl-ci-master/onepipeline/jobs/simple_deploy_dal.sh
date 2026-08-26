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


function ensure(){
    # This function does what is needed to "tear-down" the run of deploy_dal
    # It receives arguments used to release the mzone that was acquired (If any)

    CMR=${1} # Either the name of the claimed mzone or a string indicating that it was not acquired

    # First check if we acquired an mzone
    # If we did NOT acquired, then we don't have to do anything
    # If we did, we need to release it
    if [[ ${CMR} != "NOT_ACQUIRED" ]]
    then
        ${PATH_TO_GENCTL_CI}/tools/lock_and_queue_utils/move_resource_lock.sh
    else
        echo "Mzone was not claimed, no need for any special tear-down actions..."
    fi
}

# In the ensure function we could just access them as they are environment variables, but we prefer pass them to make this little bit safer...
trap 'ensure ${CLAIM_MZONE_RESULT}' EXIT

# For github check
SIMPLE_DEPLOY_DAL_GHE_CHECK_LABEL=${SIMPLE_DEPLOY_DAL_GHE_CHECK_LABEL:-"DEPLOY_DAL"}

# By default we assume that we didn't claim an mzone
CLAIM_MZONE_RESULT="NOT_ACQUIRED"

# Path to DEV-REGIONS repo
export PATH_TO_DEV_REGIONS_REPO=${WORKSPACE}/${DEV_REGIONS_REPO_NAME}

if [[ "${SKIP_DEPLOY_DAL}" == "true" ]]; then
    echo "Skipping ${SIMPLE_DEPLOY_DAL_GHE_CHECK_LABEL}..."    
elif [[ "${APPLY_DMM_DEPLOY_PROCESS}" != true ]]; then
    # Save the original flags (Since we are sourcing on this shell a script that changes them)
    orig_opts=$-

    # Try to claim an mzone (Use source because we need to get the Mzone name - or empty - into this same shell)
    source ${PATH_TO_GENCTL_CI}/tools/lock_and_queue_utils/wait_in_queue_and_get_lock.sh

    # Set back the original flags
    set -${orig_opts}

    # Check if we have the lock, if not exit
    if [[ ${CLAIM_MZONE_RESULT} == "NOT_ACQUIRED" ]]
    then
        echo "No MZone for running Deploy dal and smoke"
        
        # Since we could not acquire the lock, we need to "remove" ourselves from the queue
        run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "QUEUE_CLEANUP" ${EXIT_ON_TASK_FAILURE} \
        ${PATH_TO_GENCTL_CI}/tools/lock_and_queue_utils/queue_cleanup.sh
        
        exit 1
    fi

    ### Deploy dal ###
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "${SIMPLE_DEPLOY_DAL_GHE_CHECK_LABEL}" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/deploy-next-generation-v2.sh
else
    echo "Using new deploy dal replacement process and exporting necessary env vars" 
    
    if [[ -f ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml ]]; then
        export MZONE_NAME_FOR_HIGH_LEVEL_RELEASE_BUNDLES=$(yq -r '.dmm_deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml | cut -d ',' -f1)
        export CLAIM_MZONE_RESULT=$(yq -r '.dmm_deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml | cut -d ',' -f2)
        export BRT_ENVIRONMENT_NAME=$(yq -r '.dmm_deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml | cut -d ',' -f1)
        if [[ ! -z "${MZONE_NAME_FOR_HIGH_LEVEL_RELEASE_BUNDLES}" ]] && [[ ! -z "${BRT_ENVIRONMENT_NAME}" ]]
        then
            ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)
            export LOCK_CLAIMED_MSG="${ORG_AND_REPO} ${PIPELINE_TYPE} run ${BUILD_NUMBER} - 1P_INFO: ${PIPELINE_ID}/${PIPELINE_RUN_ID}/${ENDPOINT}"
            export PATH_TO_BRT="${PATH_TO_RESOURCELOCK_REPO}/${MASCD_BRT_POOL}"       
            run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "${SIMPLE_DEPLOY_DAL_GHE_CHECK_LABEL}" ${EXIT_ON_TASK_FAILURE} \
            ${PATH_TO_GENCTL_CI}/onepipeline/jobs/dmm_deployment_with_smoke_hostos.sh
        else
            echo "Could not find in pipeline.yaml rule_tag entry under deployment section"
            echo "Will exit with error..."
            exit 1
        fi
    else
        echo "Deploy dal replacement process relies on pipeline.yaml file, which was not found"
        echo "Exit with error..."
        exit 1
    fi
fi
