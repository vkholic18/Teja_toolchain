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

# Define the repositories to be cloned
REPOS_TO_CLONE="
RIAS_GLOBALS
GENCTL_VETTED_VERSIONS
"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Clone required repos
clone_repos_from_env_vars "${IBM_HTTPS_BASE_URL}" "${WORKSPACE}" "${REPOS_TO_CLONE}" 

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_VETTED_VERSIONS_REPO="${WORKSPACE}/${GENCTL_VETTED_VERSIONS_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# This is required because since at this point pipeline_namespace is still PR; OnePipeline does not create the asset for us
# We need to explicitly create the asset
merge_to_dev_int_pipeline_id=$(get_env root_pipeline_id) # This is actually the pipeline_id of the merge to dev-integration
merge_to_dev_int_pipeline_run_id=$(get_env root_pipeline_run_id) # This is actually the pipeline_run_id of the merge to dev-integration
pipeline_run_str="pipelinerun://${merge_to_dev_int_pipeline_id}/${merge_to_dev_int_pipeline_run_id}" # This is the format that create_pipeline_asset uses

echo "We will explicitly call create_pipeline_asset with the following parameter:"
echo ${pipeline_run_str}

# Temporary fix for evidence issues
source "${ONE_PIPELINE_PATH}/tools/pipeline_utils"
init_cos_env

source "${ONE_PIPELINE_PATH}/internal/pipeline/create_pipeline_asset"
create_pipeline_asset "${pipeline_run_str}"

# Setting the pipeline_namespace property to ci 
set_env pipeline_namespace ci

# Set evidence pending
collect_evidence "brt" "pending" "com.ibm.acceptance_tests" "artifact" "app-image"

# Actual execution of BRT
${PATH_TO_GENCTL_CI}/scripts/run_workspace_tests.sh

# Check status and set collect evidence accordingly
if [[ $? -eq 0 ]]
then
    echo "BRT Passed"
    # Temporary comment out due to issues 
    collect_evidence "brt" "success" "com.ibm.acceptance_tests" "artifact" "app-image"
    # Bring back the pipeline_namespace property to its original value
    set_env pipeline_namespace pr
else
    # Temporary comment out due to issues 
    collect_evidence "brt" "failure" "com.ibm.acceptance_tests" "artifact" "app-image"
    # Bring back the pipeline_namespace property to its original value
    set_env pipeline_namespace pr
    exit 1
fi