#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
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
export PIPELINE_TEMPLATE_TYPE="razee"

INITIAL_PIPELINE_TYPE="merge"
get_pipeline_type "${PIPELINE_RUN_BRANCH}" "${INITIAL_PIPELINE_TYPE}" "${REPO_MAIN_BRANCH}"

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

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="false"

if [[ $BASE_IMAGE_VERSION == "ubuntu22" ]]; then
    if check_yaml_path_has_data "images.multi_arch"; then
        ### Build ###
        run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "BUILD_S390X_IMAGES_UBUNTU22" ${EXIT_ON_TASK_FAILURE} \
        ${PATH_TO_GENCTL_CI}/onepipeline/scripts/build_s390x_images.sh "onepipeline/pipelines/templatized/razee/merge_dev_integration_v11_ubuntu22_and_24/.pipeline-config-subpipeline-s390x-artifacts-ubuntu22.yaml"
    else
        echo "There are no multi_arch images to build, so skipping..."
    fi
fi

if [[ $BASE_IMAGE_VERSION == "ubuntu24" ]]; then
    if check_yaml_path_has_data "images.multi_arch"; then
        ### Build ###
        run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "BUILD_S390X_IMAGES_UBUNTU24" ${EXIT_ON_TASK_FAILURE} \
        ${PATH_TO_GENCTL_CI}/onepipeline/scripts/build_s390x_images_ubuntu24.sh "onepipeline/pipelines/templatized/razee/merge_dev_integration_v11_ubuntu22_and_24/.pipeline-config-subpipeline-s390x-artifacts-ubuntu24.yaml"
    else
        echo "There are no multi_arch images to build, so skipping..."
    fi
fi