#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
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
export PIPELINE_TEMPLATE_TYPE="uuc-ci"

PIPELINE_TYPE="merge"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

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

### ICR Backup if required ###
if [[ "${ICR_MIGRATION_MODE}" == "true" ]]
then
    ## ICR Backup ##
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "ICR_BACKUP" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/icr_backup.sh
fi

## Move from pre release to vetted ###
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "MOVE_CANDIDATE_FILES" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/move_files.sh "move_from_pre_release_to_vetted"

## Check inventory files exist ###
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "CHECK_INVENTORY_VETTED_FILES" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/check_vetted_files.sh

### Move from vetted to final destination (Since is only one task no need for job) ###
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "MOVE_CANDIDATE_FILES" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/move_files.sh "move_from_vetted_to_final_destination"

## Process inventory file with the deployment zip ###
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "PROCESS_INVENTORY_AND_DEPLOYMNET_FILES" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/download_merge_and_upload_inventory.sh

### Inventory add ###
echo "**** IMPROVED INVENTORY LOGIC ****"
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "DOWNLOAD_JSON_AND_ADD_INVENTORY" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/download_json_file_and_inventory_add_improved.sh
