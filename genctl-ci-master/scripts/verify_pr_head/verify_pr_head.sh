#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script verifies that the head of the PR comes from a specific organization, repo and branch

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI
# GHE_API_TOKEN, GHE_API_URL
# REPOSITORY_NAME
# EXPECTED_PR_HEAD_ORG_AND_REPO, EXPECTED_PR_HEAD_BRANCH, VERIFY_PR_HEAD_PARTIAL_MATCH
# PR_NUMBER

# This script also implements skipping logic through: SKIP_VERIFY_PR_HEAD

# =============================================================================================

# Set flags
set -u

# Source tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

START=$(date +%s)

# Skip if needed
generic_skip $SKIP_VERIFY_PR_HEAD

# Execute
generic_python_execution ${PATH_TO_GENCTL_CI}/scripts/verify_pr_head ${PATH_TO_GENCTL_CI}/scripts/retry.sh

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Verify PR head took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"