#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -o pipefail

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="false"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"
# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Configure ssh agent for git - used to do a git fetch on tags to get the most updated tags
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts

# Legacy third-party upload had the following flags:
export DO_NOT_OVERWRITE="true"
export FAIL_ON_IMAGE_PULL_FAILURE="true"

# Adding for extra check
export VERIFY_COPIED_IMAGES_CAN_BE_PULLED="true"

# Check the file got created and is not empty...
if [[ -s "${PATH_TO_IMAGES_TO_COPY}/final_image_list.txt" ]]
then
    echo "File with images list exists already; no need to create..."
else

    # Generate file with a list of images
    if [[ ! -z "${EXPLICIT_PATH_TO_THIRD_PARTY_IMAGES_YAML_FILE}" ]]
    then
        yq -r '.images[]' "${EXPLICIT_PATH_TO_THIRD_PARTY_IMAGES_YAML_FILE}" > "${PWD}/final_image_list.txt"
    else
        yq -r '.uploads[].images[]' "${PATH_TO_WORKSPACE_REPO}/third_party_uploads_config.yaml" > "${PWD}/final_image_list.txt"
    fi

    # Check the file got created and is not empty...
    if [[ ! -s "${PWD}/final_image_list.txt" ]]
    then
        echo "Image file does not exists or is empty"
        echo "Will exit with error..."
        exit 1
    fi

    echo "Succesfully generated a file ${PWD}/final_image_list.txt"
    echo "*******************************************************************************************"
    echo "*******************************************************************************************"

    # Set the variable needed for the copy images to understand we will use a file instead of build-meta or explicit list
    export PATH_TO_IMAGES_TO_COPY="${PWD}"
fi

#use dry run if needed here
#export COPY_IMAGES_DRY_RUN_MODE="true"

# Set parameters for push

#Use docker_local as a source for ICR push

export PULL_REGISTRY=${VPC_ICR_SANDBOX_URL}
export PULL_REGISTRY_API_KEY=${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}
export PULL_REGISTRY_USER=""
export PULL_REGISTRY_PASSWORD=""

export PUSH_REGISTRY=${IBMCLOUD_CR_URL_ONEPIPELINE}
export PUSH_REGISTRY_API_KEY=${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}
# Copy images script has a login function that "prefers" user and password over key login if present
# In order to be able to login to IBM Cloud for the push, we need to set them on empty
export PUSH_REGISTRY_USER=""
export PUSH_REGISTRY_PASSWORD=""

# Call copy images to ICR
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "LEGACY_THIRD_PARTY_UPLOAD_TO_ICR" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/copy_images.sh


export PUSH_REGISTRY=${ARTIFACTORY_DOCKER_URL}
export PUSH_REGISTRY_USER=${ARTIFACTORY_USER}
export PUSH_REGISTRY_PASSWORD=${CC_ARTIF_ACCESS_TOKEN}

# Call copy images to ICR
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "LEGACY_THIRD_PARTY_UPLOAD_TO_ARTIFACTORY" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

