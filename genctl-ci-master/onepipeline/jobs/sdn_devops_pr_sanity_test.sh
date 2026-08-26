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

    ALR=${1} # Either the name of the lock acquired or a string indicating that it was not acquired
    B_P=${2} # The path to the lock directory
    LCM=${3} # String used for git commit when releasing
    ATT=${4} # Max attempts to release lock
    SLP=${5} # Sleep time between attempts for lock release

    # First check if we have the lock
    # If we do have it, we need to release the lock
    # If we do NOT have it, then we don't have to do anything
    if [[ ${ALR} != "NOT_ACQUIRED" ]]; then
            # If needed, release lock
            release_lock_if_acquired ${ALR} ${B_P} "${LCM}" ${ATT} ${SLP}
    else
        echo "Lock was not acquired, no need for any special tear-down actions..."
    fi
}

# In the ensure function we could just access them as they are environment variables, but we prefer pass them to make this little bit safer...
trap 'ensure ${ACQUIRE_LOCK_RESULT} ${PATH_TO_BRT} "${LOCK_CLAIMED_MSG}" 360 10' EXIT

# Validate what we got from the pipeline.yaml
if [[ ${SDN_DEVOPS_PR_SANITY_TESTS_ENVIRONMENT_NAME} == mzone* ]]; then

    # Try to acquire the lock
    export ACQUIRE_LOCK_RESULT="NOT_ACQUIRED"

    # Acquire lock should not stop on error
    set +e
    acquire_lock ${PATH_TO_BRT} "${SDN_DEVOPS_PR_SANITY_TESTS_ENVIRONMENT_NAME}" "${LOCK_CLAIMED_MSG}" 900 10

    if [[ ${ACQUIRE_LOCK_RESULT} == "NOT_ACQUIRED" ]]
    then
        echo "Could not acquire lock, exiting...."
        exit 1
    fi
    
    # At this point we have the lock; we can proceed to run
    ${PATH_TO_WORKSPACE_REPO}/run_sanity.sh
else
    echo "In pipeline.yaml file, configuration is for running sanity tests on ${SDN_DEVOPS_PR_SANITY_TESTS_ENVIRONMENT_NAME}, which is not valid, as name needs to start with mzone"
fi