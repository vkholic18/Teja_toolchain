#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, WORKSPACE_PATH
# REPOSITORY_NAME
# GHE_API_URL, GITHUB_ACCESS_TOKEN
# SKIP_LABEL_VALIDATION
# BASE_WORKSPACE_DIR, SECRET_DIR, LABEL_TO_SEARCH

# =============================================================================================
set -u

# Source tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh
START=$(date +%s)
# Skip if needed
generic_skip $SKIP_LABEL_VALIDATION

export PR_HEAD=$(cd ${WORKSPACE_PATH} && git rev-parse HEAD)

# Install ci python tools
python3 -m pip install -q ${PATH_TO_GENCTL_CI}/tools/ci_python_tools


# Execute
generic_python_execution ${PATH_TO_GENCTL_CI}/scripts/check_secrets_label ${PATH_TO_GENCTL_CI}/scripts/retry.sh

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Check secrets label took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"