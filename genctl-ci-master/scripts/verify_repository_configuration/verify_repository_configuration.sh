#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script verifies that a repository is properly configured according to the Razee/MASCD conventional commit enforcement flow

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, GHE_API_TOKEN, GHE_API_URL, REPOSITORY_NAME

# In addition the following environment variables are optional: 
# EXPECTED_CONFIG_FILE_PATH

# This script also implements skipping logic through: SKIP_CONVENTIONAL_COMMIT_ENFORCEMENT

# =============================================================================================

# Set flags
set -e

# Source tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Skip if needed
generic_skip $SKIP_CONVENTIONAL_COMMIT_ENFORCEMENT

# Execute
generic_python_execution ${PATH_TO_GENCTL_CI}/scripts/verify_repository_configuration ${PATH_TO_GENCTL_CI}/scripts/retry.sh
