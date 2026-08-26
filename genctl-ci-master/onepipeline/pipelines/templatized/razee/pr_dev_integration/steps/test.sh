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

export PIPELINE_TYPE="dev-integration-pr"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_PLATFORM_INVENTORY_REPO="${WORKSPACE}/${PLATFORM_INVENTORY_REPO_NAME}"
export PATH_TO_GENCTL_RELEASE_REPO="${WORKSPACE}/${GENCTL_RELEASE_REPO_NAME}"
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_ANTI_PATTERNS="${WORKSPACE}/${ANTI_PATTERNS_REPO_NAME}"
export PATH_TO_PIPELINE_TERRAFORM="${WORKSPACE}/${PIPELINE_TERRAFORM_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the SSH
eval "$(ssh-agent -s)" # Check if needed here
ssh-add - <<< "${GIT_PRIVATE_KEY}" # Check if needed here

# Set the flag that indicates if exit when a job fails
export EXIT_ON_JOB_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

### Unit tests ###
run_job "UNIT_TESTS" ${EXIT_ON_JOB_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/jobs/unit_tests.sh

### Hooks ###
run_hook "${CHECKS_PREFIX}" "${PIPELINE_NAMESPACE}" "${PATH_TO_WORKSPACE_REPO}" \
"${EXIT_ON_HOOK_FAILURE}" "${SET_GHE_STATUS_ON_HOOK}"

### K3S unit tests ###
# Used only by: regional-storage
run_job "K3S_UNITTEST" ${EXIT_ON_JOB_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/jobs/run_k3s_unit_test.sh 

### Upload to COS (If relevant label is set) ###
run_job "UPLOAD_TO_COS_IF_LABEL_EXISTS_IN_PR" ${EXIT_ON_JOB_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/jobs/upload_to_cos_if_label_exists_in_pr.sh
