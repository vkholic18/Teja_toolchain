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

# Basic logging info
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/basic_logging_info.sh

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

### All Scans ###
run_job "ALL_SCANS" ${EXIT_ON_JOB_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/jobs/all_scans_master.sh

### Check vetted files exist (Since is only one task no need for job) ###
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "CHECK_INVENTORY_VETTED_FILES" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/check_vetted_files.sh

### Create file used for collect evidence in PR
run_task "false" ${CHECKS_PREFIX} "CREATE_EVIDENCE_IN_PR_PREREQ_COMMANDS_FILE" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/prepare_prereq_file_for_evidence_in_pr.sh

# Save artifacts is required both for collecting evidence of BRT and for dynamic scan
# Since all the razee workspaces do BRT (Though not all of them do dynamic scan) we can save artifacts at this point
run_task "false" ${CHECKS_PREFIX} "SAVE_ARTIFACTS_FOR_PR_EVIDENCE" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/save_artifacts.sh
