#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

function run_job(){
    # This function runs a "job"
    # It adds some printing before and after the job execution
    # In addition, it allows to exit 1 (Or not) after job failure, according to a flag
    
    # Expected parameters:

    # $1 --> The name of the job
    # $2 --> A boolean indicating if exit 1 when the job failed
    # $3 --> The path to the job (Should be an .SH file with proper permissions)

    # Put some friendly names
    JOB_NAME=$1
    EOJF=$2
    PATH_TO_JOB=$3

    echo -e "${BGreen}Job ${JOB_NAME} started ...................................................................... ${NC}"    
    ${PATH_TO_JOB} "${@:4}"
    if [[ $? -ne 0 ]] ; then
        echo -e "${BRed}Finished job ${JOB_NAME} with failure ......................................................... ${NC}"
        if [[ $EOJF = true ]]; then
            exit 1
        else
            echo -e "${BYellow}Job ${JOB_NAME} failed but since the flag of exit on job failure is not true, will continue execution"
        fi
    else
        echo -e "${BGreen}Finished Job ${JOB_NAME} succesfully ...................................................................... ${NC}"
    fi
}
function run_task(){
    # This function runs a "task"
    # It adds some printing before and after the job execution
    # In addition, it allows to exit 1 (Or not) after task failure, according to a flag
    # In addition, it allows to add (Or not) GHE status of pending/success/failure according to a flag
    
    # Expected parameters:

    # $1 --> A boolean indicating if set (Or not) GHE statuses
    # $2 --> The prefix of the task (Used for GHE statuses)
    # $3 --> The name of the task (Used for printing and GHE statuses)
    # $4 --> A boolean indicating if exit 1 when the task failed
    # $5 --> The path to the task (Should be an .SH file with proper permissions)

    # Put some friendly names
    SET_GHE_STATUSES=$1
    TASK_CHECK_PREFIX=$2
    TASK_CHECK_STR=$3
    EOTF=$4
    PATH_TO_TASK=$5

    # Additional validation for PATH_TO_TASK
    # This verifies that we have something in PATH_TO_TASK that is not empty
    if [ -z "${PATH_TO_TASK// }" ];
    then
        echo "Missing PATH_TO_TASK"
        echo "Will exit with error..."
        exit 1
    fi

    # Concatenate the prefix and the actual check
    FULL_CHECK_STR="${TASK_CHECK_PREFIX}/${TASK_CHECK_STR}"
    FINISHED_RUNNING="${TASK_CHECK_STR} finished running."
    
    if [[ $SET_GHE_STATUSES = true ]] ; then
        # Set to pending
        set_ghe_commit_status "pending" "${TASK_CHECK_STR} starts to run." "${FULL_CHECK_STR}"
    fi

    echo -e "${BGreen}${TASK_CHECK_STR} started ...................................................................... ${NC}"
    echo "Exit task on failure is ${EOTF}"
    echo "Will try to run ${PATH_TO_TASK}"
    ${PATH_TO_TASK} "${@:6}"
    if [[ $? -ne 0 ]] ; then
        export RUN_TASK_RESULT="FAILED"
        echo -e "${BRed}Exiting ${TASK_CHECK_STR} with failure ......................................................... ${NC}"
        if [[ $SET_GHE_STATUSES = true ]] ; then
            set_ghe_commit_status "failure" "${FINISHED_RUNNING}" "${FULL_CHECK_STR}"
        fi
        if [[ $EOTF = true ]]; then
            exit 1
        else
            echo -e "${BYellow}${TASK_CHECK_STR} failed but since the flag of exit task on failure is not true, will continue execution ${NC}"
        fi
    else
        export RUN_TASK_RESULT="PASSED"
        echo -e "${BGreen}${TASK_CHECK_STR} succeeded ...................................................................... ${NC}"
        if [[ $SET_GHE_STATUSES = true ]] ; then
            set_ghe_commit_status "success" "${FINISHED_RUNNING}" "${FULL_CHECK_STR}"
        fi
    fi
}

function run_task_alternative(){
    # This function is a slightly different implementation of "running a task" that suit in some cases (Ex: BRT)

    # The main differences with the regular run_task function are:
    # 1. It does not set GHE status for pending or success, only for failure (We rely on the pending and success being managed outside)
    # 2. It supports different strings for the GHE check and for the printing to the output


    # Expected parameters:

    # $1 --> A boolean indicating if set (Or not) GHE statuses
    # $2 --> The prefix of the task (Used for GHE statuses)
    # $3 --> The name of the task (Used for printing and GHE statuses)
    # $4 --> A boolean indicating if exit 1 when the task failed
    # $5 --> The path to the task (Should be an .SH file with proper permissions)

    # Put some friendly names
    SET_GHE_STATUSES=$1
    GHE_CHECK_PREFIX=$2
    GHE_CHECK_NAME=$3
    TASK_NAME=$4
    EXIT_ON_TASK_FAILURE=$5
    PATH_TO_TASK=$6

    # Concatenate the prefix and the actual check
    FULL_CHECK_STR="${GHE_CHECK_PREFIX}/${GHE_CHECK_NAME}"
    FINISHED_RUNNING="${GHE_CHECK_NAME} finished running."

    echo -e "${BGreen}${TASK_NAME} started ...................................................................... ${NC}"
    echo "Exit task on failure is ${EXIT_ON_TASK_FAILURE}"
    echo "Will try to run ${PATH_TO_TASK}"
    ${PATH_TO_TASK} "${@:7}"
    if [[ $? -ne 0 ]] ; then
        echo -e "${BRed}Exiting ${TASK_NAME} with failure ......................................................... ${NC}"
        if [[ $SET_GHE_STATUSES = true ]] ; then
            set_ghe_commit_status "failure" "${FINISHED_RUNNING}" "${FULL_CHECK_STR}"
        fi
        if [[ $EXIT_ON_TASK_FAILURE = true ]]; then
            exit 1
        else
            echo -e "${BYellow}${TASK_NAME} failed but since the flag of exit task on failure is not true, will continue execution"
        fi
    else
        echo -e "${BGreen}${TASK_NAME} succeeded ...................................................................... ${NC}"
    fi
}

function run_hook(){
    # This function runs a hook
    # It executes any custom scripts if relevant setting exists in pipeline.yaml 

    # Expected parameters:

    # $1 --> The prefix of the hook (Used for GHE statuses)
    # $2 --> The type of the pipeline running, either "pr" or "ci"
    # $3 --> The Path to the workspace repos
    # $4 --> A boolean indicating if exit 1 when the hook failed
    # $5 --> A boolean indicating if set (Or not) GHE statuses

    GHE_CHECK_PREFIX=$1
    PIPELINE_NAMESPACE=$2
    PATH_TO_WORKSPACE_REPO=$3
    EXIT_ON_TASK_FAILURE=$4
    SET_GHE_STATUSES=$5


    if [[ -f "${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml" ]] && \
    yq -e '.ci_hook' "${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml" &> /dev/null && \
    yq -e ".ci_hook.run_in | select(. | contains([\"${PIPELINE_NAMESPACE}\"]))" "${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml" &> /dev/null; then
        echo "Found a CI HOOK, will try to exec"
        export NAME=$(yq -r '.ci_hook.name | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
        YAML_TASK_FAILURE=$(yq -r '.ci_hook.parameters.EXIT_ON_TASK_FAILURE // ""' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
        YAML_GHE_STATUSES=$(yq -r '.ci_hook.parameters.SET_GHE_STATUSES // ""' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
        export EXIT_ON_TASK_FAILURE="${YAML_TASK_FAILURE:-${EXIT_ON_TASK_FAILURE}}"
        export SET_GHE_STATUSES="${YAML_GHE_STATUSES:-${SET_GHE_STATUSES}}"
        run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "RUN_CUSTOM_HOOK - ${NAME}" ${EXIT_ON_TASK_FAILURE} \
        ${PATH_TO_GENCTL_CI}/onepipeline/scripts/run_custom_hook.sh
    fi
}