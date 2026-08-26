#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# The following script "retags" the dev-integration version with the SHA and SemVer tag of master

# This script is developed as a "replacement" of the build that we do in merge to master
# The reason for this is that the version that we build in master is technically the same code that we already built in merge to dev-integration
# Specifically when moving to OnePipeline, we want to avoid building in merge to master since that would require us to collect evidence twice
# In addition we could also use this script in Concourse as a replacement of the build we do in merge to master to save some time

# This logic works for retagging into the same registry, however we support running this against the different registries
# For this, we rely on checking which environment variables are present as it is done on the build process

# How does it actually works ?

# This script relies on the existing script of copy images
# This script is meant to be executed after AutoSemver ran succesfully
# What we want to do is

# 1) Identify the dev-integration version that has equivalent content to what we would build for master (This logic is actually done before right at the beginning of the pipeline)
# 2) Pull that version, and push it again but with new tags which are the SHA and SemVer tag of current master (This is done on copy images script)

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO, REPO_MAIN_BRANCH, SKIP_RETAG_AGAINST_ICR
# GIT_PRIVATE_KEY, VAULT_GIT_CONFIG_USER_EMAIL, VAULT_GIT_CONFIG_USERNAME

# In addition the following environment variables are optional: 
# RETAG_DEV_INT_TO_MASTER_DRY_RUN_MODE

# Default of dry run mode is false
export RETAG_DEV_INT_TO_MASTER_DRY_RUN_MODE=${RETAG_DEV_INT_TO_MASTER_DRY_RUN_MODE:-"false"}

# Move to the Workspace repo
#pushd "${PATH_TO_WORKSPACE_REPO}"

# Configuration needed for working with the remote (Needed before fetching tags)
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

# Source util for function
source ${PATH_TO_GENCTL_CI}/scripts/get_dev_int_version_equivalent_to_current_master.sh
source $PATH_TO_GENCTL_CI/scripts/retry.sh

# Check we have something in RESULT_DEV_INT_SHA, if not throw error as this is a pre-requisite for continue the logic
if [[ ! -z "${RESULT_DEV_INT_SHA}" ]]
then
    # Required to be in retag mode
    export COPY_IMAGES_RETAG_MODE="true"

    export RETAG_SHA_TO_PUSH=${RESULT_MASTER_SHA}
    export RETAG_SEMVER_TO_PUSH=${RESULT_MASTER_SEMVER}
    export RETAG_SHA_TO_PULL=${RESULT_DEV_INT_SHA}
    export RETAG_SEMVER_TO_PULL=${RESULT_DEV_INT_SEMVER}

    if [[ $RETAG_DEV_INT_TO_MASTER_DRY_RUN_MODE = true ]]; then
        echo "DRY RUN MODE !!! - No actual invokation to copy images will be performed..."
    else
        ## Handle third party ##

        # Define path to the third party images file to check if we need it
        third_party_images_yaml_file="${PATH_TO_WORKSPACE_REPO}/${THIRD_PARTY_IMAGES_YAML_FILE_PATH}"

        # First check if the file exists at all
        if [ -f "${third_party_images_yaml_file}" ]
        then
            echo "Found repository third party images file. Create a image list file with a 3d party images"
            # Source utils
            source ${PATH_TO_GENCTL_CI}/scripts/third_party_images/third_party_images_utils.sh

            # Create directory that will hold the file with the image list
            path_to_directory_for_image_list_file="${CI_TEMP_DIR}/retag_dev_int_to_master"
            mkdir ${path_to_directory_for_image_list_file}

            # Create a text file that has the images that we will retag
            create_images_file_for_retag_dev_int_to_master_third_party "${third_party_images_yaml_file}" "${PIPELINE_REPO_NAME}" \
            "${RETAG_SHA_TO_PULL}" "${RETAG_SEMVER_TO_PULL}" "${path_to_directory_for_image_list_file}/final_image_list.txt"

            # Check the file got created and is not empty...
            if [[ ! -s "${path_to_directory_for_image_list_file}/final_image_list.txt" ]]
            then
                echo "Image file does not exists or is empty"
                echo "Will exit with error..."
                exit 1
            fi
            echo "cat ${path_to_directory_for_image_list_file}/final_image_list.txt"
            cat ${path_to_directory_for_image_list_file}/final_image_list.txt
        else
            echo "No third party images file found..."
        fi

        # Set some required env vars for copy images
        export PULL_REGISTRY_USER=${ARTIFACTORY_USER}
        export PULL_REGISTRY_PASSWORD=${CC_ARTIF_ACCESS_TOKEN}
        # Since we will work within same registry, user and password are the same for pull/push
        export PUSH_REGISTRY_USER=${PULL_REGISTRY_USER}
        export PUSH_REGISTRY_PASSWORD=${PULL_REGISTRY_PASSWORD}

        # Artifactory prod
        if [[ ! -z ${ARTIFACTORY_DOCKER_URL} ]]; then
            
            export PULL_REGISTRY=${ARTIFACTORY_DOCKER_URL}
            export PUSH_REGISTRY=${PULL_REGISTRY}

            echo "*** Will perform retagging logic (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
            retry ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

            if [[ $? -eq 0 ]] ; then
                echo "*** Succesfully finished retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
            else
                echo "*** Something went wrong during retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                exit 1
            fi

            # Third party
            if [ -f "${third_party_images_yaml_file}" ]
            then
                echo "*** Will perform retagging logic (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) for third party images ***"
                
                export PATH_TO_IMAGES_TO_COPY="${path_to_directory_for_image_list_file}"
                retry ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

                if [[ $? -eq 0 ]] ; then
                    echo "*** Succesfully finished retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                else
                    echo "*** Something went wrong during retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                    exit 1
                fi

                # Set it as empty as preparation for next execution
                export PATH_TO_IMAGES_TO_COPY=""
            fi
        fi

        # Sandbox
        if [[ ! -z ${ARTIFACTORY_SANDBOX_DOCKER_URL} ]]; then
            
            export PULL_REGISTRY=${ARTIFACTORY_SANDBOX_DOCKER_URL}
            export PUSH_REGISTRY=${PULL_REGISTRY}
            
            echo "*** Will perform retagging logic (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
            retry ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

            if [[ $? -eq 0 ]] ; then
                echo "*** Succesfully finished retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
            else
                echo "*** Something went wrong during retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                exit 1
            fi

            # Third party
            if [ -f "${third_party_images_yaml_file}" ]
            then
                echo "*** Will perform retagging logic (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) for third party images ***"
                
                export PATH_TO_IMAGES_TO_COPY="${path_to_directory_for_image_list_file}"
                retry ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

                if [[ $? -eq 0 ]] ; then
                    echo "*** Succesfully finished retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                else
                    echo "*** Something went wrong during retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                    exit 1
                fi

                # Set it as empty as preparation for next execution
                export PATH_TO_IMAGES_TO_COPY=""
            fi
        fi
        
        # ICR
        if [[ "${SKIP_RETAG_AGAINST_ICR}" = "false" ]] 
        then
            if [[ ! -z ${IBMCLOUD_CR_URL_ONEPIPELINE} ]]; then
                
                # Pull from artifactory
                export PULL_REGISTRY=${ARTIFACTORY_DOCKER_URL}
                export PULL_REGISTRY_USER=${ARTIFACTORY_USER}
                export PULL_REGISTRY_PASSWORD=${CC_ARTIF_ACCESS_TOKEN}

                # Set parameters for push
                export PUSH_REGISTRY=${IBMCLOUD_CR_URL_ONEPIPELINE}
                export PUSH_REGISTRY_API_KEY=${IBMCLOUD_KEY_FOR_RETAG}

                # Copy images script has a login function that "prefers" user and password over key login if present
                # In order to be able to login to IBM Cloud for the push, we need to set them on empty
                export PUSH_REGISTRY_USER=""
                export PUSH_REGISTRY_PASSWORD=""

                if [[ ${ICR_MIGRATION_MODE} == true ]]
                then
                    echo "We are in ICR Migration mode, we WILL include manifests when working with ICR"
                else
                    # For ICR we don't want to deal with manifests
                    export COPY_IMAGES_SKIP_MANIFESTS="true"
                fi


                echo "*** Will perform retagging logic (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                retry ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

                if [[ $? -eq 0 ]] ; then
                    echo "*** Succesfully finished retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                else
                    echo "*** Something went wrong during retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                    exit 1
                fi

                # Third party
                if [ -f "${third_party_images_yaml_file}" ]
                then
                     echo "*** Will perform retagging logic (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) for third party images ***"

                    export PATH_TO_IMAGES_TO_COPY="${path_to_directory_for_image_list_file}"
                    retry ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

                    if [[ $? -eq 0 ]] ; then
                        echo "*** Succesfully finished retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                    else
                        echo "*** Something went wrong during retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                        exit 1
                    fi

                    # Set it as empty as preparation for next execution
                    export PATH_TO_IMAGES_TO_COPY=""
                fi
            fi
        else
            echo "No retag against ICR will be performed..."
        fi

        # ICR Sandbox
        
        if [[ ! -z ${VPC_ICR_SANDBOX_URL} ]]; then
            if [[ ${ICR_MIGRATION_MODE} == true ]]
            then
                # If we are in ICR Migration mode we can assume image is already in ICR Sandbox and therefore we can pull from there
                export PULL_REGISTRY=${VPC_ICR_SANDBOX_URL}
                export PULL_REGISTRY_API_KEY=${IBMCLOUD_KEY_FOR_RETAG}

                # Set parameters for push
                export PUSH_REGISTRY=${PULL_REGISTRY}
                export PUSH_REGISTRY_API_KEY=${PULL_REGISTRY_API_KEY}

                # Copy images script has a login function that "prefers" user and password over key login if present
                # In order to be able to login to IBM Cloud for the pull, we need to set them on empty
                export PULL_REGISTRY_USER=""
                export PULL_REGISTRY_PASSWORD=""

                # Copy images script has a login function that "prefers" user and password over key login if present
                # In order to be able to login to IBM Cloud for the push, we need to set them on empty
                export PUSH_REGISTRY_USER=""
                export PUSH_REGISTRY_PASSWORD=""

                echo "*** Will perform retagging logic (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                retry ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

                if [[ $? -eq 0 ]] ; then
                    echo "*** Succesfully finished retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                else
                    echo "*** Something went wrong during retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                    exit 1
                fi
                # Third party
                if [ -f "${third_party_images_yaml_file}" ]
                then
                    echo "*** Will perform retagging logic (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) for third party images ***"

                    export PATH_TO_IMAGES_TO_COPY="${path_to_directory_for_image_list_file}"
                    retry ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

                    if [[ $? -eq 0 ]] ; then
                        echo "*** Succesfully finished retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                    else
                        echo "*** Something went wrong during retag process (Pulling from ${PULL_REGISTRY} and pushing to ${PUSH_REGISTRY}) ***"
                        exit 1
                    fi

                    # Set it as empty as preparation for next execution
                    export PATH_TO_IMAGES_TO_COPY=""
                fi
            else
                echo "Nothing to do regarding sandbox ICR as we are NOT in ICR Migration mode"
            fi      
        fi
    fi
else
    echo "At this point, expected to have the equivalent dev-integ SHA on variable RESULT_DEV_INT_SHA, but is empty"
    echo "Will exit with error..."
    exit 1
fi