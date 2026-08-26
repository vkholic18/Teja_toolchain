#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script is the entry point for the "new" logic of processing build-meta.yaml

# This script supports:

# 2 types of artifacts: images and packages
# 4 types of modes: 
        # upload
        # download_and_save_artifacts
        # move_from_pre_release_to_vetted
        # move_from_vetted_to_final_destination

# Note that not each combination of artifacts and mode are valid, this is validated by the script

# The following environment variables need to be set before executing the script:

# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO

# There are environment variables that need to be set depending on the type of artifact and mode
# In addition, the script should get two arguments, the first one is the type of artifact and the second one is the process mode

# In additional the following variables are optional and if not have values they will take the default
export PROCESS_BUILD_META_DRY_RUN_MODE=${PROCESS_BUILD_META_DRY_RUN_MODE:-"false"}
export PROCESS_BUILD_META_UPLOAD_PACKAGES_INCLUDE_METADATA=${PROCESS_BUILD_META_UPLOAD_PACKAGES_INCLUDE_METADATA:-"false"}


supported_types_of_artifacts="images packages"
supported_process_modes="upload download_and_save_artifacts move_from_pre_release_to_vetted move_from_vetted_to_final_destination"

# Check we got two arguments
if [ "$#" -eq 2 ]; then

    # Get the arguments
    artifact_type=$1
    process_mode=$2

    # Check the artifact type is valid
    if [[ "$supported_types_of_artifacts" =~ (^|[[:space:]])$artifact_type($|[[:space:]]) ]]
    then
        # Check the process mode is valid
        if [[ "$supported_process_modes" =~ (^|[[:space:]])$process_mode($|[[:space:]]) ]]
        then
            # Check there is build-meta.yaml file
            if [ -f ${PATH_TO_WORKSPACE_REPO}/hack/ci/build-meta.yaml ]
            then
                if [[ ${artifact_type} == "images" ]] 
                then
                    echo "Not implemented yet..."
                    #${PATH_TO_GENCTL_CI}/scripts/process_build_meta_new/process_build_meta_images_new.sh $process_mode
                else
                    ${PATH_TO_GENCTL_CI}/scripts/process_build_meta_new/process_build_meta_packages_new.sh $process_mode
                fi
            else
                echo "Could not find build-meta.yaml file; will exit with error"
                exit 1
            fi
        else
            echo "Process mode ${process_mode} is not supported; will exit with error"
            exit 1
        fi
    else
        echo "Artifact type ${artifact_type} is not supported; will exit with error"
        exit 1
    fi
else
    echo "Process build meta new mode requires two arguments: type of artifact and process mode; will exit with error"
    exit 1
fi
