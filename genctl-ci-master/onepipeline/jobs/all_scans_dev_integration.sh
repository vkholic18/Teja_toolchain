#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
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

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

echo -e "${BYellow}All Scans starts at: $(date)............. ${NC}"
START=$(date +%s)

SCRIPT_PATH="${PATH_TO_WORKSPACE_REPO}/hack/ci/custom_pre_scan_script.sh"

if [[ -f "$SCRIPT_PATH" && -x "$SCRIPT_PATH" ]]; then
    echo "Executing $SCRIPT_PATH"
    source $SCRIPT_PATH
else
    echo "Script $SCRIPT_PATH not found or not executable, moving to next step."
fi

## Check pr title and commits ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "SCAN_PR_TITLE" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/check_pr_title/check_pr_title.sh

## Go vetting ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "SCAN_GO_VETTING" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/go-vetting.sh ${PATH_TO_WORKSPACE_REPO}

## Verify workspace dependencies file ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "${WORKSPACE_DEPENDENCIES_FILE_CHECK_LABEL}" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/verify_workspace_dependencies_file/verify_workspace_dependencies_file.sh

## Validate version file ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "VALIDATE_VERSION_FILE" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/validate_version.sh

## Validate API version ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "VALIDATE_API_VERSION" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/validate_api_version.sh

## Validate regional version ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "VALIDATE_REGIONAL_VERSION" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/validate_regional_version.sh

## Validate client API version ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "VALIDATE_CLIENT_API_VERSION" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/validate_client_api_version.sh

# ## Check secrets ## - TODO: Finish porting

## Check secrets label ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "${SECRETS_CHECK_LABEL}" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/check_secrets_label/check_secrets_label.sh

## Validate Razee YAML Files ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "VALIDATE_RAZEE_YAML_FILES" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/validate_razee_yaml_files.sh ${PATH_TO_WORKSPACE_REPO} ${PATH_TO_GENCTL_CI}

if [[ $SKIP_JINJA_VALIDATION = false ]]; then
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "VALIDATE_JINJA_FILES" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/onepipeline/scripts/jinja_validation.sh
fi

## Check duplicate keys in mustache templates ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "razee_check_duplicate_keys" ${EXIT_ON_TASK_FAILURE_RAZEE_CHECK_DUPLICATE_KEYS} \
${PATH_TO_GENCTL_CI}/scripts/razee_check_duplicate_keys/razee_check_duplicate_keys.sh

## Validate Razee remote resource ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "VALIDATE_RAZEE_REMOTE_RESOURCE" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/validate_remote_resource/validate_remote_resource.sh

## Validate global keys ##
# run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "validate-global-keys" ${EXIT_ON_TASK_FAILURE} \
# ${PATH_TO_GENCTL_CI}/scripts/validate_global_keys.sh

## Validate required deployment labels ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "validate-required-deployment-labels" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/git_meta_label_injector/validate_deployment_labels.sh

## Validate third party images file ##
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "VALIDATE_THIRD_PARTY_IMAGES_FILE" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/third_party_images/validate_third_party_images_file.sh

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}All Scans ends at: $(date)............. ${NC}"
echo -e "${BYellow}All Scans took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete............. ${NC}"
