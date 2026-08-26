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
export PIPELINE_TEMPLATE_TYPE="uuc-ci"

# Set the pipeline template type
export PIPELINE_TYPE="pr"

REPOS_TO_CLONE="
CI_CD_UTILS
"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Clone required repos
clone_repos_from_env_vars "${IBM_HTTPS_BASE_URL}" "${WORKSPACE}" "${REPOS_TO_CLONE}"

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

#check if build-meta.yaml is empty
check_yaml_file_is_empty

#check if hack/ci/build-meta.yaml is empty
if [[ "$BUILD_META_YAML_IS_EMPTY" == "false" ]]; then
    #if it's not empty you process the BUILD_ARTIFACT_TYPE
    if [[ $BUILD_ARTIFACT_TYPE == "images" ]]; then
        if check_yaml_path_has_data "images.amd64" || check_yaml_path_has_data "images.multi_arch" || check_yaml_path_has_data "images.no_arch"; then
            run_job "BUILD" ${EXIT_ON_JOB_FAILURE} \
            ${PATH_TO_GENCTL_CI}/onepipeline/jobs/build_v11.sh "BUILD_AMD64_IMAGES"
        else
            echo "There are no amd64/multi_arch images to build, so skipping..."
        fi
    fi

else
    #if it's empty, it means its custom building mechanism
    echo "Proceed with custom building mechanism"

    # Run the job to validate the images in the third party images file
    run_job "VALIDATE_THIRD_PARTY_IMAGES_WITH_MAPPING_FILE" ${EXIT_ON_JOB_FAILURE} \
    ${PATH_TO_GENCTL_CI}/onepipeline/jobs/validate_component_images_in_third_party_images.sh

    # Run the job to mirror the OCP release
    run_job "MIRROR_OCP_RELEASE" ${EXIT_ON_JOB_FAILURE} \
    ${PATH_TO_GENCTL_CI}/onepipeline/jobs/mirror_ocp_release.sh
fi
