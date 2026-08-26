# !/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI,WORKSPACE_PATH

# =============================================================================================
set -eu

: "${PATH_TO_GENCTL_CI:="./genctl-ci-repo"}"
: "${WORKSPACE_PATH:="./workspace-repo"}"

# Source tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

START=$(date +%s)
find ${WORKSPACE_PATH}/hack/deploy/razee -name "*.yaml" >> file_list

#Install tools
python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/razee_check_duplicate_keys/requirements.txt

#Execute
generic_python_execution ${PATH_TO_GENCTL_CI}/scripts/razee_check_duplicate_keys ${PATH_TO_GENCTL_CI}/scripts/retry.sh --list=file_list

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Check duplicate keys in mustache templates took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"