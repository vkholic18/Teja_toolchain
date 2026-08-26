#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2024
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# Source util for function
source $PATH_TO_GENCTL_CI/tools/ci_bash_tools/tools.sh

# Source util for function
source $PATH_TO_GENCTL_CI/scripts/retry.sh

# This is to ensure we don't use retag mode here as this is regular copy images process
export COPY_IMAGES_RETAG_MODE="false"

# The following script does a backup by copying between two different ICR regions

# Set parameters for pull
export PULL_REGISTRY=${IBMCLOUD_CR_URL_ONEPIPELINE}
export PULL_REGISTRY_USER=""
export PULL_REGISTRY_PASSWORD=""
export PULL_REGISTRY_API_KEY=${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}
export ICR_PULL_REGISTRY_REGION="us-south"

# Set parameters for push
export PUSH_REGISTRY=${IBMCLOUD_CR_URL_ONEPIPELINE_BACKUP} 
export PUSH_REGISTRY_USER=""
export PUSH_REGISTRY_PASSWORD=""
export PUSH_REGISTRY_API_KEY=${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}
export ICR_PUSH_REGISTRY_REGION="eu-gb"

# Special logic for low level release bundles
export ICR_BACKUP_RELEASE_BUNDLES_MODE=${ICR_BACKUP_RELEASE_BUNDLES_MODE:-"false"}

# First check if we are in non standard naming images mode; if yes, prefer that logic over the build-meta one
if [ "$(ls -A ${CI_NON_STANDARD_NAMING_IMAGES_DIR})" ]
then
    # Create directory that will hold the file with the image list
    path_to_directory_for_image_list_file="${CI_TEMP_DIR}/for_icr_backup"
    mkdir ${path_to_directory_for_image_list_file}

    # Move to the directory
    pushd "${CI_NON_STANDARD_NAMING_IMAGES_DIR}"

    # Iterate and save artifacts (Though we support only one file, set infra for in case in the future we want to support multiple)
    for image_to_backup in *
    do 
        img_to_backup_full_name=$(cat ${image_to_backup})

        # We want to backup to ICR only images from ICR
        if [[ $img_to_backup_full_name =~ ".icr." ]]
        then
            if [[ "${ICR_BACKUP_RELEASE_BUNDLES_MODE}" == "true" ]]
            then
                # Here we can safely use IBMCLOUD_CR_URL_ONEPIPELINE because for release bundles; in merge we always push to us.icr.io/genctl-cicd-onepipeline
                img_in_format_for_final_image_list=${img_to_backup_full_name#"${IBMCLOUD_CR_URL_ONEPIPELINE}/"}
            else
                img_in_format_for_final_image_list=${img_to_backup_full_name}
            fi
            
            echo "${img_in_format_for_final_image_list}" >> "${path_to_directory_for_image_list_file}/final_image_list.txt"
        fi
    done

    # Come back
    popd

    # Export environment variable
    export PATH_TO_IMAGES_TO_COPY="${path_to_directory_for_image_list_file}"
else
    # If we are not in the non standard images flow; then we assume we go with the build-meta.yaml
    if [[ -f "${PATH_TO_WORKSPACE_REPO}/hack/ci/build-meta.yaml" ]]
    then
        # Check if we have at least one image in build-meta in any of the architectures
        repo_has_images_in_build_meta "${PATH_TO_WORKSPACE_REPO}/hack/ci/build-meta.yaml"
        if [[ "${RESULT_CHECK_IF_REPO_HAS_IMAGES}" == "true" ]]
        then
            echo "Found at least one image in build-meta; will proceed to ICR backup..."
        else
            echo "Could not find any images defined in build-meta.yaml file"
            echo "Won't do ICR backup"
            exit 0
        fi
    else
        echo "Could not find build-meta.yaml file"
        echo "Won't do ICR backup"
        exit 0
    fi
fi

echo "*** Will perform backup (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
retry ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

if [[ $? -eq 0 ]] ; then
    echo "*** Succesfully finished backup process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
else
    echo "*** Something went wrong during backup process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
    exit 1
fi

## Handle third party ##

# Configuration needed for working with the remote (Needed before fetching tags)
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

# Get SHA and SemVer
pushd "${PATH_TO_WORKSPACE_REPO}"
SHA=$(git rev-parse --verify HEAD)
SEMVER=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true
popd

# Define path to the third party images file to check if we need it
third_party_images_yaml_file="${PATH_TO_WORKSPACE_REPO}/${THIRD_PARTY_IMAGES_YAML_FILE_PATH}"

# First check if the file exists at all
if [ -f "${third_party_images_yaml_file}" ]
then
    # Source utils
    source ${PATH_TO_GENCTL_CI}/scripts/third_party_images/third_party_images_utils.sh

    # Create directory that will hold the file with the image list
    path_to_directory_for_image_list_file="${CI_TEMP_DIR}/icr_backup"
    mkdir ${path_to_directory_for_image_list_file}

    # Create a text file that has the images that we will retag
    create_images_file_for_icr_backup_third_party "${third_party_images_yaml_file}" "${PIPELINE_REPO_NAME}" \
    "${SHA}" "${SEMVER}" "${path_to_directory_for_image_list_file}/final_image_list.txt"

    # Check the file got created and is not empty...
    if [[ ! -s "${path_to_directory_for_image_list_file}/final_image_list.txt" ]]
    then
        echo "Image file does not exists or is empty"
        echo "Will exit with error..."
        exit 1
    fi

    echo "*** Will perform backup logic (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) for third party images ***"

    export PATH_TO_IMAGES_TO_COPY="${path_to_directory_for_image_list_file}"
    retry ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

    if [[ $? -eq 0 ]] ; then
        echo "*** Succesfully finished backup process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
    else
        echo "*** Something went wrong during backup process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
        exit 1
    fi

    # Set it as empty as preparation for next execution
    export PATH_TO_IMAGES_TO_COPY=""
else
    echo "No third party images file found..."
fi