#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

function save_artifact_package() {
    # This function makes the relevant logic for downloading and saving artifact for a specific package

    # It receives the following parameters

    # art_url --> Artifactory url (Required for checking file and download it)
    # art_token --> Token for authentication against artifactory
    # package_repo_for_download --> The package repository in artifactory to download from
    # package_dir_for_download --> The directory for download
    # org_and_repo --> The org and repo
    # sha --> The sha
    # package_type --> The package type
    # arch --> The package architecture
    # workspace_desired_path_in_artifactory --> The path under our prefixed path to search the package for
    # repo_for_artifact_field --> The package final destination (For the purpose of saving artifact already with the right values)
    # file_name_to_search --> The string used to search the file

    art_url=$1
    art_token=$2
    package_repo_for_download=$3
    package_dir_for_download=$4
    org_and_repo=$5
    sha=$6
    package_type=$7
    arch=$8
    workspace_desired_path_in_artifactory=$9
    repo_for_artifact_field=${10}
    file_name_to_search=${11}

    # Get a short version of the sha
    short_sha=${sha:0:12}

    # This is used for download
    path_to_package_after_repo_and_destination="${org_and_repo}/${short_sha}/${package_type}/${arch}/${workspace_desired_path_in_artifactory}"

    # Build the path to the directory where the package should be located
    path_to_package_in_art_after_url_for_download="${package_repo_for_download}/${package_dir_for_download}/${path_to_package_after_repo_and_destination}"

    # First get the name of the file
    get_file_name_in_artifactory "${art_token}" "${art_url}" "${path_to_package_in_art_after_url_for_download}" "${file_name_to_search}"

    # Download
    download_file_from_artifactory "${art_token}" \
    "${art_url}/${path_to_package_in_art_after_url_for_download}/${FOUND_FILE_NAME_IN_ARTIFACTORY}" \
    "${PWD}/${FOUND_FILE_NAME_IN_ARTIFACTORY}"

    # Calculate digest
    package_digest="$(sha256sum "${PWD}/${FOUND_FILE_NAME_IN_ARTIFACTORY}" | awk '{print $1}')"

    # Some logic required for save artifact

    package_no_slashes=$(echo "$workspace_desired_path_in_artifactory" | tr / _)
    name_for_save_artifact="${package_no_slashes}_${file_name_to_search}_${arch}_${package_type}"

    echo "Will try to save artifact for ${name_for_save_artifact}"

    final_destination_path="${art_url}/${repo_for_artifact_field}/${workspace_desired_path_in_artifactory}/${FOUND_FILE_NAME_IN_ARTIFACTORY}"

    # Save artifact
    save_artifact "${name_for_save_artifact}" \
    type="${package_type}" \
    "name=${final_destination_path}" \
    "digest=sha256:${package_digest}" \
    "tags=${sha}"

    res_save_artifact=$?
    if [ $res_save_artifact -eq 0 ]; then
        echo "Succesfully saved artifact ${name_for_save_artifact}"
    else
        echo "Something went wrong when saving artifact ${name_for_save_artifact}"
        echo "Will exit with error..."
        exit 1
    fi
}

function save_artifact_image() {
    # This function makes the relevant logic for pulling and saving artifact for a specific image

    # It receives the following parameters

    # img --> The image (Example: genctl/acadia-discovery-controller)
    # registry_url --> Registry url
    # sha 
    # arch_type
    # artifact_image_explicit_name --> Either empty string or an explicit name that we will use
    # artifact_name_suffix --> Either string with empty space or a string which will be a suffix added to the artifact name

    # IMPORTANT: This function assumes we are already logged in against the registry

    img=$1
    registry_url=$2
    sha=$3
    arch_type=$4
    artifact_image_explicit_name=$5
    artifact_name_suffix=$6

    # Build the full path to the image
    # For no-arch images, don't add architecture suffix
    if [[ "${arch_type}" == "no-arch" ]]; then
        full_image_path="${registry_url}/${img}:${sha}"
    else
        full_image_path="${registry_url}/${img}:${sha}-${arch_type}"
    fi

    echo "Will try to save artifact for ${full_image_path}"

    # First check if the image exists
    result=$(docker manifest inspect ${full_image_path})
    status_code=$?

    # If it exists, proceed to pull and save artifact; if not, exit 1 with error
    if [[ "${status_code}" -eq 0 ]]; then

        # Since the image should exist we can safely pull
        docker pull "${full_image_path}"
        res=$?

        # Check if pull was succesful
        if [ $res -eq 0 ]; then
            
            DIGEST="$(docker inspect --format='{{index .RepoDigests 0}}' "${full_image_path}" | awk -F@ '{print $2}')"

            IMAGE_NO_SLASHES=$(echo "$img" | tr / _)
            
            # If no explicit name was given, use default which is the image name and the arch
            # If an explicit name was given, favour that explicit name
            if [[ "${artifact_image_explicit_name}" == "" ]]
            then
                NAME_FOR_SAVE_ARTIFACT="${IMAGE_NO_SLASHES}_${arch_type}"
            else
                NAME_FOR_SAVE_ARTIFACT=${artifact_image_explicit_name}
            fi

            # Add suffix if required
            if [[ "${artifact_name_suffix}" != " " ]]
            then
                NAME_FOR_SAVE_ARTIFACT="${NAME_FOR_SAVE_ARTIFACT}_${artifact_name_suffix}"
            fi

            save_artifact "${NAME_FOR_SAVE_ARTIFACT}" \
            type=image \
            "name=${full_image_path}" \
            "digest=${DIGEST}" \
            "tags=${sha}"

            res_save_artifact=$?
            if [ $res_save_artifact -eq 0 ]; then
                echo "Succesfully saved artifact with name ${NAME_FOR_SAVE_ARTIFACT}"
                echo "The full path to the image is: ${full_image_path}"
            else
                echo "Something went wrong when saving artifact ${NAME_FOR_SAVE_ARTIFACT}"
                echo "Will exit with error..."
                exit 1
            fi

        else
            echo "There was an issue when trying to pull image ${full_image_path} for the purpose of saving artifact"
            echo "Will exit with error..."
            exit 1
        fi
    else
        echo "Image ${full_image_path} does not exist; will exit with error..."
        exit 1
    fi
}
function save_artifact_image_defined_in_ci_dir() {
    # This function makes the relevant logic for pulling and saving artifact for images defined in CI dir

    # The CI dir contains a list of txt files in which:

    # A) The name of the file is what we will set as name of the artifact
    # B) The content of the file has the full path to the image

    # It receives the following parameters

    # img --> The image (Example: hostos/hostos-boot-release)
    # sha 
    # full_image_path --> The full image path to make docker pull

    # IMPORTANT: This function assumes we are already logged in against the registry

    img=$1
    sha=$2
    full_image_path=$3

    echo "Will try to save artifact for ${full_image_path}"

    # First check if the image exists
    result=$(docker manifest inspect ${full_image_path})
    status_code=$?

    # If it exists, proceed to pull and save artifact; if not, exit 1 with error
    if [[ "${status_code}" -eq 0 ]]; then

        # Since the image should exist we can safely pull
        docker pull "${full_image_path}"
        res=$?

        # Check if pull was succesful
        if [ $res -eq 0 ]; then

            DIGEST="$(docker inspect --format='{{index .RepoDigests 0}}' "${full_image_path}" | awk -F@ '{print $2}')"

            save_artifact "${img}" \
            type=image \
            "name=${full_image_path}" \
            "digest=${DIGEST}" \
            "tags=${sha}"

            res_save_artifact=$?
            if [ $res_save_artifact -eq 0 ]; then
                echo "Succesfully saved artifact ${NAME_FOR_SAVE_ARTIFACT}"
            else
                echo "Something went wrong when saving artifact ${NAME_FOR_SAVE_ARTIFACT}"
                echo "Will exit with error..."
                exit 1
            fi
        else
            echo "There was an issue when trying to pull image ${full_image_path} for the purpose of saving artifact"
            echo "Will exit with error..."
            exit 1
        fi
    else
        echo "Image ${full_image_path} does not exist; will exit with error..."
        exit 1
    fi
}
function save_artifacts_images_list() {
    IMAGES_LIST=$1 # A string which is a list of space separated images (For example: "genctl/compute-agent genctl/capacity-pool-controller" )
    IMG_REGISTRY_URL=$2 # URL to the image registry (Example docker-na-public.artifactory.swg-devops.com/wcp-genctl-docker-local)
    SHA=$3 # Commit SHA
    ONLY_FIRST_IMAGE_MODE=$4 # A boolean indicating true if we want to use only the first image or false if we want to save all the images
    SUFFIX=$5 # Either empty string or a string which will be a suffix added to the artifact name
    SV_ART_FAIL_IF_NO_MNFST=$6 # A boolean indicating true if we want to fail in case manifest does not exist or false otherwise
    IS_NO_ARCH=$7 # Optional: A boolean indicating if these are no-arch images (default: false)

    for img_for_save_artifact in ${IMAGES_LIST}
    do
        # For no-arch images, skip manifest inspection and use "no-arch" directly
        if [[ "${IS_NO_ARCH}" == "true" ]]; then
            echo "Processing no-arch image: ${img_for_save_artifact}"
            arch_types=("no-arch")
        else
            JQ_REGEX_MANIFEST_ARCHITECTURE='.manifests[].platform.architecture | select( . != null)'

            # Get manifests
            manifests=$(sudo docker manifest inspect ${IMG_REGISTRY_URL}/${img_for_save_artifact}:${SHA})

            if [[ "${SV_ART_FAIL_IF_NO_MNFST}" == "true" ]]
            then
                echo "Will fail if there is no manifest..."
                if [[ -z "${manifests}" ]]
                then
                    echo "Could not find manifest for image ${IMG_REGISTRY_URL}/${img_for_save_artifact}:${SHA}"
                    echo "Will exit with error..."
                    exit 1
                fi
            fi

            # Get arch types
            arch_types=($(echo ${manifests} | jq -r  "${JQ_REGEX_MANIFEST_ARCHITECTURE}"))
        fi

        # Iterate the different architectures and for each type, get the image list and save artifacts
        for arch in ${arch_types[@]}; do
            if [[ "${ONLY_FIRST_IMAGE_MODE}" == "true" ]]
            then
                save_artifact_image "${img_for_save_artifact}" "${IMG_REGISTRY_URL}" "${SHA}" "${arch}" "app-image" "${SUFFIX}"
                return
            else
                save_artifact_image "${img_for_save_artifact}" "${IMG_REGISTRY_URL}" "${SHA}" "${arch}" "" "${SUFFIX}"
            fi
        done
    done
}

function save_artifacts_images() {
    # This function makes the relevant logic for pulling and saving artifacts for all the images on the build-meta.yaml

    PATH_TO_BUILD_META_YAML_FILE=$1 # The path to the build metadata file
    IMG_REGISTRY_URL=$2 # URL to the image registry (Example docker-na-public.artifactory.swg-devops.com/wcp-genctl-docker-local)
    SHA=$3 # Commit SHA
    ONLY_FIRST_IMAGE_MODE=$4 # A boolean indicating true if we want to use only the first image or false if we want to save all the images
    SUFFIX=$5 # Either empty string or a string which will be a suffix added to the artifact name
    SV_ART_FAIL_IF_NO_MNFST=$6 # A boolean indicating true if we want to fail in case manifest does not exist or false otherwise
    
    echo "Regular save artifacts for images process"

    # First process amd64
    images_amd64=$(yq -r '.images.amd64 | select(. != null) | if type=="string" then . else .[] end' "${PATH_TO_BUILD_META_YAML_FILE}")

    save_artifacts_images_list "${images_amd64}" ${IMG_REGISTRY_URL} ${SHA} \
    ${ONLY_FIRST_IMAGE_MODE} "${SUFFIX}" "${SV_ART_FAIL_IF_NO_MNFST}"

    # Then, process multi arch
    images_multi_arch=$(yq -r '.images.multi_arch | select(. != null) | if type=="string" then . else .[] end' "${PATH_TO_BUILD_META_YAML_FILE}")

    save_artifacts_images_list "${images_multi_arch}" ${IMG_REGISTRY_URL} ${SHA} \
    ${ONLY_FIRST_IMAGE_MODE} "${SUFFIX}" "${SV_ART_FAIL_IF_NO_MNFST}"

    # Finally, process no-arch (single-platform images without architecture suffix)
    images_no_arch=$(yq -r '.images.no_arch | select(. != null) | if type=="string" then . else .[] end' "${PATH_TO_BUILD_META_YAML_FILE}")

    save_artifacts_images_list "${images_no_arch}" ${IMG_REGISTRY_URL} ${SHA} \
    ${ONLY_FIRST_IMAGE_MODE} "${SUFFIX}" "${SV_ART_FAIL_IF_NO_MNFST}" "true"
}
function save_artifacts_images_third_party() {
    # This function makes the relevant logic for pulling and saving artifacts for all the images on the third party images YAML file

    PATH_TO_THIRD_PARTY_IMAGES_YAML_FILE=$1 # The path to the YAML file with the list of third party images
    IMG_REGISTRY_URL=$2 # URL to the image registry (Example docker-na-public.artifactory.swg-devops.com/wcp-genctl-docker-local)
    REPO_NAME=$3 # The repo name use to concatenate to prefix
    SHA=$4 # Commit SHA
    ONLY_FIRST_IMAGE_MODE=$5 # A boolean indicating true if we want to use only the first image or false if we want to save all the images
    SUFFIX=$6 # Either empty string or a string which will be a suffix added to the artifact name
    SV_ART_FAIL_IF_NO_MNFST=$7 # A boolean indicating true if we want to fail in case manifest does not exist or false otherwise

    # Get images
    third_party_images=$(yq -r '.images[]' "${PATH_TO_THIRD_PARTY_IMAGES_YAML_FILE}")

    # If we have any image, then process
    if [[ ! ${third_party_images} == null ]]; then
        
        # Create a variable that will hold the processed list
        tmp_processed_list=""

        # Iterate
        for third_party_image in ${third_party_images}
        do
            # Get image part 
            third_party_image_name=$(echo "${third_party_image}" | cut -d ':' -f 1)
            
            # Add image
            # For example if the image in the YAML file is:
            # sysdig/agent-slim:13.4.0
            # This will add third-party-images/monitoring-workspace/sysdig/agent-slim
            tmp_processed_list="${tmp_processed_list} third-party-images/${REPO_NAME}/${third_party_image_name}"
        done

        save_artifacts_images_list "${tmp_processed_list}" ${IMG_REGISTRY_URL} ${SHA} \
        ${ONLY_FIRST_IMAGE_MODE} "${SUFFIX}" "${SV_ART_FAIL_IF_NO_MNFST}"
    fi
}
