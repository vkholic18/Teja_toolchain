#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -o pipefail
set -e

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# source required properties
source $PATH_TO_PIPELINE/environment/secrets.sh

pushd "${PATH_TO_WORKSPACE_REPO}"

if [[ "${GIT_PRIVATE_KEY:-}" != "" ]]; then
  eval "$(ssh-agent -s)"
  ssh-add - <<< "${GIT_PRIVATE_KEY}"
  mkdir -p ~/.ssh
  ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
  
  # Define the repositories to be cloned
  REPOS_TO_CLONE="GOLDI_LOCKS"

  # Move to the CI temp dir
  pushd "${CI_TEMP_DIR}"

  # Convert & source pipeline params and override
  convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
  "${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

  # Come back
  popd

  # Clone required repos
  clone_repos_from_env_vars "${IBM_HTTPS_BASE_URL}" "${WORKSPACE}" "${REPOS_TO_CLONE}"
fi

${PATH_TO_WORKSPACE_REPO}/scripts/1pl-bootstrap.sh
popd
