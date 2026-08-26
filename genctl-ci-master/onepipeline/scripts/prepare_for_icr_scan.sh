#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script prepares for the ICR Scan

# It relies on the existing saved artifacts that we can retrieve with list_artifacts in order to

# A) Pull from artifactory and push to ICR if the images do not exist there yet
# B) Make another save_artifacts command with the ICR url in order for the scan to work

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI
# IBMCLOUD_KEY_FOR_PREPARE_FOR_ICR_SCAN
# ARTIFACTORY_DOCKER_URL, WCP_ARTIFACTORY_USERNAME, CC_ARTIF_ACCESS_TOKEN
# IBMCLOUD_CR_URL_ONEPIPELINE

# In addition the following environment variables are optional and if not defined will take default value

export PREPARE_FOR_ICR_SCAN_DRY_RUN_MODE=${PREPARE_FOR_ICR_SCAN_DRY_RUN_MODE:-"false"}

# ICR migration mode

export ICR_MIGRATION_MODE=${ICR_MIGRATION_MODE:-"false"} # By default we are not pushing images to ICR

if [[ ${ICR_MIGRATION_MODE} == true ]]
then
    echo "ICR_MIGRATION_MODE is true, no need to special preparations"
    echo "At this point images should be already in ICR and artifacts with ICR URL should have already been saved"
    exit 0
fi

# First we need to login to artifactory

# Prevent creds from being printed out when debugging
orig_opts=$-
set +x
echo "Logging into ${ARTIFACTORY_DOCKER_URL}"
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_URL} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
set -${orig_opts}

# Now we need to login to ICR

# Source the ibmcloud_utils.sh
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

set +x
# Login to ibmcloud using function defined in ibmcloud_utils.sh
ibmcloud_login "${IBMCLOUD_KEY_FOR_PREPARE_FOR_ICR_SCAN}"
set -x

ibmcloud cr login

# Iterate over the saved artifacts
while read -r artifact
do
    # Get the name of the artifact "object" and the name field of artifact (For docker images is the full path to the image)
    art_object_saved_name=${artifact}
    original_art="$(load_artifact "${artifact}" name)"

    art_tags="$(load_artifact "${artifact}" tags)"
    
    # Get the type
    art_type="$(load_artifact "${artifact}" type)"

    # Different logic for images and packages
    if [[ "${art_type}" == "image" ]]
    then
        # Here we replace the artifactory image path with the ICR one, in other words, for example, we replace: 
        # docker-na-public.artifactory.swg-devops.com/wcp-genctl-docker-local/rias/compute-billing-lifecycle-mgmt:fad36ffe610d7875244bff758bad3de6fd37bb9a-amd64
        # With
        # us.icr.io/genctl-cicd-onepipeline/rias/compute-billing-lifecycle-mgmt:fad36ffe610d7875244bff758bad3de6fd37bb9a-amd64
        replaced_with_icr_url=${original_art/$ARTIFACTORY_DOCKER_URL/$IBMCLOUD_CR_URL_ONEPIPELINE}

        echo "Will check if there is an image ${replaced_with_icr_url} in ICR..."

        # Save original options
        orig_opts=$-

        # We set +e in order not to stop execution if the image-inspect returns error
        set +e 

        # Check if image exists and save exit code
        result=$(ibmcloud cr image-inspect ${replaced_with_icr_url})
        statusCode=$?
        
        # Bring back original flags
        set -${orig_opts}
        
        if [[ "${statusCode}" -ne 0 ]]; then
            echo "Image ${replaced_with_icr_url} does not exists in ICR"

            echo "Will proceed to pull ${original_art} and push to ${replaced_with_icr_url}"

            docker pull ${original_art}
            docker image tag ${original_art} ${replaced_with_icr_url}
            if [[ $PREPARE_FOR_ICR_SCAN_DRY_RUN_MODE = true ]]; then
                echo "DRY RUN MODE !!!"
                echo "Would have pushed ${replaced_with_icr_url}"
            else
                docker push ${replaced_with_icr_url}
            fi
            
            # Remove locally
            docker rmi ${replaced_with_icr_url}
            docker rmi ${original_art}
        fi

        ### Deal with the SemVer ###

        # Move to repo
        pushd "${PATH_TO_WORKSPACE_REPO}"

        # Extract some info
        SHA=$(git rev-parse --verify HEAD)
        SEMVER=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true

        # Move back
        popd

        # Check we have SemVer
        if [[ ! -z "${SEMVER}" ]]
        then
            echo "SemVer is ${SEMVER}"

            # This line replaces the SHA with the SemVer, for example we have:
            # us.icr.io/genctl-cicd-onepipeline/rias/compute-billing-lifecycle-mgmt:207f364c4085be969daf0babf13cae0ec48fb263-amd64
            # And this replaces to
            # us.icr.io/genctl-cicd-onepipeline/rias/compute-billing-lifecycle-mgmt:1.39.0-dev.5-amd64
            icr_url_and_semver_instead_sha=${replaced_with_icr_url/$SHA/$SEMVER}
            
            # We set +e in order not to stop execution if the image-inspect returns error
            set +e 

            # Check if image exists and save exit code
            result=$(ibmcloud cr image-inspect ${icr_url_and_semver_instead_sha})
            statusCode=$?
            
            # Bring back original flags
            set -${orig_opts}
            
            if [[ "${statusCode}" -ne 0 ]]; then
                echo "Image ${icr_url_and_semver_instead_sha} does not exists in ICR"

                echo "Will proceed to pull ${original_art} and push to ${icr_url_and_semver_instead_sha}"

                docker pull ${original_art}
                docker image tag ${original_art} ${icr_url_and_semver_instead_sha}
                if [[ $PREPARE_FOR_ICR_SCAN_DRY_RUN_MODE = true ]]; then
                    echo "DRY RUN MODE !!!"
                    echo "Would have pushed ${icr_url_and_semver_instead_sha}"
                else
                    docker push ${icr_url_and_semver_instead_sha}
                fi
                
                # Remove locally
                docker rmi ${icr_url_and_semver_instead_sha}
                docker rmi ${original_art}
            fi
        else
            echo "No SemVer found"
        fi

        # At this point image should exist in ICR, either because it was from a previous run or because we just pushed it
        # Since the image should exist we can safely pull
        # For save_artifact we use only the one with the SHA
        docker pull ${replaced_with_icr_url}
        
        DIGEST="$(docker inspect --format='{{index .RepoDigests 0}}' "${replaced_with_icr_url}" | awk -F@ '{print $2}')"
                    
        NAME_FOR_SAVE_ARTIFACT="${art_object_saved_name}_FOR_ICCR_SCAN"

        if [[ $PREPARE_FOR_ICR_SCAN_DRY_RUN_MODE = true ]]; then
            echo "DRY RUN MODE !!!"
            echo "Would have saved_artifact with object name ${NAME_FOR_SAVE_ARTIFACT} and property name ${replaced_with_icr_url}"
        else
            save_artifact "${NAME_FOR_SAVE_ARTIFACT}" \
            type=image \
            "name=${replaced_with_icr_url}" \
            "digest=${DIGEST}" \
            "tags=${art_tags}"
        fi
    else
       echo "Artifacts ${art_object_saved_name} is not an image"
    fi
done < <(list_artifacts)