#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="simple"

export PIPELINE_TYPE="pr"

get_pipeline_type "${PR_BASEBRANCH}" "${INITIAL_PIPELINE_TYPE}" "${REPO_MAIN_BRANCH}"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}" 

# Come back
popd

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="false"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# ${finish_evaluate_exit_code} is a OnePipeline variable that should be 0 if all the previous stages passed
if [[ ${SIMPLE_AUTO_MERGE} == true && ${finish_evaluate_exit_code} -eq 0 ]]
then
	### Auto-merge ### (Since is only one task no need for job)
	run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "AUTO_MERGE" ${EXIT_ON_TASK_FAILURE} \
	${PATH_TO_GENCTL_CI}/scripts/merge_pr/merge_pr.sh
else
	echo "Won't do auto-merge"
fi

if [[ ${SIMPLE_CUSTOM_FINISH} == true ]] && [ -f "${PATH_TO_WORKSPACE_REPO}/hack/ci/custom_finish.sh" ]
then
    ### Run custom script after automerge, used for tagging the commit
    echo "Running custom_finish.sh from the hack/ci directory"
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "CUSTOM_FINISH" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_WORKSPACE_REPO}/hack/ci/custom_finish.sh
else
    echo "No custom script set up"
fi

# Call regular finish process of OnePipeline    
"/opt/commons/custom-finish/finish.sh"