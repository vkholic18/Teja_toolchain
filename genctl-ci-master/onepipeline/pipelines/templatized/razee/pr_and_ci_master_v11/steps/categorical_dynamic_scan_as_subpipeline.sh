#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
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

# We assume that the lock we acquired is the one defined in the pipeline.yaml
export PARENT_PIPELINE_ACQUIRE_LOCK_RESULT="${BRT_ENVIRONMENT_NAME}"

# We get from the parent pipeline the claimed msg, this is used to release the lock
export PARENT_PIPELINE_LOCK_CLAIMED_MSG=$(get_env ci_parent_pipeline_lock_claimed_msg)

export CATEGORY_NAME=$(get_env category-name)
export API_FILE_NAME=$(get_env api-file-name)
export PROFILES=$(get_env profiles)
export ENDPOINTS=$(get_env endpoints)
export EXCLUDE_ENTRIES=$(get_env exclude-entries "[]")

# Set exit on task
export EXIT_ON_TASK_FAILURE="true"
export SET_GHE_STATUSES="false"
export CHECKS_PREFIX="dynamic-scan"

# ### Check vetted files exist (Since is only one task no need for job) ###
# run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "CHECK_INVENTORY_VETTED_FILES" ${EXIT_ON_TASK_FAILURE} \
# ${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/check_vetted_files.sh

# ### Create file used for collect evidence in PR
# run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "CREATE_EVIDENCE_IN_PR_PREREQ_COMMANDS_FILE" ${EXIT_ON_TASK_FAILURE} \
# ${PATH_TO_GENCTL_CI}/onepipeline/scripts/prepare_prereq_file_for_evidence_in_pr.sh
echo "After"

export PIPELINE_NAMESPACE=$(get_env pipeline_namespace)

echo "printing PIPELINE_NAMESPACE"
echo "${PIPELINE_NAMESPACE}"

set_env pipeline_namespace pr

echo "printing PIPELINE_NAMESPACE 2"
echo "${PIPELINE_NAMESPACE}"

# # This is required because since at this point pipeline_namespace is still PR; OnePipeline does not create the asset for us
# # We need to explicitly create the asset
# merge_to_dev_int_pipeline_id=$(get_env root_pipeline_id) # This is actually the pipeline_id of the merge to dev-integration
# merge_to_dev_int_pipeline_run_id=$(get_env root_pipeline_run_id) # This is actually the pipeline_run_id of the merge to dev-integration
# pipeline_run_str="pipelinerun://${merge_to_dev_int_pipeline_id}/${merge_to_dev_int_pipeline_run_id}" # This is the format that create_pipeline_asset uses

# echo "We will explicitly call create_pipeline_asset with the following parameter:"
# echo ${pipeline_run_str}

# # Temporary fix for evidence issues
# source "${ONE_PIPELINE_PATH}/tools/pipeline_utils"
# init_cos_env

# Get parent pipeline information
get_parent_pipeline_info

# source "${ONE_PIPELINE_PATH}/internal/pipeline/create_pipeline_asset"
# create_pipeline_asset "${pipeline_run_str}"

list_artifacts
echo "list_artifacts"

# # Setting the pipeline_namespace property to ci 
# set_env pipeline_namespace ci

# Actual execution of dynamic scan
run_task "false" ${CHECKS_PREFIX} "DYNAMIC_SCAN" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/zap/trigger_zap_scans_v2.sh

# # Bring back the pipeline_namespace property to its original value
# set_env pipeline_namespace pr

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Dynamic scan ends at: $(date)............. ${NC}"
echo -e "${BYellow}Dynamic scan took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete............. ${NC}"
