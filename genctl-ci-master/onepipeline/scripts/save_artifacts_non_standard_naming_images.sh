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

# List content
echo "Will list the content of ${PWD}"
ls -la

# Iterate and save artifacts (Though we support only one file, set infra for in case in the future we want to support multiple)
for image_to_save_artifact in *
do 
    if [[ "$image_to_save_artifact" == *"__FOR_ICR"* ]]; then
        continue
    fi
    img_full_name=$(cat ${image_to_save_artifact})
    save_artifact_image_defined_in_ci_dir "${image_to_save_artifact}" "${GIT_SHA_FOR_SAVE_ARTIFACTS}" "${img_full_name}"

    echo "Will proceed to delete all local docker images in order to force actual pull"
    echo "These are the current existing local images"
    docker images
    echo "*******************************************************************************************"
    docker rmi -f $(docker images -a -q) || echo "Found no local images"
    echo "After deletion, these are the current existing local images"
    docker images
done

#make artifacts available in ICR for non-standard images tagging
if [[ ${ICR_MIGRATION_MODE} == true ]]
then
    orig_opts=$-
    set +x
    # Login to ibmcloud using function defined in ibmcloud_utils.sh
    ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"
    ibmcloud cr login
    set -${orig_opts}

    echo "finished the login to ICR"

    for image_to_save_artifact in *
    do
        img_full_name=$(cat ${image_to_save_artifact})
        image_path_with_tag=$(echo "${img_full_name}" | sed 's|^[^/]*/[^/]*/||')

        echo "Image path with tag: ${image_path_with_tag}"

        icr_image_path="${IBMCLOUD_CR_URL_ONEPIPELINE}/${image_path_with_tag}"

        save_artifact_image_defined_in_ci_dir "${image_to_save_artifact}_FOR_ICR" "${GIT_SHA_FOR_SAVE_ARTIFACTS}" "${icr_image_path}"
    done

    echo "Will proceed to delete all local docker images in order to force actual pull"
    echo "These are the current existing local images"
    docker images
    echo "*******************************************************************************************"
    docker rmi -f $(docker images -a -q) || echo "Found no local images"
    echo "After deletion, these are the current existing local images"
    docker images
fi

# Move back
popd
