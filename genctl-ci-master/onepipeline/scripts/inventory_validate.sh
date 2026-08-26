#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# This script comapres the build-meta.yaml file inside a workspace with its relevant inventory-repo.
# If there are images inside the inventory repo, that do not exist in the build-meta we will fail the pipeline
# Validation wont run if the build-meta.yaml file has no images in it

# Source tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh 

# Set the path to the build-meta.yaml file for easier use
PATH_TO_BUILD_META="${PATH_TO_WORKSPACE_REPO}/hack/ci/build-meta.yaml"
# Check if the build-meta has any images
repo_has_images_in_build_meta "${PATH_TO_BUILD_META}"

if [[ "${RESULT_CHECK_IF_REPO_HAS_IMAGES}" == "true" ]]
then
    declare -a multi_arch_images=()
    declare -a non_multi_arch_images=()
    echo "Found at least one image in build-meta"
    readarray -t arch_types < <(yq -r '.images | keys[]' "${PATH_TO_BUILD_META}")

    # Loop through each architecture type
    for arch_type in "${arch_types[@]}"; do

        echo "--- Processing images for architecture: ${arch_type} ---"

        readarray -t images_list < <(yq -r ".images.${arch_type} | select(. != null) | if type == \"array\" then .[] else (. | split(\" \")[]) end" "${PATH_TO_BUILD_META}")

        # Check if the images_list is empty for the current architecture
        if [ "${#images_list[@]}" -eq 0 ]; then
            echo "No images found for architecture: ${arch_type}"
            continue
        fi

        # Loop through each image in the current architecture's list
        for image_name in "${images_list[@]}"; do
            transformed_name="${image_name//\//_}"
            # Not doing any further manipulation on multi arch
            if [ "${arch_type}" == "multi_arch" ]; then
                final_name="${transformed_name}"
                multi_arch_images+=("${final_name}")
            else
                final_name="${transformed_name}_${arch_type}_image"
                non_multi_arch_images+=("${final_name}")
            fi
        done
    done
else
    echo "Could not find any images defined in build-meta.yaml file"
    echo "Won't validate images"
    exit 0
fi

PATH_TO_BUILD_THIRD_PARTY="${PATH_TO_WORKSPACE_REPO}/hack/ci/third-party-images.yaml"
third_party_image_names=($(grep -v "images:" "$PATH_TO_BUILD_THIRD_PARTY" | sed -E 's|.*/([^:]+):.*|\1|' | sed 's/- //'))

INVENTORY_REPO="$(get_env inventory-repo)"
GIT_BRANCH="master"
temp_url="${INVENTORY_REPO#https://}"
temp_url="${temp_url%.git}"


if [[ "$temp_url" =~ ^([^/]+)/([^/]+)/([^/]+)$ ]]; then
  GIT_HOST="${BASH_REMATCH[1]}"
  GIT_REPO_OWNER="${BASH_REMATCH[2]}"
  GIT_REPO_NAME="${BASH_REMATCH[3]}"
else
  echo "Error: Could not parse Git repository URL: ${temp_url}" >&2
  exit 1
fi

# Get the API url of an inventory repo
API_URL="https://${GIT_HOST}/api/v3/repos/${GIT_REPO_OWNER}/${GIT_REPO_NAME}/git/trees/${GIT_BRANCH}?recursive=1"

# Get the files from the inventory repo
response=$(curl -s -H "Authorization: token ${GITHUB_API_KEY}" \
                  -H "Accept: application/vnd.github.v3+json" \
                  "${API_URL}")

# Get all images from the inventory and convert non_multi_arch_images into a space separeted strings
readarray -t built_inv_images < <(echo "${response}" | jq -r '.tree[] | select(.type == "blob") | .path' | grep -i "image$" | grep -vi "^third")
readarray -t third_party_inv_images < <(echo "${response}" | jq -r '.tree[] | select(.type == "blob") | .path' | grep -i "image$" | grep -i "^third")
printf -v non_multi_arch_images_str " %s " "${non_multi_arch_images[@]}"
skip_multi_arch_check=false
declare -a missing_images=()
declare -a true_delta=()

echo "--- Filtering non multi arch images ---"

# First compare the inventory images with the list of non multi_arch images each image not found put in missing list
for inv_image in "${built_inv_images[@]}"; do
    if ! [[ "${non_multi_arch_images_str}" =~ " ${inv_image} " ]]; then
        missing_images+=("${inv_image}")
    fi
done

# Check if there any still missing images, if none, no need to verify multi_arch
built_inv_images=("${missing_images[@]}")
if [ "${#built_inv_images[@]}" -eq 0 ]; then
    skip_multi_arch_check=true
fi

echo "--- Filtering multi arch images ---"

# Check if there any multi-arch images defined in the build-meta, if not and there are still missing images - fail
if [ "$skip_multi_arch_check" = false ]; then
    if [ "${#multi_arch_images[@]}" -eq 0 ]; then
        echo "  No multi_arch images defined in build-meta of ${CC_REPO_NAME} were found in ${temp_url}. The following images are considered missing from build-meta:"
        printf "  %s\n" "${built_inv_images[@]}"
        echo "To resolve this issue please open a PR against ${temp_url} deleting the redundant image, once deleted - rerun the pipeline"
        exit 1
    else
        # get the regex check on base name of image (without architecture, as this may have various due to being multi-arch)
        multi_arch_check_regex="^($(printf '%s_.* ' "${multi_arch_images[@]}" | sed 's/ /|/g; s/|*$//'))$"
        for inv_image in "${built_inv_images[@]}"; do
            # Check if the inventory image matches any of the multi-arch base patterns
            if ! [[ "${inv_image}" =~ ${multi_arch_check_regex} ]]; then
                true_delta+=("${inv_image}")
                echo "  '${inv_image}' NOT found in multi_arch_images."
            fi
        done
    fi
fi

echo "--- Filtering third party images ---"

# Check if there any third party images in the inventory repo
if [ "${#third_party_inv_images[@]}" -eq 0 ]; then
    echo "no third party images found in the inventory"
else
    echo "inventory repo have third party images, will vlidate against the third_party_images.yaml file"
    third_party_image_regex_parts=$(printf "|%s" "${third_party_image_names[@]}")
    third_party_image_regex_parts=${third_party_image_regex_parts:1}
    third_party_regex="_(${third_party_image_regex_parts})_"
    for inv_image in "${third_party_inv_images[@]}"; do
        if ! [[ "${inv_image}" =~ ${third_party_regex} ]]; then
            true_delta+=("${inv_image}")
            echo "  '${inv_image}' NOT found in third-party-images.yaml"
        fi
    done
fi

if [ "${#true_delta[@]}" -gt 0 ]; then
    echo "ERROR: The following images were found in  ${temp_url} but are missing from build-meta or third_party_images of ${CC_REPO_NAME} :"
    printf "  %s\n" "${true_delta[@]}"
    echo "To resolve this issue please open a PR against ${temp_url} deleting the redundant image, once deleted - rerun the pipeline"
    exit 1 
else
    echo " image validation completed successfuly"
    exit 0 
fi
