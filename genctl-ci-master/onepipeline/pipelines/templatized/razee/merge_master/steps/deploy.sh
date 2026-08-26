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

# Source utility to get equivalent dev-int version from master
source ${PATH_TO_GENCTL_CI}/scripts/get_dev_int_version_equivalent_to_current_master.sh

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="razee"

export PIPELINE_TYPE="merge"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# DRY_RUN is set to be false which will update the version in JIRA. 
export EXIT_ON_TASK_FAILURE_UPDATE_RELEASE_VERSION="false"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}" 

# Come back
popd

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_DEV_REGIONS_REPO="${WORKSPACE}/${DEV_REGIONS_REPO_NAME}"
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

### Auto-Semver ### (Since is only one task no need for job)
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "AUTO_SEMVER" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/tasks/auto-semver.sh

### Get equivalent dev-integration SHA and SemVer to be used during the pipeline ###
get_dev_int_version_equivalent_to_current_master ${PATH_TO_WORKSPACE_REPO} ${REPO_MAIN_BRANCH}

### UPDATE_CHNAGELOG ### (Since is only one task no need for job)
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "UPDATE_CHNAGELOG" ${EXIT_ON_TASK_FAILURE_UPDATE_RELEASE_VERSION} \
${PATH_TO_GENCTL_CI}/scripts/update_workspace_changelog.sh

### update-release-version ### (Since is only one task no need for job)
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "UPDATE_RELEASE_VERSION" ${EXIT_ON_TASK_FAILURE_UPDATE_RELEASE_VERSION} \
${PATH_TO_GENCTL_CI}/scripts/update_release_version.sh

### Retag ###
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "RETAG" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/retag_dev_int_to_master.sh

### ICR Backup if required ###
if [[ "${ICR_MIGRATION_MODE}" == "true" ]]
then
    ## ICR Backup ##
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "ICR_BACKUP" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/icr_backup.sh
fi

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

### Move ZIP from vetted to final destination (Since is only one task no need for job) ###
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "MOVE_ZIP" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/move_files.sh "move_from_vetted_to_final_destination"

### Download JSON and execute cocoa inventory commands (Since is only one task no need for job) ###
echo "**** IMPROVED INVENTORY LOGIC ****"
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "DOWNLOAD_JSON_AND_ADD_INVENTORY" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/download_json_file_and_inventory_add_improved.sh
