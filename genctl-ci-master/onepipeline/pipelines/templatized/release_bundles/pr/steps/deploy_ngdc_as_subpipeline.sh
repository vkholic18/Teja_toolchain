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

# Get the parent pipeline info to pass it to the sub-pipeline
get_parent_pipeline_info

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="release_bundles"

INITIAL_PIPELINE_TYPE="pr"
get_pipeline_type "${PR_BASEBRANCH}" "${INITIAL_PIPELINE_TYPE}" "${REPO_MAIN_BRANCH}"

# Define the repositories to be cloned
REPOS_TO_CLONE="
GENCTL_CD
GENCTL_VETTED_VERSIONS
RESOURCELOCK
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
export PATH_TO_VETTED_VERSIONS_REPO="${WORKSPACE}/${GENCTL_VETTED_VERSIONS_REPO_NAME}"
export PATH_TO_GENCTL_CD_REPO="${WORKSPACE}/${GENCTL_CD_REPO_NAME}"
export PATH_TO_RESOURCELOCK_REPO="${WORKSPACE}/${RESOURCELOCK_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the SSH
eval "$(ssh-agent -s)" # Check if needed here
ssh-add - <<< "${GIT_PRIVATE_KEY}" # Check if needed here

# Set the flag that indicates if exit when a job fails
export EXIT_ON_JOB_FAILURE="true"

## NGDC Deploy ##
run_job "RELEASE_BUNDLES_NGDC_DEPLOY" ${EXIT_ON_JOB_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/jobs/release_bundles_ngdc_deploy.sh
