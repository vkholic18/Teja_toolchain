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

# Define type of pipeline (Used to search overrides)
PIPELINE_TYPE="pr"

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

######## VALIDATE FEATUREFLAGS CONFIGURATION ########

print_divider
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "validate-featureflags-config" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/validate_featureflags_config.sh
print_divider

######## GET FEATUREFLAGS METADATA ########

print_divider
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "get-feature-flag-metadata" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/get_feature_flag_meta.sh
print_divider

######## CREATE CR IN SERVICENOW ########

print_divider
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "create-cr" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/cd/create_snow_ticket.sh
print_divider

######## INSTALL SERVICENOW CLI ########

print_divider
mkdir -p ${WORKSPACE}/service-now-cli
pushd ${WORKSPACE}/service-now-cli
git -c advice.detachedHead=false clone --depth 1 -b ${SNOW_CLI_VERSION} https://${GIT_TOKEN}@github.ibm.com/SqlServiceWdp/service-now-cli . && \
  go build -o ${WORKSPACE}/service-now-cli
popd

######## VALIDATE DEPLOYMENT ########

# We want to check the deployment type, and verify this isn't a featureflag or razee deployment. If it is exit and close the CR.
deploy_type="$(jq -r .DeployType ${TICKET_DIR}/data.json)"
if [[ "${deploy_type}" == "featureflag" || "${deploy_type}" == "razee" ]]; then
  echo "Featureflag or razee deployment detected in legacy release bundle pipeline. To fix this, rerun this pipeline with the automation label."

  # Cancel CR
  export CR_STATE="cancel"
  export CLOSE_CATEGORY="cancelled"
  export CLOSE_NOTES="CR opened by incorrect pipeline."
  run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "change-cr-status-to-cancel" ${EXIT_ON_TASK_FAILURE} ${PATH_TO_GENCTL_CI}/scripts/cd/update_cr_status.sh
  exit 1
fi

print_divider
