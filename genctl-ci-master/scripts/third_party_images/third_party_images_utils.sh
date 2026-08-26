#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

function create_images_file_for_retag_dev_int_to_master_third_party (){
    # This function takes as an input a third-party-images file and creates a new file that is used for the retag process in merge to master razee
    # For each entry in the input file we get two entries with SHA and SemVer of dev-integration

    # Expected parameters:

    # $1 --> Full path to the third-party-images.yaml file
    # $2 --> Repo name (To concatenate to prefix)
    # $3 --> Dev-integration SHA
    # $4 --> Dev-integration SemVer
    # $5 --> Full path to the result file

    # Put some friendly names
    path_to_third_party_images_file=$1
    repo_name=$2
    dev_integ_sha=$3
    dev_integ_semver=$4
    result_file_path=$5

    # Get images
    images=$(yq -r '.images[]' "${path_to_third_party_images_file}")

     # Iterate
    for image in ${images}
    do
        # Split image and tag
        image_name=$(echo "${image}" | cut -d ':' -f 1)
        
        # Add entry with dev-integ SHA
        echo "third-party-images/${repo_name}/${image_name}:${dev_integ_sha}" >> ${result_file_path}

        # Add entry with dev-integ SemVer
        echo "third-party-images/${repo_name}/${image_name}:${dev_integ_semver}" >> ${result_file_path}
    done
}
function create_images_file_for_icr_backup_third_party (){
    # This function takes as an input a third-party-images file and creates a new file that is used for the ICR backup process in merge to master razee
    # For each entry in the input file we get two entries with SHA and SemVer of master

    # Expected parameters:

    # $1 --> Full path to the third-party-images.yaml file
    # $2 --> Repo name (To concatenate to prefix)
    # $3 --> Master SHA
    # $4 --> Master SemVer
    # $5 --> Full path to the result file

    # Put some friendly names
    path_to_third_party_images_file=$1
    repo_name=$2
    master_sha=$3
    master_semver=$4
    result_file_path=$5

    # Get images
    images=$(yq -r '.images[]' "${path_to_third_party_images_file}")

     # Iterate
    for image in ${images}
    do
        # Split image and tag
        image_name=$(echo "${image}" | cut -d ':' -f 1)
        
        # Add entry with dev-integ SHA
        echo "third-party-images/${repo_name}/${image_name}:${master_sha}" >> ${result_file_path}

        # Add entry with dev-integ SemVer
        echo "third-party-images/${repo_name}/${image_name}:${master_semver}" >> ${result_file_path}
    done
}