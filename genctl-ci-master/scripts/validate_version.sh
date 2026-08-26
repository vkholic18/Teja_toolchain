#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, WORKSPACE_PATH, VERSION_FILE_PATH

# =============================================================================================

# Set flags
set -eu
# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh
START=$(date +%s)
echo "WORKSPACE_PATH=${WORKSPACE_PATH}"
echo "VERSION_FILE_PATH=${VERSION_FILE_PATH}"


python3 ${PATH_TO_GENCTL_CI}/tools/versioning/component_version.py ${WORKSPACE_PATH}/${VERSION_FILE_PATH}

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Validate version file took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"