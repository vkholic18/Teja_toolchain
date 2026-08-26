#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
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
convert_and_source_pipeline_params_and_overrides ${PATH_TO_GENCTL_CI} \
"${PIPELINE_REPO_NAME}" ${PIPELINE_TYPE}

# Come back
popd

# Define the repositories to be cloned
REPOS_TO_CLONE="RIAS_RELEASE GENESIS_DEPLOY_ARTIFACTS RIAS_GLOBALS RIAS_ETCD_GLOBALS GENCTL_GLOBALS"

clone_repos_from_env_vars "${IBM_HTTPS_BASE_URL}" "${WORKSPACE}" "${REPOS_TO_CLONE}"
