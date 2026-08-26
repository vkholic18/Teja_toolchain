#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script merges a PR

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI
# GHE_API_TOKEN, GHE_API_URL
# REPOSITORY_NAME
# PR_NUMBER, PR_SHA

# Optional variables supported

# MERGE_METHOD, APPROVE_BEFORE_MERGE

# This script also implements skipping logic through: SKIP_AUTO_MERGE

# =============================================================================================

# Set flags
set -u

# Source tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Skip if needed
generic_skip $SKIP_AUTO_MERGE

# Execute
generic_python_execution ${PATH_TO_GENCTL_CI}/scripts/merge_pr ${PATH_TO_GENCTL_CI}/scripts/retry.sh
