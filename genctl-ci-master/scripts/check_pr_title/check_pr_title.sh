#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
set -eu

# The following environment variables need to be set before executing this script:
# PATH_TO_GENCTL_CI, WORKSPACE_ROOT, TOKEN, IBM_GITHUB_API_URI_BASE, PR_NUMBER, WORKSPACE_ORG, WORKSPACE_REPO

# Source tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# This script also implements skipping logic through: SKIP_CHECK_PR_TITLE
START=$(date +%s)
set +u
generic_skip ${SKIP_CHECK_PR_TITLE}
set -u

${PATH_TO_GENCTL_CI}/scripts/check_pr_title/check_pr_title.py -w ${WORKSPACE_ROOT} -t ${TOKEN} -a ${IBM_GITHUB_API_URI_BASE} -p ${PR_NUMBER} -o ${WORKSPACE_ORG} -r ${WORKSPACE_REPO}

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Check PR title and commits took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"