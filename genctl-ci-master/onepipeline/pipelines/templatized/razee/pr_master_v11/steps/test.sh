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

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="razee"

export PIPELINE_TYPE="pr"

# Define the repositories to be cloned
REPOS_TO_CLONE="
PLATFORM_INVENTORY
RESOURCELOCK
GENCTL_GLOBALS
RIAS_GLOBALS
DEV_REGIONS
GENESIS_DEPLOY_ARTIFACTS
RIAS_ETCD_GLOBALS
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
export PATH_TO_PLATFORM_INVENTORY_REPO="${WORKSPACE}/${PLATFORM_INVENTORY_REPO_NAME}"
export PATH_TO_RESOURCELOCK_REPO="${WORKSPACE}/${RESOURCELOCK_REPO_NAME}"
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_RIAS_ETCD_GLOBALS_REPO="${WORKSPACE}/${RIAS_ETCD_GLOBALS_REPO_NAME}"
export PATH_TO_RIAS_ETCD_RELEASE_REPO="${WORKSPACE}/${RIAS_ETCD_RELEASE_REPO_NAME}"
export PATH_TO_GENCTL_GLOBALS_REPO="${WORKSPACE}/${GENCTL_GLOBALS_REPO_NAME}"
export PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO="${WORKSPACE}/${GENESIS_DEPLOY_ARTIFACTS_REPO_NAME}"
export PATH_TO_DEV_REGIONS_REPO="${WORKSPACE}/${DEV_REGIONS_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the SSH
eval "$(ssh-agent -s)" # Check if needed here
ssh-add - <<< "${GIT_PRIVATE_KEY}" # Check if needed here

# Note: Here we use a mix of jobs and tasks, therefore we configure both flags

# Set the flag that indicates if exit when a job fails
export EXIT_ON_JOB_FAILURE="true"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

### Check vetted files exist (Since is only one task no need for job) ###
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "CHECK_INVENTORY_VETTED_FILES" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/check_vetted_files.sh

### Create file used for collect evidence in PR
run_task "false" ${CHECKS_PREFIX} "CREATE_EVIDENCE_IN_PR_PREREQ_COMMANDS_FILE" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/prepare_prereq_file_for_evidence_in_pr.sh

# Save artifacts is required both for collecting evidence of BRT and for dynamic scan
# Since all the razee workspaces do BRT (Though not all of them do dynamic scan) we can save artifacts at this point
run_task "false" ${CHECKS_PREFIX} "SAVE_ARTIFACTS_FOR_PR_EVIDENCE" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/save_artifacts_v11.sh

### Workspace tests ###
run_job "RUN_WORKSPACE_TESTS" ${EXIT_ON_JOB_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/jobs/run_workspace_tests.sh

if [[ "${NEED_TO_RUN_DYNAMIC_SCAN}" == "true" ]]
then
    # At this point we assume that we have the lock since the BRT run and passed and we are in a workspace that runs dynamic scan
    # Therefore we can safely proceed to run dynamic scan
    ### Run dynamic scan - This runs in a sub-pipeline in TAAS worker ###
    # Important: Note that this runs on a fire and forget mode, it means we trigger the subpipeline but we don't wait for it to finish
    # As long as the triggering of the subpipeline works, then tekton/code-unit-tets check will be passed
    
    # First run some commands required as pre-requisite
    # The goal of this commands is to "trick" OnePipeline to believe we are in a merge pipeline while we are in a PR one
    # The commands are on a .sh file that was created during the check vetted files task
    echo "As preparation for dynamic scan, will source a shell script that contains the following content: "
    cat "${CI_TEMP_DIR}/${EVIDENCE_IN_PR_PREREQ_COMMANDS_FILE_NAME}"
    source "${CI_TEMP_DIR}/${EVIDENCE_IN_PR_PREREQ_COMMANDS_FILE_NAME}"

    # Fire and forget subpipeline for dynamic scan
    run_task "false" ${CHECKS_PREFIX} "DYNAMIC_SCAN_SUBPIPELINE_TRIGGER" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/onepipeline/scripts/dynamic_scan_subpipeline_trigger_v11.sh "onepipeline/pipelines/templatized/razee/pr_master_v11/.pipeline-config-subpipeline-configurations.yaml" 

fi
# If we reach this point, we assume everything went well
# We can set the GHE status check of unit-tests (Which was set to pending by One-Pipeline/GitHub) to success
# The reason that we have to do this by ourselves, is that despite One-Pipeline could do this for us, it will be only in the code-pr-finish stage
# This doesn't work for us since we have the auto-merge logic implemented in the code-compliance stage, which runs before the code-pr finish
# In other words, if we don't set this by ourselves, we will reach auto-merge and the status check will still be pending which; preventing us from merging

set_ghe_commit_status "success" "${TASK_NAME} finished running.. (Status set by vpc-ci)" "${ONEPIPELINE_CHECKS_PREFIX}/${TASK_NAME}"
