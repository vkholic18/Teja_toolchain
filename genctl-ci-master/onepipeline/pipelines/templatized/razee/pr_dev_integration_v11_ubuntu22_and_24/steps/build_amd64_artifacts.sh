#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
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

if [ "$#" -ne 1 ]; then
    echo "ERROR: ${FUNCNAME[0]} requires 1 argument but got $#. Please pass in the correct arguments."
    exit 1
else
    GITHUB_CUSTOM_CHECK_NAME=$1
fi
# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="razee"

INITIAL_PIPELINE_TYPE="pr"
get_pipeline_type "${PR_BASEBRANCH}" "${INITIAL_PIPELINE_TYPE}" "${REPO_MAIN_BRANCH}"

# Basic logging info
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/basic_logging_info.sh

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

# Set the SSH
eval "$(ssh-agent -s)" # Check if needed here
ssh-add - <<< "${GIT_PRIVATE_KEY}" # Check if needed here

# Note: Here we use a mix of jobs and tasks, therefore we configure both flags

# Set the flag that indicates if exit when a job fails
export EXIT_ON_JOB_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

if [[ $BUILD_ARTIFACT_TYPE == "images" ]]; then
    if check_yaml_path_has_data "images.amd64" || check_yaml_path_has_data "images.multi_arch"; then
        run_job "BUILD" ${EXIT_ON_JOB_FAILURE} \
        ${PATH_TO_GENCTL_CI}/onepipeline/jobs/build_v11.sh ${GITHUB_CUSTOM_CHECK_NAME}
    else
        echo "There are no amd64/multi_arch images to build, so skipping..."
    fi
fi

if [[ $BUILD_ARTIFACT_TYPE == "packages" ]]; then
    if has_non_s390x_packages_data; then
        run_job "BUILD" ${EXIT_ON_JOB_FAILURE} \
        ${PATH_TO_GENCTL_CI}/onepipeline/jobs/build_v11.sh ${GITHUB_CUSTOM_CHECK_NAME}
    else
        echo "There are no amd64/arm64/noarch packages to build, so skipping..."
    fi
fi
