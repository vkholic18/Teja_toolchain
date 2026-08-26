#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script handles the save artifact for the case of non standard naming images
# The assumption is that we execute this script there are few conditions that are met

# 1. There is one file in CI_NON_STANDARD_NAMING_IMAGES_DIR
# 2. The content of the file is a full URL to an image in artifactory

# In addition, note that if we are in this mode, then there is no processing of packages (Ex: debian)
# In other words, a repo that builds an image with non standard naming is limited to only one image and no packages

# The following environment variables need to be set before executing the script:

# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO
# CC_ARTIF_ACCESS_TOKEN
# ARTIFACTORY_DOCKER_URL, WCP_ARTIFACTORY_USERNAME

# Source tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/save_artifacts_utils.sh
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh 

CUSTOM_IMG_MAPPING_SCRIPT_PATH="${PATH_TO_WORKSPACE_REPO}/hack/ci/create-custom-image-mapping.sh"

if [[ -f "${CUSTOM_IMG_MAPPING_SCRIPT_PATH}" ]]; then
    echo "We are on save artifacts for non standard naming images..."

    # Get the SHA used to save artifacts
    pushd ${PATH_TO_WORKSPACE_REPO}
    GIT_SHA_FOR_SAVE_ARTIFACTS=$(git rev-parse --verify HEAD)
    popd

    # Delete all the local images
    echo "Will proceed to delete all local docker images in order to force actual pull"
    echo "These are the current existing local images"
    docker images
    echo "*******************************************************************************************"
    docker rmi -f $(docker images -a -q)
    echo "After deletion, these are the current existing local images"
    docker images

    # Then we login to artifactory
    orig_opts=$-
    set +x
    echo "Logging into ${ARTIFACTORY_DOCKER_URL}"
    echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_URL} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
    set -${orig_opts}

    # Move to the directory
    pushd "${CI_NON_STANDARD_NAMING_IMAGES_DIR}"

    # Copy images to ICR if SAVE_IMAGES_TO_ICR is set to true
    echo "Will copy images to ICR..."

    # Iterate through the same files again for artifactory copying
    for image_to_save_artifact in *
    do
        img_full_name=$(cat ${image_to_save_artifact})

        echo "Processing image for artifactory copy: ${img_full_name}"

        # Extract image name and tag from full artifactory path
        # Example: docker-na-public.artifactory.swg-devops.com/wcp-genctl-sandbox-docker-local/rhos-installation/ocp-release:4.17.36-x86_64-egress-router-cni
        # We need to get: rhos-installation/ocp-release:4.17.36-x86_64-egress-router-cni

        # Remove the registry URL part (everything before the third /)
        image_path_with_tag=$(echo "${img_full_name}" | sed 's|^[^/]*/[^/]*/||')

        echo "Image path with tag: ${image_path_with_tag}"

        image_source_path="${ARTIFACTORY_SANDBOX_DOCKER_URL}/${image_path_with_tag}"

        # Pull the image from Artifactory
        echo "Pulling image from Artifactory: ${image_source_path}"
        docker pull "${image_source_path}"

        # Construct ARTIFACTORY image path (keeping the same image name and tag)
        image_destination_path="${ARTIFACTORY_DOCKER_PROD_URL}/${image_path_with_tag}"

        echo "Tagging image for ARTIFACTORY: ${icr_image_path}"
        docker tag "${image_source_path}" "${image_destination_path}"

        # Push to ARTIFACTORY
        echo "Pushing image to ARTIFACTORY: ${image_destination_path}"
        docker push "${image_destination_path}"

        echo "Successfully copied image to ARTIFACTORY: ${image_destination_path}"

        echo "Will proceed to delete all local docker images in order to force actual pull"
        echo "These are the current existing local images"
        docker images
        echo "*******************************************************************************************"
        docker rmi -f $(docker images -a -q) || echo "Found no local images"
        echo "After deletion, these are the current existing local images"
        docker images
    done

    if [[ ${ICR_MIGRATION_MODE} == true ]]
    then
        orig_opts=$-
        set +x
        # Login to ibmcloud using function defined in ibmcloud_utils.sh
        ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"
        ibmcloud cr login
        set -${orig_opts}

        # Iterate through the same files again for ICR copying
        for image_to_save_artifact in *
        do
            img_full_name=$(cat ${image_to_save_artifact})

            echo "Processing image for ICR copy: ${img_full_name}"

            # Extract image name and tag from full artifactory path
            # Example: docker-na-public.artifactory.swg-devops.com/wcp-genctl-docker-local/rhos-installation/ocp-release:4.17.36-x86_64-egress-router-cni
            # We need to get: rhos-installation/ocp-release:4.17.36-x86_64-egress-router-cni

            # Remove the registry URL part (everything before the third /)
            image_path_with_tag=$(echo "${img_full_name}" | sed 's|^[^/]*/[^/]*/||')

            echo "Image path with tag: ${image_path_with_tag}"

            # Pull the image from Artifactory
            echo "Pulling image from Artifactory: ${img_full_name}"
            docker pull "${img_full_name}"

            # Construct ICR image path (keeping the same image name and tag)
            icr_image_path="${IBMCLOUD_CR_URL_ONEPIPELINE}/${image_path_with_tag}"

            echo "Tagging image for ICR: ${icr_image_path}"
            docker tag "${img_full_name}" "${icr_image_path}"

            # Push to ICR
            echo "Pushing image to ICR: ${icr_image_path}"
            docker push "${icr_image_path}"

            echo "Successfully copied image to ICR: ${icr_image_path}"

            echo "Will proceed to delete all local docker images in order to force actual pull"
            echo "These are the current existing local images"
            docker images
            echo "*******************************************************************************************"
            docker rmi -f $(docker images -a -q) || echo "Found no local images"
            echo "After deletion, these are the current existing local images"
            docker images
        done
    fi

    # Move back
    popd
else
    echo "No action needed"
fi
