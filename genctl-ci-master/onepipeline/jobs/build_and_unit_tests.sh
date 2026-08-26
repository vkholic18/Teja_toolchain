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
EXIT_ON_TASK_FAILURE_UNIT_TESTS_AND_COVERAGE="false"
EXIT_ON_TASK_FAILURE_BUILD="true"

# In some flows we want to skip unit tests so check 
if [[ $SKIP_UNIT_TESTS = true ]]; then
    echo "Skipping unit tests"
else
    ## Unit tests ##
    cd ${WORKSPACE}
    mkdir coverage
    ln -s ${PATH_TO_WORKSPACE_REPO} workspace-repo
    echo -e "${BYellow}Unit Tests starts at: $(date)............. ${NC}"
    START=$(date +%s)
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "UNIT_TEST" ${EXIT_ON_TASK_FAILURE_UNIT_TESTS_AND_COVERAGE} \
    ${PATH_TO_WORKSPACE_REPO}/hack/ci/run-unit-tests.sh
    END=$(date +%s)
    DIFF=$(( $END - $START ))
    echo -e "${BYellow}Unit Tests ends at: $(date)............. ${NC}"
    echo -e "${BYellow}Unit Tests took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete............. ${NC}"

    echo "RUN_TASK_RESULT for UNIT_TEST" ${RUN_TASK_RESULT}
    if [[ ${RUN_TASK_RESULT} == "FAILED" ]]; then
        #update evidence for unit tests
        collect_evidence "unittest" "failure" "com.ibm.unit_tests" "repo" "app-repo"
        echo -e "${BRed}Exiting UNIT_TEST with failure ......................................................... ${NC}"
        exit 1
    fi

    ## Code coverage ##
    cd ${WORKSPACE}
    mkdir -p output

    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "CODE_COVERAGE" ${EXIT_ON_TASK_FAILURE_UNIT_TESTS_AND_COVERAGE} \
    ${PATH_TO_GENCTL_CI}/scripts/code-coverage.sh ${PATH_TO_WORKSPACE_REPO} coverage output

    if [[ ${RUN_TASK_RESULT} == "FAILED" ]]; then
        collect_evidence "unittest" "failure" "com.ibm.unit_tests" "repo" "app-repo"
        echo -e "${BRed}Exiting CODE_COVERAGE with failure ......................................................... ${NC}"
        exit 1
    else
        collect_evidence "unittest" "success" "com.ibm.unit_tests" "repo" "app-repo"
    fi


fi

# In some flows we want to skip the build itself, so check 
if [[ $SKIP_BUILD = true ]]; then
    echo "Skipping build..."
else
    ## Build ##
    ln -s ${PATH_TO_WORKSPACE_REPO} workspace-repo # TODO: Shouldn't be needed but currently is due to how build.sh is written
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "BUILD" ${EXIT_ON_TASK_FAILURE_BUILD} \
    ${PATH_TO_GENCTL_CI}/tasks/pipeline/generic-workspace-build.sh
fi
