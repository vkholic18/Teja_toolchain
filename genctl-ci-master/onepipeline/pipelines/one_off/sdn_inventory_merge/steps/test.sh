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

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}" 

# Come back
popd

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_SDN_DEVOPS_REPO="${WORKSPACE}/${SDN_DEVOPS_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Configuration required for working with the git remote (Needed for acquire/release lock)
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

# Get the PR number
get_last_commit_associated_pr_number "${PATH_TO_WORKSPACE_REPO}"

# Some useful prints
echo "Will run script ${PATH_TO_SDN_DEVOPS_REPO}/hack/ci/sdn_release.sh, passing the following arguments:"
echo "#1=${PATH_TO_SDN_DEVOPS_REPO} which comes from environment variable PATH_TO_SDN_DEVOPS_REPO"
echo "#2=${LAST_COMMIT_ASSOCIATED_PR_NUMBER} which comes from environment variable LAST_COMMIT_ASSOCIATED_PR_NUMBER (Calculated through the call to function get_last_commit_associated_pr_number)"

# Actual call
${PATH_TO_SDN_DEVOPS_REPO}/hack/ci/sdn_release.sh "${PATH_TO_SDN_DEVOPS_REPO}" "${LAST_COMMIT_ASSOCIATED_PR_NUMBER}"
