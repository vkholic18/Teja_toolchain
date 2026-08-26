#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
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
export PIPELINE_TEMPLATE_TYPE="minimal"

PIPELINE_TYPE="merge"

REPOS_TO_CLONE="
CI_CD_UTILS
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

# Gets used for all common utilities for CI/CD
export PATH_TO_CICD_UTILS="${WORKSPACE}/${CI_CD_UTILS_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the flag that indicates if exit when a job fails
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

# ---------------------------------------------------------------------------
# Clone the workspace repository
# WORKSPACE_REPOSITORY_URL  : the Git URL of the workspace repo (read from pipeline
#                       environment / inventory)
# PATH_TO_WORKSPACE_REPO : local directory where the repo will be cloned into
# GIT_TOKEN_PATH      : path to the file containing the Git auth token used
#                       by the one-pipeline clone_repo helper
# ---------------------------------------------------------------------------
echo ""
echo ">>> Cloning workspace repository..."
echo "    Source URL : ${WORKSPACE_REPOSITORY_URL}"
echo "    Target dir : ${PATH_TO_WORKSPACE_REPO}"
. "${ONE_PIPELINE_PATH}"/git/clone_repo "${WORKSPACE_REPOSITORY_URL}" "${WORKSPACE_REPOSITORY_BRANCH}" "${PATH_TO_WORKSPACE_REPO}" ${GIT_TOKEN_PATH}
echo "<<< Workspace repository cloned successfully."

# In some flows we want to skip the build itself, so check 
if [[ $SKIP_BUILD = true ]]; then
    echo "Skipping build..."
else
    ## Build ##
    cd ${PATH_TO_WORKSPACE_REPO}
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "BUILD" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_WORKSPACE_REPO}/hack/ci/build.sh
fi
