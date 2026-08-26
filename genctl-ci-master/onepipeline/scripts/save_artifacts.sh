#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# The following environment variables need to be set before executing the script:

# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO
# CC_ARTIF_ACCESS_TOKEN (Used both for images and packages)

# The following environment variables need to be set if there are images to process
# ARTIFACTORY_DOCKER_URL WCP_ARTIFACTORY_USERNAME

# The following environment variables need to be set if there are packages to process (Used in process_build_meta_packages_new.sh)
# ARTIFACTORY_DEBIAN_SANDBOX_REPO_PATH, ARTIFACTORY_GOLANG_BINARIES_SANDBOX_REPO_PATH
# PACKAGES_PRE_RELEASE_DIR, PACKAGES_FINAL_LOCATION_DIR 

SKIP_SAVE_ARTIFACTS=${SKIP_SAVE_ARTIFACTS:-"false"} # By default we DO want to save artifacts
SAVE_ARTIFACTS_SKIP_IMAGES=${SAVE_ARTIFACTS_SKIP_IMAGES:-"false"} # By default we DO want to save artifacts for images
SAVE_ARTIFACTS_SKIP_PACKAGES=${SAVE_ARTIFACTS_SKIP_PACKAGES:-"false"} # By default we DO want to save artifacts for packages

SAVE_ARTIFACTS_ONLY_FIRST_IMAGE_MODE=${SAVE_ARTIFACTS_ONLY_FIRST_IMAGE_MODE:-"false"} # By default we DON'T do the mode of saving only the first artifact

SAVE_ARTIFACTS_FAIL_IF_NO_MANIFEST=${SAVE_ARTIFACTS_FAIL_IF_NO_MANIFEST:-"false"} # By default we DON'T fail if there is no manifest

# Source tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh 
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/save_artifacts_utils.sh

# Skip if needed
generic_skip $SKIP_SAVE_ARTIFACTS

# First check if we are in non standard naming images mode; if yes, prefer that logic over the build-meta one
if [ "$(ls -A ${CI_NON_STANDARD_NAMING_IMAGES_DIR})" ]
then
    ${PATH_TO_GENCTL_CI}/onepipeline/scripts/save_artifacts_non_standard_naming_images.sh
else
    echo "Will parse build-meta.yaml for saving artifacts..."

    # Set the path to the build-meta.yaml file for easier use
    PATH_TO_BUILD_META="${PATH_TO_WORKSPACE_REPO}/hack/ci/build-meta.yaml"

    # Check build-meta.yaml file exists
    if [ -f "${PATH_TO_BUILD_META}" ]
    then
        # Get the SHA
        pushd ${PATH_TO_WORKSPACE_REPO}
        GIT_SHA_FOR_SAVE_ARTIFACTS=$(git rev-parse --verify HEAD)
        popd

        if [[ "${SAVE_ARTIFACTS_SKIP_IMAGES}" == "true" ]]
        then
            echo "Skipping saving artifacts for images"
        else
            # Check if we have images
            images=$(yq -r '.images ' "${PATH_TO_BUILD_META}")

            if [[ ! ${images} == null ]]; then
                
                # Delete all the local images, this is in order to force an actual pull from the remote registry
                echo "Will proceed to delete all local docker images in order to force actual pull"
                echo "These are the current existing local images"
                docker images
                echo "*******************************************************************************************"
                docker rmi -f $(docker images -a -q) || echo "Found no local images"
                echo "After deletion, these are the current existing local images"
                docker images

                # Login to artifactory
                orig_opts=$-
                set +x
                echo "Logging into ${ARTIFACTORY_DOCKER_URL}"
                echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_URL} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
                set -${orig_opts}

                # Call function that saves artifacts
                save_artifacts_images "${PATH_TO_BUILD_META}" \
                "${ARTIFACTORY_DOCKER_URL}" "${GIT_SHA_FOR_SAVE_ARTIFACTS}" \
                "${SAVE_ARTIFACTS_ONLY_FIRST_IMAGE_MODE}" " " "${SAVE_ARTIFACTS_FAIL_IF_NO_MANIFEST}"

                if [[ ${ICR_MIGRATION_MODE} == true ]]
                then
                    # Delete all the local images, this is in order to force an actual pull from the remote registry
                    echo "Will proceed to delete all local docker images in order to force actual pull"
                    echo "These are the current existing local images"
                    docker images
                    echo "*******************************************************************************************"
                    docker rmi -f $(docker images -a -q) || echo "Found no local images"
                    echo "After deletion, these are the current existing local images"
                    docker images
                    
                    echo "Will save artifacts for ICR"
                    set +x
                    # Login to ibmcloud using function defined in ibmcloud_utils.sh
                    ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"

                    ibmcloud cr login

                    save_artifacts_images "${PATH_TO_BUILD_META}" \
                    "${IBMCLOUD_CR_URL_ONEPIPELINE}" "${GIT_SHA_FOR_SAVE_ARTIFACTS}" \
                    "${SAVE_ARTIFACTS_ONLY_FIRST_IMAGE_MODE}" "${SUFFIX_FOR_ICR_SAVE_ARTIFACTS}" "${SAVE_ARTIFACTS_FAIL_IF_NO_MANIFEST}"
                fi

                # Define path to the third party images file
                third_party_images_yaml_file="${PATH_TO_WORKSPACE_REPO}/${THIRD_PARTY_IMAGES_YAML_FILE_PATH}"

                # First check if the file exists at all
                if [ -f "${third_party_images_yaml_file}" ]
                then
                    # Delete all the local images, this is in order to force an actual pull from the remote registry
                    echo "Will proceed to delete all local docker images in order to force actual pull"
                    echo "These are the current existing local images"
                    docker images
                    echo "*******************************************************************************************"
                    docker rmi -f $(docker images -a -q) || echo "Found no local images"
                    echo "After deletion, these are the current existing local images"
                    docker images

                    # Call function that saves artifacts for third party images
                    save_artifacts_images_third_party "${third_party_images_yaml_file}" \
                    "${ARTIFACTORY_DOCKER_URL}" "${PIPELINE_REPO_NAME}" "${GIT_SHA_FOR_SAVE_ARTIFACTS}" \
                    "${SAVE_ARTIFACTS_ONLY_FIRST_IMAGE_MODE}" " " "${SAVE_ARTIFACTS_FAIL_IF_NO_MANIFEST}"

                    if [[ ${ICR_MIGRATION_MODE} == true ]]
                    then
                        # Delete all the local images, this is in order to force an actual pull from the remote registry
                        echo "Will proceed to delete all local docker images in order to force actual pull"
                        echo "These are the current existing local images"
                        docker images
                        echo "*******************************************************************************************"
                        docker rmi -f $(docker images -a -q) || echo "Found no local images"
                        echo "After deletion, these are the current existing local images"
                        docker images
                        
                        echo "Will save artifacts for ICR (Third party)"
                        set +x
                        # Login to ibmcloud using function defined in ibmcloud_utils.sh
                        ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"

                        ibmcloud cr login

                        # Call function that saves artifacts for third party images
                        save_artifacts_images_third_party "${third_party_images_yaml_file}" \
                        "${IBMCLOUD_CR_URL_ONEPIPELINE}" "${PIPELINE_REPO_NAME}" "${GIT_SHA_FOR_SAVE_ARTIFACTS}" \
                        "${SAVE_ARTIFACTS_ONLY_FIRST_IMAGE_MODE}" "${SUFFIX_FOR_ICR_SAVE_ARTIFACTS}" "${SAVE_ARTIFACTS_FAIL_IF_NO_MANIFEST}"
                    fi
                else
                    echo "No third party images file found..."
                fi
            else
                echo "Could not find images in build-meta.yaml"
            fi
        fi

        if [[ "${SAVE_ARTIFACTS_SKIP_PACKAGES}" == "true" ]]
        then
            echo "Skipping saving artifacts for packages"
        else
            # Check if we have packages
            packages=$(yq -r '.packages ' "${PATH_TO_BUILD_META}")

            if [[ ! ${packages} == null ]]; then
                ${PATH_TO_GENCTL_CI}/scripts/process_build_meta_new/process_build_meta_packages_new.sh "download_and_save_artifacts"
            else
                echo "Could not find packages in build-meta.yaml"
            fi
        fi
    else
        echo "Could not find build-meta.yaml file under ${PATH_TO_WORKSPACE_REPO}/hack/ci"
        echo "Can't save artifacts without build-meta.yaml file; will exit with error"
        exit 1
    fi
fi