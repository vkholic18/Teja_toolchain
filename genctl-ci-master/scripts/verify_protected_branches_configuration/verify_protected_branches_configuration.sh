#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script verifies that the protected branches (Or a specific branch) is properly configured according to the Razee/MASCD conventional commit enforcement flow

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, VERIFY_PROTECTED_BRANCHES_GHE_API_TOKEN, GHE_API_URL, REPOSITORY_NAME, MAIN_BRANCH_NAME, WORKSPACE_PIPELINES_STATUS

# In addition the following environment variables are optional: 
# EXPECTED_CONFIG_FILE_PATH
# SPECIFIC_BRANCH_TO_CHECK
# DEV_INTEG_SUFFIX

# This script also implements skipping logic through: SKIP_CONVENTIONAL_COMMIT_ENFORCEMENT

# =============================================================================================

# Set flags
set -e

# Source tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Skip if needed
generic_skip $SKIP_CONVENTIONAL_COMMIT_ENFORCEMENT

# Set the path to the verify protected branches configuration directory (Relative from current location) for readability
VERIFY_PROTECTED_BRANCHES_CONFIG_DIR="${PATH_TO_GENCTL_CI}/scripts/verify_protected_branches_configuration"

# Set value for expected config path
export EXPECTED_CONFIG_FILE_PATH=${EXPECTED_CONFIG_FILE_PATH:-"${VERIFY_PROTECTED_BRANCHES_CONFIG_DIR}/expected_config_${WORKSPACE_PIPELINES_STATUS}.json"}

# Support dev-integ suffix
if [ ! -z "$DEV_INTEG_SUFFIX" ]
then
    sed -i "0,/dev-integration/{s//dev-integration${DEV_INTEG_SUFFIX}/}" ${EXPECTED_CONFIG_FILE_PATH}
fi    

# Replace main branch name

# Replace to support "alternative" branch names that represent the main branch (We keep master in the expected)
# For example: workspaces that use "main" instead of "master"
sed -i "0,/master/{s//${MAIN_BRANCH_NAME}/}" ${EXPECTED_CONFIG_FILE_PATH}

# Install ci python tools
python3 -m pip install -q ${PATH_TO_GENCTL_CI}/tools/ci_python_tools

# Execute
generic_python_execution ${PATH_TO_GENCTL_CI}/scripts/verify_protected_branches_configuration ${PATH_TO_GENCTL_CI}/scripts/retry.sh
