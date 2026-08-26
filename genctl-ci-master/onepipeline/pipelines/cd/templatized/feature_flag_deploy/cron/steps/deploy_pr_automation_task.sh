#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
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

# Set the SSH - needed for repo clones in get-promotion-repo.sh
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if exit when a job fails
export EXIT_ON_JOB_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

########  Automation task ########

print_divider
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "PR creation for api-spec-version change" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/featureflags_pr_automation_task.sh
print_divider