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

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="hotfix-razee"

export PIPELINE_TYPE="pr"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

popd

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Login to docker proxy
set_env cra-custom-script-path "${PATH_TO_GENCTL_CI}/scripts/vpc_ci_prepare_before_cra.sh"

script_path="$WORKSPACE_PATH/hack/ci/cra-setup.sh"

if [ -e "$script_path" ]; then
  eval "$(ssh-agent -s)"
  ssh-add - <<< "${GIT_PRIVATE_KEY}"
  echo "Pre CRA cript exists. Running..."
  source "$script_path"
fi

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="false"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

"/opt/commons/compliance-checks/run.sh"


## for now skip auto merge
# ### Auto-merge ### (Since is only one task no need for job)
# run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "AUTO_MERGE" ${EXIT_ON_TASK_FAILURE} \
# ${PATH_TO_GENCTL_CI}/scripts/merge_pr/merge_pr.sh
