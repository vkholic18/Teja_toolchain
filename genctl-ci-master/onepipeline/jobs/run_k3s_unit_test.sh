#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"
START=$(date +%s)
if [[ $SKIP_K3S = true ]]; then
    echo "Skipping"
else
    cd ${WORKSPACE}


    echo ${STORAGE_FYRE_KEY} | md5sum
    ln -s ${PATH_TO_WORKSPACE_REPO} workspace-repo

    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "${K3S_RUN_CHECK_LABEL}" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_WORKSPACE_REPO}/hack/ci/run-functional-tests.sh
fi
END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Functional tests took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"