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

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="razee"

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

# Copy custom_required_checks.json to workspace root directory
cp ${PATH_TO_GENCTL_CI}/hack/ci/custom_required_checks.json ${PATH_TO_WORKSPACE_REPO}/

if [ $? -eq 0 ]; then
    echo "custom_required_checks.json copied successfully"
    set_env cra-bom-generate "0"
    set_env cra-vulnerability-scan "0"
    set_env branch-protection-rules-path "custom_required_checks.json"
else
  echo "custom_required_checks.json file copy failed. Aborting code-compliance-checks"
  exit 1
fi

"/opt/commons/compliance-checks/run.sh"
