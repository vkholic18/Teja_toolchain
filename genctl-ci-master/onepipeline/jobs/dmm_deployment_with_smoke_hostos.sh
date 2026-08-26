#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
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
    # This function does what is needed to "tear-down" the run of the deploy_dal/dmm_deploy
    # It receives arguments used to release the lock

    ALR=${1} # Either the name of the lock acquired or a string indicating that it was not acquired
    B_P=${2} # The path to the lock directory
    LCM=${3} # String used for git commit when releasing
    ATT=${4} # Max attempts to release lock
    SLP=${5} # Sleep time between attempts for lock release

    # First check if we have the lock
    # If we do have it, we need to scale up, rollback and then release the lock
    # If we do NOT have it, then we don't have to do anything
    if [[ ${ALR} != "NOT_ACQUIRED" ]]; then
        # If needed, release lock
        release_lock_if_acquired ${ALR} ${B_P} "${LCM}" ${ATT} ${SLP}
    else
        echo "Lock was not acquired, no need for any special tear-down actions..."
    fi
}

# In the ensure function we could just access them as they are environment variables, but we prefer pass them to make this little bit safer...
trap 'ensure ${ACQUIRE_LOCK_RESULT} ${PATH_TO_BRT} "${LOCK_CLAIMED_MSG}" 360 10 ' EXIT

SIMPLE_DMM_DEPLOY_GHE_LABEL=${SIMPLE_DMM_DEPLOY_GHE_LABEL:-"DMM_DEPLOY"}

if [[ "${SKIP_DEPLOY_DAL}" == "true" ]]; then
    echo "Skipping ${SIMPLE_DMM_DEPLOY_GHE_LABEL}..."
else
    # Try to acquire the lock
    export ACQUIRE_LOCK_RESULT="NOT_ACQUIRED"

    # Acquire lock should not stop on error
    set +e
    acquire_lock ${PATH_TO_BRT} ${BRT_ENVIRONMENT_NAME} "${LOCK_CLAIMED_MSG}" 900 10

    if [[ ${ACQUIRE_LOCK_RESULT} == "NOT_ACQUIRED" ]]
    then
        echo "Could not acquire lock, exiting...."
        exit 1
    fi

    echo "Lock acquired. Refreshing dev-regions to ensure no conflicts..."
    pushd ${PATH_TO_DEV_REGIONS_REPO}
    git fetch origin ${DEV_REGIONS_BRANCH} && git checkout ${DEV_REGIONS_BRANCH} && git reset --hard origin/${DEV_REGIONS_BRANCH}
    popd

    # Set exit on task
    export EXIT_ON_TASK_FAILURE="true"

    # Few configurations
    export DEPLOY_COMPONENT_ONLY="true"

    ### Start high level release bundles deploy with dev-mzone-mgmt logic ###
    # Move to the dev-regions repo
    pushd ${PATH_TO_DEV_REGIONS_REPO}

    # For easy use create a variable with the path to the YAML file to process (Which is the environment)
    YAML_FILE_TO_PROCESS="${MZONE_NAME_FOR_HIGH_LEVEL_RELEASE_BUNDLES}/${MZONE_NAME_FOR_HIGH_LEVEL_RELEASE_BUNDLES}.yaml"

    # Some more vars
    CURRENT_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BRANCH_TO_CREATE_NAME="${PIPELINE_REPO_ORG}_${PIPELINE_REPO_NAME}_RUN_FOR_PR_${PR_ID}_${CURRENT_TIMESTAMP}"

    # Create and move to local branch
    git checkout -b "${BRANCH_TO_CREATE_NAME}"

    # First check if the YAML file exists, if not, exit with error
    if [ ! -f "${YAML_FILE_TO_PROCESS}" ]
    then
        echo "Could not find file ${YAML_FILE_TO_PROCESS}"
        echo "Will exit with error..."
        exit 1
    fi

    # Use gh tool to create PR with label
    # Login
    gh auth login --hostname github.ibm.com --with-token <<< ${GH_TOKEN}

    echo "Checking for labels in the pr pipeline"
    echo $PR_BASEBRANCH
    if [[ "${APPLY_FULL_DEPLOYMENT}" != "true" ]]; then
        echo "Component only deployment with latest versions"
        export PATH_TO_VETTED_VERSION_FILES_FOR_REPLACEMENT="${PATH_TO_VETTED_VERSIONS_REPO}/${GENCTL_VETTED_VERSIONS_FILE}"
        export PATH_TO_PRE_INTEGRATION_FILES_FOR_REPLACEMENT="${PATH_TO_VETTED_VERSIONS_REPO}/pre-integration.yaml"
        ${PATH_TO_GENCTL_CI}/scripts/update_dmm_env_from_vetted_versions.py "vetted-versions.yaml" "${YAML_FILE_TO_PROCESS}" "only_hostos" "${PATH_TO_VETTED_VERSION_FILES_FOR_REPLACEMENT}" "${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml" "${PATH_TO_PRE_INTEGRATION_FILES_FOR_REPLACEMENT}"
    else
        echo "Scratch level deployment with latest versions from vetted-versions for all bundles"
        ${PATH_TO_GENCTL_CI}/scripts/update_dmm_env_from_vetted_versions.py "vetted-versions.yaml" "${YAML_FILE_TO_PROCESS}" "update_all"
    fi

    # First change is to add a comment in top of the file; this is to ensure that even if we are in a re-run we will be able to create a PR
    MSG_TO_ADD_TO_YAML_FILE="${BRANCH_TO_CREATE_NAME}"
    if grep -q "^ci_run_info:" "${YAML_FILE_TO_PROCESS}"; then
        awk -v ts="${MSG_TO_ADD_TO_YAML_FILE}" '/^ci_run_info:/{$2=ts}1' "${YAML_FILE_TO_PROCESS}" > temp.yaml && mv temp.yaml "${YAML_FILE_TO_PROCESS}"
    else
        awk -v ts="${MSG_TO_ADD_TO_YAML_FILE}" 'NR==1 {print "ci_run_info:", ts} 1' "${YAML_FILE_TO_PROCESS}" > temp.yaml && mv temp.yaml "${YAML_FILE_TO_PROCESS}"
    fi

    # update auto_update flag to true to enable the deployment using DMM
    sed -i 's/auto_update: \(true\|false\)/auto_update: true/' "${YAML_FILE_TO_PROCESS}"

    # update dev-region yaml config with newly built release bundles' versions
    ${PATH_TO_GENCTL_CI}/scripts/update_vetted_versions_for_dev_regions.py "${YAML_FILE_TO_PROCESS}" "${COMPONENT_FOR_VETTED_VERSION}" "${PR_HEADSHA}" -a "${ARTIFACTORY_DOCKER_STAGING_URL_PRIVATE}" -d "${APPLY_DMM_DEPLOY_PROCESS}" 
    
    # Add, commit and push with ready-to-deploy yaml file that will be merged in master
    COMM_MESSAGE="PR ${PR_ID} for ${ORG_AND_REPO} for ${MZONE_NAME_FOR_HIGH_LEVEL_RELEASE_BUNDLES} testbed"
    git add "${YAML_FILE_TO_PROCESS}"
    git commit -m "${COMM_MESSAGE}"
    git push origin "${BRANCH_TO_CREATE_NAME}"

    if [[ "${APPLY_FULL_DEPLOYMENT}" != "true" ]]; then
        gh pr create --title "Full deploy through ${COMM_MESSAGE}" --body "Created automatically by VPC CI automation" --label "for-CI-only-ignore-locks" --label "mzone-force-reboot"
    else
        gh pr create --title "Full deploy through ${COMM_MESSAGE}" --body "Created automatically by VPC CI automation" --label "for-CI-only-ignore-locks" --label "mzone-force-reboot" --label "rias-wipe"
    fi

    gh pr merge -s

    # Get the SHA of the merge commit and set it on variable for later use
    export SHA_OF_COMMIT_WITH_TRIGGERED_PIPELINE_DETAILS=$(gh pr view --json mergeCommit | jq -r '.mergeCommit.oid') # This gives us the SHA of the commit for that PR
    echo "SHA_OF_COMMIT_WITH_TRIGGERED_PIPELINE_DETAILS : ${SHA_OF_COMMIT_WITH_TRIGGERED_PIPELINE_DETAILS}"

    # Come back
    popd 

    export DEV_REGIONS_REPO_ORG_AND_NAME="${DEV_REGIONS_ORG_NAME}/${DEV_REGIONS_REPO_NAME}"

    python3 ${PATH_TO_GENCTL_CI}/scripts/get_mzone_mgmt_jenkins_run_result.py

    if [[ $? -eq 0 ]]
    then
        echo "Deploy succeeded with DMM, proceed with cluster validations"
    else
        echo "Deploy failed"
        exit 1
    fi

    # Move to the dev-regions repo to revert auto_update flag
    pushd ${PATH_TO_DEV_REGIONS_REPO}
    
    #revert auto_update flag
    REVERT_BRANCH_NAME=${BRANCH_TO_CREATE_NAME}_revert_flag
    git checkout ${DEV_REGIONS_BRANCH}
    git pull origin ${DEV_REGIONS_BRANCH}
    git checkout -b ${REVERT_BRANCH_NAME}

    sed -i 's/auto_update: true/auto_update: false/' "${YAML_FILE_TO_PROCESS}"
    COMM_MESSAGE_REVERT="PR ${PR_ID} for ${ORG_AND_REPO} for ${MZONE_NAME_FOR_HIGH_LEVEL_RELEASE_BUNDLES} to revert auto_update flag"
    git add "${YAML_FILE_TO_PROCESS}"
    git commit -m "${COMM_MESSAGE_REVERT}"

    git push origin $REVERT_BRANCH_NAME
    gh pr create --title "Created from ${COMM_MESSAGE_REVERT}" --body "Created automatically by VPC CI automation to set auto_update flag to false" --label "for-CI-only-ignore-locks"
    gh pr merge -s

    popd

    if [[ "${APPLY_FULL_DEPLOYMENT}" == "true" ]]; then

        run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "DMM_CLUSTER_VALIDATION_CHECKS" ${EXIT_ON_TASK_FAILURE} \
        ${PATH_TO_GENCTL_CI}/scripts/cluster_validation.sh

        run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "SMOKE" ${EXIT_ON_TASK_FAILURE} \
        ${PATH_TO_GENCTL_CI}/onepipeline/scripts/rias_smoke.sh
    fi

fi
