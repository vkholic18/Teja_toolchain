#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO

# This script also implements skipping logic through: SKIP_VALIDATE_REMOTE_RESOURCE

# =============================================================================================

# Set flags
set -eu

# Source tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

START=$(date +%s)
# Skip if needed
generic_skip $SKIP_VALIDATE_REMOTE_RESOURCE

# Execute
generic_python_execution ${PATH_TO_GENCTL_CI}/scripts/validate_remote_resource ${PATH_TO_GENCTL_CI}/scripts/retry.sh --workspaceRazeeDir=${PATH_TO_WORKSPACE_REPO}/hack/deploy/razee/

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Validate Razee remote resource took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"