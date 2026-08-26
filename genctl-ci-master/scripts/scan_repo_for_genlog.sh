#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, SCAN_PATH, PATH_TO_WORKSPACE_REPO

# =============================================================================================

# Set flags
set -eu

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh
START=$(date +%s)

if [[ -d "${SCAN_PATH}/src" ]] ; then
    SCAN_PATH=${PATH_TO_WORKSPACE_REPO}/src
fi
    
echo "SCAN_PATH=${SCAN_PATH}"

${PATH_TO_GENCTL_CI}/scripts/repo_scanning_script_genlog.sh $SCAN_PATH --verbose
    
cat /tmp/scanning_result_verbose.txt

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Scan repo for genlog took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"