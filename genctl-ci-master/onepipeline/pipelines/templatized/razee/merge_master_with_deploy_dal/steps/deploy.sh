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
export PATH_TO_RESOURCELOCK_REPO="${WORKSPACE}/${RESOURCELOCK_REPO_NAME}"
export PATH_TO_GENCTL_RELEASE_REPO="${WORKSPACE}/${GENCTL_RELEASE_REPO_NAME}"
export PATH_TO_RIAS_RELEASE_REPO="${WORKSPACE}/${RIAS_RELEASE_REPO_NAME}"
export PATH_TO_RIAS_ETCD_RELEASE_REPO="${WORKSPACE}/${RIAS_ETCD_RELEASE_REPO_NAME}"
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_VETTED_VERSIONS_REPO="${WORKSPACE}/${GENCTL_VETTED_VERSIONS_REPO_NAME}"
export PATH_TO_PLATFORM_INVENTORY_REPO="${WORKSPACE}/${PLATFORM_INVENTORY_REPO_NAME}"
export PATH_TO_INTEGRATION_TESTING_REPO="${WORKSPACE}/${INTEGRATION_TESTING_REPO_NAME}"

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
export SET_GHE_STATUSES="false"

### Auto-Semver ###
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "AUTO_SEMVER" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/tasks/auto-semver.sh

### Get equivalent dev-integration SHA and SemVer to be used during the pipeline ###
get_dev_int_version_equivalent_to_current_master ${PATH_TO_WORKSPACE_REPO} ${REPO_MAIN_BRANCH}

### update-release-version ### 
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "UPDATE_RELEASE_VERSION" ${EXIT_ON_TASK_FAILURE_UPDATE_RELEASE_VERSION} \
${PATH_TO_GENCTL_CI}/scripts/update_release_version.sh

### Prepare release bundles ###
run_job "PREPARE_RELEASE_BUNDLES" ${EXIT_ON_JOB_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/jobs/prepare_high_level_release_bundles.sh

### Upload to COS ### 
if [[ $SKIP_COS_UPLOAD = true ]]; then
    echo "Skipping Upload to COS task"
else
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "UPLOAD_TO_COS" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/tasks/upload-to-cos.sh
fi

### Update vetted versions ###
export LAUNCH_DARKLY_USE_IN_DEFAULT_RULE="false"
export LAUNCH_DARKLY_CREATE_VARIATION_ONLY="true"
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "UPDATE_VETTED_VERSIONS" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/tasks/update-ld-feature-flag.sh


### DMM integration and smoke
if [[ "${APPLY_DMM_DEPLOY_PROCESS}" == true ]]
then
    run_job "DMM_DEPLOY" ${EXIT_ON_JOB_FAILURE} \
    ${PATH_TO_GENCTL_CI}/onepipeline/jobs/simple_deploy_dal_with_smoke_new.sh
else
    run_job "DEPLOY_DAL_AND_SMOKE" ${EXIT_ON_JOB_FAILURE} \
    ${PATH_TO_GENCTL_CI}/onepipeline/jobs/deploy_dal_and_smoke.sh
fi

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

### Bump components ###
run_job "BUMP_COMPONENTS" ${EXIT_ON_JOB_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/jobs/bump_components.sh

### Upload to COS ###
# We already performed Upload to COS in the stage of preparation the release bundle for testing, we don't need to do it again.
# We should not do it OnePipeline because the whole process is running in the same contained and which add deployment label twice
# Issue-4464

### Update vetted versions ###
export LAUNCH_DARKLY_USE_IN_DEFAULT_RULE="true"
export LAUNCH_DARKLY_CREATE_VARIATION_ONLY="false"
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "UPDATE_VETTED_VERSIONS" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/tasks/update-ld-feature-flag.sh


### Move ZIP from vetted to final destination ###
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "MOVE_ZIP" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/move_files.sh "move_from_vetted_to_final_destination"

### Download JSON and execute cocoa inventory commands ###
echo "**** IMPROVED INVENTORY LOGIC ****"
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "DOWNLOAD_JSON_AND_ADD_INVENTORY" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/download_json_file_and_inventory_add_improved.sh
