#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================


# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI,WORKSPACE_PATH

# This script also implements skipping logic through: SKIP_LABEL_VALIDATION

# =============================================================================================

# Set flags
set -e

# Source tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

START=$(date +%s)
# Skip if needed
generic_skip $SKIP_LABEL_VALIDATION

# Install requirements (Use retry mechanism)
source ${PATH_TO_GENCTL_CI}/scripts/retry.sh
retry python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/git_meta_label_injector/requirements.txt

# Execute script
python3 ${PATH_TO_GENCTL_CI}/scripts/git_meta_label_injector/validate_deployment_labels.py

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Validate required deployment labels took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"