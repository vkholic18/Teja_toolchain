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

export PIPELINE_TYPE="dev-integration-merge"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}" 

# Come back
popd

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_RIAS_RELEASE_REPO="${WORKSPACE}/${RIAS_RELEASE_REPO_NAME}"
export PATH_TO_DEV_REGIONS_REPO="${WORKSPACE}/${DEV_REGIONS_REPO_NAME}"
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_RIAS_ETCD_GLOBALS_REPO="${WORKSPACE}/${RIAS_ETCD_GLOBALS_REPO_NAME}"
export PATH_TO_RIAS_ETCD_RELEASE_REPO="${WORKSPACE}/${RIAS_ETCD_RELEASE_REPO_NAME}"
export PATH_TO_GENCTL_GLOBALS_REPO="${WORKSPACE}/${GENCTL_GLOBALS_REPO_NAME}"
export PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO="${WORKSPACE}/${GENESIS_DEPLOY_ARTIFACTS_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the SSH
eval "$(ssh-agent -s)" # Check if needed here
ssh-add - <<< "${GIT_PRIVATE_KEY}" # Check if needed here

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="false"

source ${PATH_TO_GENCTL_CI}/onepipeline/jobs/evaluate_status_of_cos_ffsld.sh

### Upload to COS ### (Since is only one task no need for job)
if [[ $SKIP_COS_UPLOAD = true ]]; then
    echo "Skipping Upload to COS task"
else
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "UPLOAD_TO_COS" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/tasks/upload-to-cos.sh
fi

### Update vetted versions ### (Since is only one task no need for job)
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "UPDATE_VETTED_VERSIONS" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/tasks/update-ld-feature-flag.sh

### Update environment file ### (Since is only one task no need for job)
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "UPDATE_ENV_FILE" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/update_dev_regions_environment.sh 

### Move from pre release to vetted ###
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "MOVE_CANDIDATE_FILES" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/move_files.sh "move_from_pre_release_to_vetted"

### Generate FFSLD and push to COS file ###
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "GENERATE_FFSLD" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/tasks/generate_ffsld.sh
