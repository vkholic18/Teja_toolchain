#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script checks if the third-party-images file exists and if yes does some validations on it

# The following environment variables need to be set before executing the script:
# PATH_TO_WORKSPACE_REPO

# =============================================================================================

# Set flags
set -e

# Define path to the file
third_party_images_yaml_file="${PATH_TO_WORKSPACE_REPO}/${THIRD_PARTY_IMAGES_YAML_FILE_PATH}"

# First check if the file exists at all
if [ -f "${third_party_images_yaml_file}" ]
then
    echo "Found third party images file; will proceed to validate..."

    set +e # For not inmediately failing on validation

    # First we validate is a valid YAML file
    python3 -c 'import yaml,sys;yaml.safe_load(sys.stdin)' < "${third_party_images_yaml_file}"  > /dev/null 2>&1
    
    if [[ $? -eq 0 ]]
    then
        echo "File ${third_party_images_yaml_file} is a valid YAML file"

        set -e

        # Get images
        images=$(yq -r '.images[]' "${third_party_images_yaml_file}")

        # If we have any image, then process
        if [[ ! ${images} == null ]]; then
            
            # Use a variable to store the ones we processed already
            existing_images=""
            
            # Iterate
            for image in ${images}
            do
                # Split image and tag
                image_name=$(echo "${image}" | cut -d ':' -f 1)
                image_tag=$(echo "${image}" | cut -d ':' -f 2)

                # Verify the image is not in the list yet
                if [[ "$existing_images" =~ (^|[[:space:]])$image_name($|[[:space:]]) ]]
                then
                    echo "There is an issue with image ${image}"
                    echo "Image ${image_name} already exists with a different tag"
                    echo "We don't allow to include same image twice in the file..."
                    echo "Will exit with error..."
                    exit 1
                else
                    # Verify the image does not contain architecture
                    if [[ $image_tag == *"-amd64"* ]] ||  [[ $image_tag == *"-s390x"* ]] 
                    then
                        echo "There is an issue with image ${image}"
                        echo "Image tag should NOT include architecture"
                        echo "Will exit with error..."
                        exit 1
                    else
                        existing_images="${existing_images} ${image_name}"
                    fi
                fi            
            done

            echo "Succesfully validated third party images file"
        fi
    else
        echo "ERROR: File ${third_party_images_yaml_file} is not a valid YAML file"
        exit 1
    fi
else
    echo "No third party images file..."
fi