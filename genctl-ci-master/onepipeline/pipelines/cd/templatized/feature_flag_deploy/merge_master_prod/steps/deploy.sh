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

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="false"

# Set up SSH and GIT configs
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"
git config --global --add url."git@github.ibm.com:".insteadOf "https://github.ibm.com/"

# Setup some pre-requisites
mkdir ${TICKET_DIR}
mkdir ${SLACK_DIR}

notify_error(){
  echo "Error occurred while running merge pipeline"
  export STATUS="Feature flags deployment failed"
  ${PATH_TO_GENCTL_CI}/scripts/cd/send-slack.sh "${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml"
}

# Send slack notification when there is error
trap '[[ $? -ne 0 ]] && notify_error' EXIT

if [[ ! -e go-notify ]]; then
    echo "Cloning go-notify repo"
    mkdir go-notify
    git clone git@github.ibm.com:genctl-cicd/go-notify.git go-notify
    cd go-notify
    git checkout tags/${GO_NOTIFY_VERSION}
    echo "building and installing go-notify"
    go install
    cd ..
else
  echo "go-notify already exists"
fi


######## CREATE FF CR IN SERVICENOW ########

run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "create-cr" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/tasks/featureflags-create-cr.sh

# Do not run verify-cr-approval as "task" to grab the correct exit status of verify-cr-approval.sh
# Otherwise task updates the PR checks and messes up the exit code of the script
${PATH_TO_GENCTL_CI}/scripts/cd/verify-cr-approval.sh

######## IMPLEMENT/CANCEL CR ########
if [[ $? -eq 0 ]] ; then
  echo "CR approved, changing the CR state to implement"

  # Implement CR
  export STATE="start"
  ${PATH_TO_GENCTL_CI}/scripts/cd/ff_change_cr_status.sh
  if [[ $? -eq 0 ]] ; then
    echo "CR implemented. Closing CR as Successful ..."

    # Close CR
    export STATE="close"
    export CLOSE_NOTES="Pipeline succeeded"
    ${PATH_TO_GENCTL_CI}/scripts/cd/ff_change_cr_status.sh
  else
    echo "Failed to implement CR. Closing CR with issues"

    # Cancel CR
    export STATE="close"
    export CLOSE_NOTES="Pipeline failed to implement CR"
    ${PATH_TO_GENCTL_CI}/scripts/cd/ff_change_cr_status.sh
    exit 1
  fi

else
  echo "Failed to implement CR"

  # Cancel CR
  export STATE="cancel"
  export CLOSE_NOTES="Failed to implement CR"
  ${PATH_TO_GENCTL_CI}/scripts/cd/ff_change_cr_status.sh
  exit 1
fi


# Upload featureflags to COS
export FEATUREFLAGS_BASE_DIR="${PATH_TO_GENCTL_CI}/${COS_UPLOAD_CONTENT_ROOT}"
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "upload-featureflags-configs-to-cos" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/tasks/update-featureflags-config.sh "featureflags-config"

# Upload cm features-api-data to COS
export FEATUREFLAGS_BASE_DIR="${PATH_TO_GENCTL_CI}/${COS_UPLOAD_CONTENT_ROOT}"
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "upload-features-api-data-to-cos" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/tasks/update-featureflags-config.sh "features-api-config"

