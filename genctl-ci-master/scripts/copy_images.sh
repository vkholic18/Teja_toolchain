#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022, 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script copy images

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO, PATH_TO_IMAGES_TO_COPY

# PULL_REGISTRY, PULL_REGISTRY_USER, PULL_REGISTRY_PASSWORD:
# PUSH_REGISTRY, PUSH_REGISTRY_USER, PUSH_REGISTRY_PASSWORD:

# In additional the following variables are optional and if not have values they will take the default

export COPY_IMAGES_DRY_RUN_MODE=${COPY_IMAGES_DRY_RUN_MODE:-"false"}
export ALLOW_INSECURE=${ALLOW_INSECURE:-"false"}
export CERTIFICATE_VALID=${CERTIFICATE_VALID:-"true"}
export COPY_IMAGES_ENABLED=${COPY_IMAGES_ENABLED:-"true"}
export DO_NOT_OVERWRITE=${DO_NOT_OVERWRITE:-"false"}
export PULL_REGISTRY_API_KEY=${PULL_REGISTRY_API_KEY:-""}
export ICR_PULL_REGISTRY_REGION=${ICR_PULL_REGISTRY_REGION:-""}
export PUSH_REGISTRY_API_KEY=${PUSH_REGISTRY_API_KEY:-""}
export ICR_PUSH_REGISTRY_REGION=${ICR_PUSH_REGISTRY_REGION:-""}
export IMAGES_TO_COPY_AMD64=${IMAGES_TO_COPY_AMD64:-""}
export IMAGES_TO_COPY_MULTI_ARCH=${IMAGES_TO_COPY_MULTI_ARCH:-""}
export IMAGES_TO_COPY_NO_ARCH=${IMAGES_TO_COPY_NO_ARCH:-""}
export IMAGES_AND_MANIFESTS_TO_COPY=${IMAGES_AND_MANIFESTS_TO_COPY:-""}
export FAIL_ON_IMAGE_PULL_FAILURE=${FAIL_ON_IMAGE_PULL_FAILURE:-"false"}
export COPY_IMAGES_SKIP_MANIFESTS=${COPY_IMAGES_SKIP_MANIFESTS:-"false"}

export VERIFY_COPIED_IMAGES_CAN_BE_PULLED=${VERIFY_COPIED_IMAGES_CAN_BE_PULLED:-"false"}

# Retag mode
# Used to:
# 1 .Pull an image with a specific SHA / Semver tag
# 2. Push it to the same registry but with a new SHA / Semver tag
# In addition we support pushing and pulling with a specific tag (Specific has priority over default behavior)
export COPY_IMAGES_RETAG_MODE=${COPY_IMAGES_RETAG_MODE:-"false"}
export RETAG_SPECIFIC_TAGS_TO_PULL=${RETAG_SPECIFIC_TAGS_TO_PULL:-""}
export RETAG_SHA_TO_PULL=${RETAG_SHA_TO_PULL:-""}
export RETAG_SEMVER_TO_PULL=${RETAG_SEMVER_TO_PULL:-""}
export RETAG_SPECIFIC_TAG_TO_PUSH=${RETAG_SPECIFIC_TAG_TO_PUSH:-""}
export RETAG_PREFIX_TO_IMAGE=${RETAG_PREFIX_TO_IMAGE:-""}
export RETAG_SHA_TO_PUSH=${RETAG_SHA_TO_PUSH:-""}
export RETAG_SEMVER_TO_PUSH=${RETAG_SEMVER_TO_PUSH:-""}
export REG_PROD=${REG_PROD:-""}

# Set flags
set -eux

build_root="${PWD}"
build_meta_file="build-meta.yaml"
temp_images=${build_root}/temp_images.txt
image_sync_pipeline_type_file="image_sync_pipeline_type.txt"

# Source retry
. ${PATH_TO_GENCTL_CI}/scripts/retry.sh

# Source ibmcloud_utils
. ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

# Constants
JQ_REGEX_NULL_FILTER='| select(. != null)'
JQ_REGEX_MANIFEST_ARCHITECTURES=".manifests[].platform.architecture ${JQ_REGEX_NULL_FILTER}"
JQ_REGEX_TYPE_FIELD=".mediaType ${JQ_REGEX_NULL_FILTER}"
JQ_REGEX_MANIFEST_TYPE='distribution.manifest.list' # Note: Do not include null filter in this regex! this is used as a substring to search for!
JQ_REGEX_CONFIG_MEDIA_TYPE=".config.mediaType ${JQ_REGEX_NULL_FILTER}"

# Fix for invalid certificate:
certificate_insecure_flag=""
if [[ ${CERTIFICATE_VALID} == "false" ]]; then
    echo "using \"--insecure\" due to issues with the certificate"
    certificate_insecure_flag="--insecure"
fi

# Either prints to the log that insecure registries are allowed, or error out if they are not
# This function is called when there is missing login information for a registry, otherwise is not called.
function check_insecure(){
    if [[ ${ALLOW_INSECURE} == "true" ]]; then
    echo "WARNING! Insecure registries are allowed!"
    insecure_flag="--insecure"
    else
    echo "Warning: No login credentials were provided for a registry"
    #exit 1
    fi
}

# logic for amd64 images
function process_amd64(){
    if [[ ${images_amd64} != "" ]]; then
        echo "image artifact(s) for push: ${images_amd64}"
        architecture="amd64"
        for image in ${images_amd64}
        do
            successful_image_uploads=0
            for tag in $tags; do
                set +e
                IMAGE_TO_PULL="${PULL_REGISTRY}/${image}:${tag}"
                # First check if we are in retag mode at all
                if [[ $COPY_IMAGES_RETAG_MODE = true ]]; then
                    # Here check if we got a specific tag to push; if yes, prefer it; if no, go with original functionality of retag 
                    if [[ -z "${RETAG_SPECIFIC_TAG_TO_PUSH}" ]]
                    then
                        # If the tag has a . in it, it means is a SemVer version tag, else is a SHA
                        if [[ ${tag} == *"."* ]]; then
                            IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image}:${RETAG_SEMVER_TO_PUSH}"
                        else
                            IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image}:${RETAG_SHA_TO_PUSH}"
                        fi
                    else
                        # Add prefix if required
                        if [[ -z "${RETAG_PREFIX_TO_IMAGE}" ]]
                        then
                            IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image}:${RETAG_SPECIFIC_TAG_TO_PUSH}"
                        else
                            IMAGE_TO_PUSH="${PUSH_REGISTRY}/${RETAG_PREFIX_TO_IMAGE}/${image}:${RETAG_SPECIFIC_TAG_TO_PUSH}"
                        fi
                    fi
                else
                    IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image}:${tag}"
                fi

                echo "Will pull ${IMAGE_TO_PULL} and push ${IMAGE_TO_PUSH}"
                # If we have some value in ICR_PUSH_REGISTRY_REGION; ensure we are targeted against that region before pushing
                if [[ ! -z "${ICR_PUSH_REGISTRY_REGION}" ]]
                then
                    echo "Will change IBM Cloud target to ${ICR_PUSH_REGISTRY_REGION}"
                    ibmcloud target -r ${ICR_PUSH_REGISTRY_REGION}
                    ibmcloud cr login
                fi
                inspect_result=$(docker manifest inspect ${IMAGE_TO_PUSH}-${architecture} ${insecure_flag})
                statusCode=$?
                set -e
                if [[ "${statusCode}" -ne 0 ]]; then
                    echo "Image tag was not found, continue pushing to ${PUSH_REGISTRY}"
                    # If we have some value in ICR_PULL_REGISTRY_REGION; ensure we are targeted against that region before pulling
                    if [[ ! -z "${ICR_PULL_REGISTRY_REGION}" ]]
                    then
                        echo "Will change IBM Cloud target to ${ICR_PULL_REGISTRY_REGION}"
                        ibmcloud target -r ${ICR_PULL_REGISTRY_REGION}
                        ibmcloud cr login
                    fi

                    if docker pull ${IMAGE_TO_PULL} --platform ${architecture}; then
                        docker tag ${IMAGE_TO_PULL} ${IMAGE_TO_PUSH}-${architecture}
                        if [[ $COPY_IMAGES_DRY_RUN_MODE = true ]]; then
                            echo "DRY RUN MODE !!! - We would have run: docker push ${IMAGE_TO_PUSH}-${architecture}"
                        else
                            # If we have some value in ICR_PUSH_REGISTRY_REGION; ensure we are targeted against that region before pushing
                            if [[ ! -z "${ICR_PUSH_REGISTRY_REGION}" ]]
                            then
                                echo "Will change IBM Cloud target to ${ICR_PUSH_REGISTRY_REGION}"
                                ibmcloud target -r ${ICR_PUSH_REGISTRY_REGION}
                                ibmcloud cr login
                            fi
                            docker push ${IMAGE_TO_PUSH}-${architecture}
                            if [[ "${VERIFY_COPIED_IMAGES_CAN_BE_PULLED}" == "true" ]]
                            then
                                echo "${IMAGE_TO_PUSH}-${architecture}" >> "tmp_images_to_verify.txt"
                            fi
                        fi
                        docker rmi ${IMAGE_TO_PUSH}-${architecture}
                        docker rmi ${IMAGE_TO_PULL}
                    else
                        echo "ERROR: Image pull failed or image does not exist in ${PULL_REGISTRY}"
                        exit 1
                    fi
                else
                    echo "WARNING: Image tag was found, skipping the push to ${PUSH_REGISTRY}"
                fi
                #create and push manifest (separate manifest creation from docker manifest inspect ${IMAGE_TO_PUSH}-${architecture} ${insecure_flag}
                manifest_name="${IMAGE_TO_PUSH}"
                manifest_params="${manifest_name}"
                manifest_params="${manifest_params} ${IMAGE_TO_PUSH}-${architecture}" # Add the re-tagged image to the variable used to make the manifest file
                if [[ $COPY_IMAGES_DRY_RUN_MODE = true ]]; then
                    echo "DRY RUN MODE !!! - We would have run: docker manifest create ${certificate_insecure_flag} ${manifest_params}"
                    echo "DRY RUN MODE !!! - We would have run: docker manifest push ${certificate_insecure_flag} ${manifest_name}"
                else
                    if [[ $COPY_IMAGES_SKIP_MANIFESTS = true ]]; then
                        echo "Skipping manifests copy"
                    else
                        set +e
                        docker buildx imagetools inspect ${manifest_name} >/dev/null 2>&1
                        rc=$?
                        echo "buildx rc: $rc"
                        set -e
                        #manifest not exist
                        if [[ "${rc}" -ne 0 ]]; then
                            docker manifest create ${certificate_insecure_flag} ${manifest_params}
                            # If we have some value in ICR_PUSH_REGISTRY_REGION; ensure we are targeted against that region before pushing
                            if [[ ! -z "${ICR_PUSH_REGISTRY_REGION}" ]]
                            then
                                echo "Will change IBM Cloud target to ${ICR_PUSH_REGISTRY_REGION}"
                                ibmcloud target -r ${ICR_PUSH_REGISTRY_REGION}
                                ibmcloud cr login
                            fi
                            docker manifest push ${certificate_insecure_flag} ${manifest_name}
                            rc=$?
                            echo "manifest push rc: $rc"
                            if [[ "${rc}" -eq 0 ]]; then
                                echo "Successfuly pushed manifest  ${manifest_name}"
                            else
                                echo "ERROR: Manifest  ${manifest_name} push failed"
                                exit 1
                            fi
                        else
                            echo "WARNING: Manifest ${manifest_name} already exist on remote "
                        fi
                    fi
                fi
                successful_image_uploads=$(($successful_image_uploads + 1))
            done
            if [ "$successful_image_uploads" -lt "1" ]; then
                echo "Images not found on ${PULL_REGISTRY} for any of the following tags: ${tags}"
                exit 1
            fi
        done
    else
        echo "No images to push for amd64 arch"
    fi
}

# logic for no-arch images (single platform, no architecture suffix)
function process_no_arch(){
    if [[ ${images_no_arch} != "" ]]; then
        echo "image artifact(s) for push (no-arch): ${images_no_arch}"
        for image in ${images_no_arch}
        do
            successful_image_uploads=0
            for tag in $tags; do
                set +e
                IMAGE_TO_PULL="${PULL_REGISTRY}/${image}:${tag}"
                # First check if we are in retag mode at all
                if [[ $COPY_IMAGES_RETAG_MODE = true ]]; then
                    # Here check if we got a specific tag to push; if yes, prefer it; if no, go with original functionality of retag
                    if [[ -z "${RETAG_SPECIFIC_TAG_TO_PUSH}" ]]
                    then
                        # If the tag has a . in it, it means is a SemVer version tag, else is a SHA
                        if [[ ${tag} == *"."* ]]; then
                            IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image}:${RETAG_SEMVER_TO_PUSH}"
                        else
                            IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image}:${RETAG_SHA_TO_PUSH}"
                        fi
                    else
                        # Add prefix if required
                        if [[ -z "${RETAG_PREFIX_TO_IMAGE}" ]]
                        then
                            IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image}:${RETAG_SPECIFIC_TAG_TO_PUSH}"
                        else
                            IMAGE_TO_PUSH="${PUSH_REGISTRY}/${RETAG_PREFIX_TO_IMAGE}/${image}:${RETAG_SPECIFIC_TAG_TO_PUSH}"
                        fi
                    fi
                else
                    IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image}:${tag}"
                fi

                echo "Will pull ${IMAGE_TO_PULL} and push ${IMAGE_TO_PUSH} (no-arch)"
                # If we have some value in ICR_PUSH_REGISTRY_REGION; ensure we are targeted against that region before pushing
                if [[ ! -z "${ICR_PUSH_REGISTRY_REGION}" ]]
                then
                    echo "Will change IBM Cloud target to ${ICR_PUSH_REGISTRY_REGION}"
                    ibmcloud target -r ${ICR_PUSH_REGISTRY_REGION}
                    ibmcloud cr login
                fi
                inspect_result=$(docker manifest inspect ${IMAGE_TO_PUSH} ${insecure_flag})
                statusCode=$?
                set -e
                if [[ "${statusCode}" -ne 0 ]]; then
                    echo "Image tag was not found, continue pushing to ${PUSH_REGISTRY}"
                    # If we have some value in ICR_PULL_REGISTRY_REGION; ensure we are targeted against that region before pulling
                    if [[ ! -z "${ICR_PULL_REGISTRY_REGION}" ]]
                    then
                        echo "Will change IBM Cloud target to ${ICR_PULL_REGISTRY_REGION}"
                        ibmcloud target -r ${ICR_PULL_REGISTRY_REGION}
                        ibmcloud cr login
                    fi

                    # Pull without --platform flag for no-arch images
                    if docker pull ${IMAGE_TO_PULL}; then
                        docker tag ${IMAGE_TO_PULL} ${IMAGE_TO_PUSH}
                        if [[ $COPY_IMAGES_DRY_RUN_MODE = true ]]; then
                            echo "DRY RUN MODE !!! - We would have run: docker push ${IMAGE_TO_PUSH}"
                        else
                            # If we have some value in ICR_PUSH_REGISTRY_REGION; ensure we are targeted against that region before pushing
                            if [[ ! -z "${ICR_PUSH_REGISTRY_REGION}" ]]
                            then
                                echo "Will change IBM Cloud target to ${ICR_PUSH_REGISTRY_REGION}"
                                ibmcloud target -r ${ICR_PUSH_REGISTRY_REGION}
                                ibmcloud cr login
                            fi
                            docker push ${IMAGE_TO_PUSH}
                            if [[ "${VERIFY_COPIED_IMAGES_CAN_BE_PULLED}" == "true" ]]
                            then
                                echo "${IMAGE_TO_PUSH}" >> "tmp_images_to_verify.txt"
                            fi
                        fi
                        docker rmi ${IMAGE_TO_PUSH}
                        docker rmi ${IMAGE_TO_PULL}
                    else
                        echo "ERROR: Image pull failed or image does not exist in ${PULL_REGISTRY}"
                        exit 1
                    fi
                else
                    echo "WARNING: Image tag was found, skipping the push to ${PUSH_REGISTRY}"
                fi
                successful_image_uploads=$(($successful_image_uploads + 1))
            done
            if [ "$successful_image_uploads" -lt "1" ]; then
                echo "Images not found on ${PULL_REGISTRY} for any of the following tags: ${tags}"
                exit 1
            fi
        done
    else
        echo "No images to push for no-arch"
    fi
}

# logic for multi-arch images
function process_multi_arch(){
    # Check that there are images defined for multi-arch
    if [[ ${images_multi_arch} != "" ]]; then
        echo "image artifact(s) for push: ${images_multi_arch}"
        for image in ${images_multi_arch}
        do
            successful_manifest_inspections=0
            for tag in $tags; do
                # Get manifest to setup the loop
                echo "Attempting to get manifest"
                set +e
                manifest_error=false
                IMAGE_TO_PULL="${PULL_REGISTRY}/${image}:${tag}"
                # First check if we are in retag mode at all
                if [[ $COPY_IMAGES_RETAG_MODE = true ]]; then
                    # Here check if we got a specific tag to push; if yes, prefer it; if no, go with original functionality of retag 
                    if [[ -z "${RETAG_SPECIFIC_TAG_TO_PUSH}" ]]
                    then
                        # If the tag has a . in it, it means is a SemVer version tag, else is a SHA
                        if [[ ${tag} == *"."* ]]; then
                            IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image}:${RETAG_SEMVER_TO_PUSH}"
                        else
                            IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image}:${RETAG_SHA_TO_PUSH}"
                        fi
                    else
                        # Add prefix if required
                        if [[ -z "${RETAG_PREFIX_TO_IMAGE}" ]]
                        then
                            IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image}:${RETAG_SPECIFIC_TAG_TO_PUSH}"
                        else
                            IMAGE_TO_PUSH="${PUSH_REGISTRY}/${RETAG_PREFIX_TO_IMAGE}/${image}:${RETAG_SPECIFIC_TAG_TO_PUSH}"
                        fi
                    fi
                else
                    IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image}:${tag}"
                fi
                echo "Will pull ${IMAGE_TO_PULL} and push ${IMAGE_TO_PUSH}"
                # If we have some value in ICR_PULL_REGISTRY_REGION; ensure we are targeted against that region before pulling
                if [[ ! -z "${ICR_PULL_REGISTRY_REGION}" ]]
                then
                    echo "Will change IBM Cloud target to ${ICR_PULL_REGISTRY_REGION}"
                    ibmcloud target -r ${ICR_PULL_REGISTRY_REGION}
                    ibmcloud cr login
                fi
                manifest=$(docker manifest inspect ${IMAGE_TO_PULL} ${insecure_flag} 2>&1)
                if [[ $? == 0 ]]; then
                    echo "Got manifest successfully"
                    successful_manifest_inspections=$(($successful_manifest_inspections + 1))
                    architectures=$(echo "${manifest}" | jq -r "${JQ_REGEX_MANIFEST_ARCHITECTURES}")
                    if [[ $? != 0 ]];  then
                        echo "Error when trying to use jq to determine architectures"
                        exit 1 # There must be a manifest for multi_arch images
                    fi
                else
                    echo "WARNING: Unable to pull manifest; error message was: ${manifest}"
                    manifest_error=true
                    continue
                fi
                set -e

                manifest_name="${IMAGE_TO_PUSH}"
                manifest_params="${manifest_name}"
                image_uploaded=false
                for architecture in ${architectures};
                do
                    set +e
                    # If we have some value in ICR_PUSH_REGISTRY_REGION; ensure we are targeted against that region before pushing
                    if [[ ! -z "${ICR_PUSH_REGISTRY_REGION}" ]]
                    then
                        echo "Will change IBM Cloud target to ${ICR_PUSH_REGISTRY_REGION}"
                        ibmcloud target -r ${ICR_PUSH_REGISTRY_REGION}
                        ibmcloud cr login
                    fi
                    inspect_result=$(docker manifest inspect ${IMAGE_TO_PUSH}-${architecture} ${insecure_flag})
                    statusCode=$?
                    set -e
                    if [[ "${statusCode}" -ne 0 ]]; then
                        echo "Image tag was not found, continue pushing to ${PUSH_REGISTRY}"
                        # If we have some value in ICR_PULL_REGISTRY_REGION; ensure we are targeted against that region before pulling
                        if [[ ! -z "${ICR_PULL_REGISTRY_REGION}" ]]
                        then
                            echo "Will change IBM Cloud target to ${ICR_PULL_REGISTRY_REGION}"
                            ibmcloud target -r ${ICR_PULL_REGISTRY_REGION}
                            ibmcloud cr login
                        fi
                        if docker pull ${IMAGE_TO_PULL} --platform ${architecture}; then
                            docker tag ${IMAGE_TO_PULL} ${IMAGE_TO_PUSH}-${architecture}
                            if [[ $COPY_IMAGES_DRY_RUN_MODE = true ]]; then
                                echo "DRY RUN MODE !!! - We would have run: docker push ${IMAGE_TO_PUSH}-${architecture}"
                            else
                                # If we have some value in ICR_PUSH_REGISTRY_REGION; ensure we are targeted against that region before pushing
                                if [[ ! -z "${ICR_PUSH_REGISTRY_REGION}" ]]
                                then
                                    echo "Will change IBM Cloud target to ${ICR_PUSH_REGISTRY_REGION}"
                                    ibmcloud target -r ${ICR_PUSH_REGISTRY_REGION}
                                    ibmcloud cr login
                                fi
                                docker push ${IMAGE_TO_PUSH}-${architecture}
                                if [[ "${VERIFY_COPIED_IMAGES_CAN_BE_PULLED}" == "true" ]]
                                then
                                    echo "${IMAGE_TO_PUSH}-${architecture}" >> "tmp_images_to_verify.txt"
                                fi
                            fi
                            image_uploaded=true
                            docker rmi ${IMAGE_TO_PUSH}-${architecture}
                            docker rmi ${IMAGE_TO_PULL}
                        else
                            echo "ERROR: Image pull failed or image does not exist in ${PULL_REGISTRY}"
                            exit 1
                        fi
                    else
                        echo "WARNING: Image tag was found, skipping the push to ${PUSH_REGISTRY}"
                    fi
                    manifest_params="${manifest_params} ${IMAGE_TO_PUSH}-${architecture}" # Add the re-tagged image to the variable used to make the manifest file
                done
                # Check if we uploaded at least one image. If we did, create (or update) the manifest.
                if [[ "${image_uploaded}" ]] || [[ "${manifest_error}" == "true" ]]; then
                    if [[ $COPY_IMAGES_DRY_RUN_MODE = true ]]; then
                        echo "DRY RUN MODE !!! - We would have run: docker manifest create ${certificate_insecure_flag} ${manifest_params}"
                        echo "DRY RUN MODE !!! - We would have run: docker manifest push ${certificate_insecure_flag} ${manifest_name}"
                    else
                        if [[ $COPY_IMAGES_SKIP_MANIFESTS = true ]]; then
                            echo "Skipping manifests copy"
                        else
                            docker manifest create ${certificate_insecure_flag} ${manifest_params}
                            docker manifest push ${certificate_insecure_flag} ${manifest_name}
                        fi
                    fi
                fi
            done
            if [ "$successful_manifest_inspections" -lt "1" ]; then
                echo "Manifest not found for any of the following tags: ${tags}"
                exit 1
            fi
        done
    else
        echo "No images to push for multi-arch"
    fi
}

# This function has highest priority when IMAGES_AND_MANIFESTS_TO_COPY is set; therefore this function will run
# first (and last) in that case.This function copies images specified in a list (comma-separated is accepted,
# recommended as well to keep format consistent) by taking a list in the var IMAGES_AND_MANIFESTS_TO_COPY, and
# searching the PULL_REGISTRY for that image. If it is found, it will copy it to the PUSH_REGISTRY location,
# using a manifest if it was specified, and creating a new one based on the new location

# This function also allows to push with a different tag than we pull and also to add a prefix to the image we push
function process_specified(){
    IMAGE_LIST=$1
    login_registries

    set +x # Turn off verbose mode - will avoid a large amount of output from doing operations on the manifests
    for image in $(cat "${IMAGE_LIST}")
    do
        # -d ':'    - split the string at the ":",
        # -f        - get the substring element (starting at 1, not 0)
        image_path=$(echo "${image}" | cut -d ':' -f 1)
        image_tag=$(echo "${image}" | cut -d ':' -f 2)
        IMAGE_TO_PULL="${PULL_REGISTRY}/${image_path}:${image_tag}"
        # First check if we are in retag mode at all
        if [[ $COPY_IMAGES_RETAG_MODE = true ]]; then
            # Here check if we got a specific tag to push; if yes, prefer it; if no, go with original functionality of retag
            echo "COPY_IMAGES_RETAG_MODE: ${COPY_IMAGES_RETAG_MODE} - entering retag mode"
            if [[ -z "${RETAG_SPECIFIC_TAG_TO_PUSH}" ]]
            then
                echo "RETAG_SPECIFIC_TAG_TO_PUSH: ${RETAG_SPECIFIC_TAG_TO_PUSH} - use standard retag"
                # If the tag has a . in it, it means is a SemVer version tag, else is a SHA
                if [[ ${image_tag} == *"."* ]]; then
                    IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image_path}:${RETAG_SEMVER_TO_PUSH}"
                else
                    IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image_path}:${RETAG_SHA_TO_PUSH}"
                fi
            else
                echo "RETAG_SPECIFIC_TAG_TO_PUSH: ${RETAG_SPECIFIC_TAG_TO_PUSH} - use specific tag"
                # Add prefix if required
                if [[ -z "${RETAG_PREFIX_TO_IMAGE}" ]]
                then
                    echo "RETAG_PREFIX_TO_IMAGE: ${RETAG_PREFIX_TO_IMAGE} - no prefix"
                    IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image_path}:${RETAG_SPECIFIC_TAG_TO_PUSH}"
                else
                    echo "RETAG_PREFIX_TO_IMAGE: ${RETAG_PREFIX_TO_IMAGE} - prefix added"
                    IMAGE_TO_PUSH="${PUSH_REGISTRY}/${RETAG_PREFIX_TO_IMAGE}/${image_path}:${RETAG_SPECIFIC_TAG_TO_PUSH}"
                fi
            fi
        else
            echo "COPY_IMAGES_RETAG_MODE: ${COPY_IMAGES_RETAG_MODE} - not retag mode"
            IMAGE_TO_PUSH="${PUSH_REGISTRY}/${image_path}:${image_tag}"
        fi

        echo "************************************************************"
        # if DO_NOT_OVERWRITE is true, skip pushing the image if it exists
        if [[ -n "${DO_NOT_OVERWRITE:-}" ]] && [[ "${DO_NOT_OVERWRITE:-}" == "true" ]]; then
            # If we have some value in ICR_PUSH_REGISTRY_REGION; ensure we are targeted against that region before inspecting
            echo "DO_NOT_OVERWRITE: ${DO_NOT_OVERWRITE} - do not overwrite mode, checking if image exist by inspecting manifest"
            if [[ ! -z "${ICR_PUSH_REGISTRY_REGION}" ]]
            then
                echo "Will change IBM Cloud target to ${ICR_PUSH_REGISTRY_REGION}"
                ibmcloud target -r ${ICR_PUSH_REGISTRY_REGION}
                ibmcloud cr login
            fi
            image_exists=$(docker manifest inspect ${IMAGE_TO_PUSH} > /dev/null ; echo $?)
            if [[ ${image_exists} == 0 ]]; then
                echo "Found already existing image ${IMAGE_TO_PUSH}. Skip pushing..."
                continue    # Will continue the loop and not execute the rest of the function for this image
            fi
        fi
        echo "Processing image: ${image}"
        set +e
        # If we have some value in ICR_PULL_REGISTRY_REGION; ensure we are targeted against that region before pulling
        if [[ ! -z "${ICR_PULL_REGISTRY_REGION}" ]]
        then
            echo "Will change IBM Cloud target to ${ICR_PULL_REGISTRY_REGION}"
            ibmcloud target -r ${ICR_PULL_REGISTRY_REGION}
            ibmcloud cr login
        fi
        echo "checking image manifest for image to pull: ${IMAGE_TO_PULL}"
        manifest=$(docker manifest inspect ${IMAGE_TO_PULL} ${insecure_flag} 2>&1)
        statusCode=$?
        set -e
        if [[ "${statusCode}" == 0 ]]; then
            echo "Got target manifest successfully"
            # Get the manifest type - anything in a registry will have a manifest, but it may not contain the information we're looking for
            target_type=$(echo "${manifest}" | jq -r "${JQ_REGEX_TYPE_FIELD}")
            # if the manifest indicates it is a manifest, then get the architectures


            echo "Will pull ${IMAGE_TO_PULL} and push ${IMAGE_TO_PUSH}"
            if [[ "${target_type}" == *"${JQ_REGEX_MANIFEST_TYPE}"* ]] && [[ $(echo "$manifest" | jq '.manifests') != "null" ]]; then
                echo "target determined to be a manifest"
                architectures=$(echo "${manifest}" | jq -r "${JQ_REGEX_MANIFEST_ARCHITECTURES}")
                manifest_name="${IMAGE_TO_PUSH}"
                manifest_params="${manifest_name}"
                echo "found image architectures: ${architectures}"
                for architecture in ${architectures};
                do
                    echo "Processing architecture ${architecture} for image"
                    # If we have some value in ICR_PULL_REGISTRY_REGION; ensure we are targeted against that region before pulling
                    if [[ ! -z "${ICR_PULL_REGISTRY_REGION}" ]]
                    then
                        echo "Will change IBM Cloud target to ${ICR_PULL_REGISTRY_REGION}"
                        ibmcloud target -r ${ICR_PULL_REGISTRY_REGION}
                        ibmcloud cr login
                    fi
                    echo "pulling ${IMAGE_TO_PULL} --platform ${architecture} "
                    docker pull ${IMAGE_TO_PULL} --platform ${architecture}
                    echo "tagging ${IMAGE_TO_PULL} ${IMAGE_TO_PUSH}-${architecture}"
                    docker tag ${IMAGE_TO_PULL} ${IMAGE_TO_PUSH}-${architecture}
                    if [[ $COPY_IMAGES_DRY_RUN_MODE = true ]]; then
                        echo "DRY RUN MODE !!! - We would have run: docker push ${IMAGE_TO_PUSH}-${architecture}"
                    else
                        # If we have some value in ICR_PUSH_REGISTRY_REGION; ensure we are targeted against that region before pushing
                        if [[ ! -z "${ICR_PUSH_REGISTRY_REGION}" ]]
                        then
                            echo "Will change IBM Cloud target to ${ICR_PUSH_REGISTRY_REGION}"
                            ibmcloud target -r ${ICR_PUSH_REGISTRY_REGION}
                            ibmcloud cr login
                        fi
                        echo "pushing ${IMAGE_TO_PUSH}-${architecture}"
                        docker push ${IMAGE_TO_PUSH}-${architecture}
                        if [[ "${VERIFY_COPIED_IMAGES_CAN_BE_PULLED}" == "true" ]]
                        then
                            echo "${IMAGE_TO_PUSH}-${architecture}" >> "tmp_images_to_verify.txt"
                        fi
                    fi
                    echo "removing pushed image: ${IMAGE_TO_PUSH}-${architecture}"
                    docker rmi ${IMAGE_TO_PUSH}-${architecture}
                    echo "removing pulled image: ${IMAGE_TO_PULL}"
                    docker rmi ${IMAGE_TO_PULL}
                    manifest_params="${manifest_params} ${IMAGE_TO_PUSH}-${architecture}" # Add the re-tagged image to the variable used to make the manifest file
                done
                echo "creating & pushing manifest..."


                if [[ $COPY_IMAGES_DRY_RUN_MODE = true ]]; then
                    echo "DRY RUN MODE !!! - We would have run: docker manifest create ${certificate_insecure_flag} ${manifest_params}"
                    echo "DRY RUN MODE !!! - We would have run: docker manifest push ${certificate_insecure_flag} ${manifest_name}"
                else
                    if [[ $COPY_IMAGES_SKIP_MANIFESTS = true ]]; then
                        echo "Skipping manifests copy"
                    else
                        echo "create manifest with: ${certificate_insecure_flag} ${manifest_params}"
                        docker manifest create ${certificate_insecure_flag} ${manifest_params}
                        docker manifest push ${certificate_insecure_flag} ${manifest_name}
                    fi
                fi
                echo "manifest pushed"
                # if the manifest indicates the target is an "image", then pull, re-tag, push, remove local image (don't create a manifest)
                # The check below is also effectively ensures that it isn't 'null', as 'null' isn't a substring of the string we're searching for
            elif [[ $(echo "${manifest}" | jq "${JQ_REGEX_CONFIG_MEDIA_TYPE}") == *"docker.container.image"* ]]; then
                echo ">>>>> target determined to be an image <<<<<<"
                # If we have some value in ICR_PULL_REGISTRY_REGION; ensure we are targeted against that region before pulling
                if [[ ! -z "${ICR_PULL_REGISTRY_REGION}" ]]
                then
                    echo "Will change IBM Cloud target to ${ICR_PULL_REGISTRY_REGION}"
                    ibmcloud target -r ${ICR_PULL_REGISTRY_REGION}
                    ibmcloud cr login
                fi
                echo "pulling ${IMAGE_TO_PULL} "
                docker pull ${IMAGE_TO_PULL}
                echo "tagging ${IMAGE_TO_PULL} ${IMAGE_TO_PUSH}"
                docker tag ${IMAGE_TO_PULL} ${IMAGE_TO_PUSH}
                if [[ $COPY_IMAGES_DRY_RUN_MODE = true ]]; then
                    echo "DRY RUN MODE !!! - We would have run: docker push ${IMAGE_TO_PUSH}"
                else
                    # If we have some value in ICR_PUSH_REGISTRY_REGION; ensure we are targeted against that region before pushing
                    if [[ ! -z "${ICR_PUSH_REGISTRY_REGION}" ]]
                    then
                        echo "Will change IBM Cloud target to ${ICR_PUSH_REGISTRY_REGION}"
                        ibmcloud target -r ${ICR_PUSH_REGISTRY_REGION}
                        ibmcloud cr login
                    fi
                    echo "pushing ${IMAGE_TO_PUSH}"
                    docker push ${IMAGE_TO_PUSH}
                    if [[ "${VERIFY_COPIED_IMAGES_CAN_BE_PULLED}" == "true" ]]
                    then
                        echo "${IMAGE_TO_PUSH}" >> "tmp_images_to_verify.txt"
                    fi
                fi
                echo "removing pushed image: ${IMAGE_TO_PUSH}"
                docker rmi ${IMAGE_TO_PUSH}
            else
                echo "Error: Manifest was neither a manifest (e.g. manifest of manifests) nor an image. printing manifest and exiting:"
                echo "${manifest}"
                exit 1
            fi
        else
            echo "Unable to pull manifest; error message was: ${manifest}"
            if [[ ${FAIL_ON_IMAGE_PULL_FAILURE} == "false" ]]; then
                echo "Skipping ${image}"
            else
                exit 1
            fi
        fi
    done
}

function login_registries(){
    # Login to registries if we have both login credentials (user/pass), otherwise assume the registries don't need them
    options=$-
    set +x  # so we don't log the password
    insecure_flag="" # Instantiate var so we don't exit on var being unset; value is set (if it should be) via check_insecure function
    if [[ ! -z ${PULL_REGISTRY_USER} && ${PULL_REGISTRY_PASSWORD} ]]; then
        echo "Logging into pull registry ${PULL_REGISTRY}"
        echo ${PULL_REGISTRY_PASSWORD} | docker login ${PULL_REGISTRY} -u ${PULL_REGISTRY_USER} --password-stdin
    elif [[ ! -z ${PULL_REGISTRY_API_KEY} ]]; then
        echo "Logging into pull registry ${PULL_REGISTRY}"
        echo "Setting con_key_file for ibmcloud login"
        set +x
        # Login to ibmcloud using function defined in ibmcloud_utils.sh
        ibmcloud_login "${PULL_REGISTRY_API_KEY}"
        set -x
        ibmcloud cr login
    else
        echo "Failed to find credentials to authenticate with pull registry ${PULL_REGISTRY}"
        check_insecure
    fi
    if [[ ! -z ${PUSH_REGISTRY_USER} && ${PUSH_REGISTRY_PASSWORD} ]]; then
        echo "Logging into push registry ${PUSH_REGISTRY}"
        echo ${PUSH_REGISTRY_PASSWORD} | docker login ${PUSH_REGISTRY} -u ${PUSH_REGISTRY_USER} --password-stdin
    elif [[ ! -z ${PUSH_REGISTRY_API_KEY} ]]; then
        echo "Logging into push registry ${PUSH_REGISTRY}"
        echo "Setting con_key_file for ibmcloud login"
        set +x
        # Login to ibmcloud using function defined in ibmcloud_utils.sh
        ibmcloud_login "${PUSH_REGISTRY_API_KEY}"
        set -x
        ibmcloud cr login
    else
        echo "Failed to find credentials to authenticate with push registry ${PUSH_REGISTRY}"
        check_insecure
    fi
    if [[ $(echo "$options") == *"x"* ]]; then
        set -x
    fi
}

function ensure_copied_images_can_be_pulled(){
    echo "** Will verify if we can pull the following images ***"
    cat "tmp_images_to_verify.txt"

    while read img || [ -n "$img" ]
    do 
        echo "Processing image ${img}"
        echo "First, delete all local images"
        docker rmi -f $(docker images -a -q) || echo "Found no local images"
        echo "Trying a fresh pull of ${img}..."
        # If we have some value in ICR_PUSH_REGISTRY_REGION means during the copy we pushed to a specific region
        # Now we are verifying if we can pull so we need to work with the region which we pushed to
        if [[ ! -z "${ICR_PUSH_REGISTRY_REGION}" ]]
        then
            echo "Will change IBM Cloud target to ${ICR_PUSH_REGISTRY_REGION}"
            ibmcloud target -r ${ICR_PUSH_REGISTRY_REGION}
            ibmcloud cr login
        fi
        retry docker pull "${img}"
    done < "${PWD}/tmp_images_to_verify.txt"

    # After we finish the verification, remove the file
    rm -rf "${PWD}/tmp_images_to_verify.txt"
}

################################### execution starts here ##############
# Create an empty file
if [[ "${VERIFY_COPIED_IMAGES_CAN_BE_PULLED}" == "true" ]]
then
    touch "tmp_images_to_verify.txt"
fi

if [[ ${COPY_IMAGES_ENABLED} == "false" ]]; then
    echo Skip pushing to registry ${PUSH_REGISTRY}. Exit...
    exit 0
fi

# the copy images from the file list (like third-party)
if [[ -d ${PATH_TO_IMAGES_TO_COPY} ]]; then
    echo "Found the directory containing the image list, skipping meta-build based approach"
    echo "*** The following images will be copied from ${PULL_REGISTRY} to ${PUSH_REGISTRY} ***"
    cat "${PATH_TO_IMAGES_TO_COPY}/final_image_list.txt"
    process_specified ${PATH_TO_IMAGES_TO_COPY}/final_image_list.txt
    if [[ "${VERIFY_COPIED_IMAGES_CAN_BE_PULLED}" == "true" ]]
    then
        ensure_copied_images_can_be_pulled
    fi
    exit 0
fi

# Check if the workspace-repo was provided as an input
if [[ -d ${PATH_TO_WORKSPACE_REPO} ]]; then
    # First check if we are in retag mode at all
    if [[ $COPY_IMAGES_RETAG_MODE = true ]]; then
        # Here check if we got specific tags to pull; if yes, prefer them; if no, go with original functionality
        # we use the tag and the sem.  vet. as a defined parameters or use the specific defined tag
        if [[ -z "${RETAG_SPECIFIC_TAGS_TO_PULL}" ]]
        then
            echo "We are going to use tag: ${RETAG_SHA_TO_PULL} and sem. ver. ${RETAG_SEMVER_TO_PULL}"
            tags="${RETAG_SHA_TO_PULL} ${RETAG_SEMVER_TO_PULL}"
        else
            echo "We are going to use specisal tag: ${RETAG_SPECIFIC_TAGS_TO_PULL}"
            tags="${RETAG_SPECIFIC_TAGS_TO_PULL}"
        fi
    else
        echo "Get the image tag"
        pushd ${PATH_TO_WORKSPACE_REPO}
        git_sha=$(git log -1 --format=%H)
        git_tag=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true
        tags="${git_sha} ${git_tag}"
        popd
    fi
else
    echo "ERROR: Path ${PATH_TO_WORKSPACE_REPO} path does not exist, but the operation being used requires that var to be set"
    exit 1
fi

# Verify that the file defining build metadata exists
if [[ -f "${PATH_TO_WORKSPACE_REPO}/hack/ci/${build_meta_file}" ]]; then
    echo "${build_meta_file} file found in repository!"
    # Verify that there is at least one image to upload for at least one architecture/group (non-zero)
    if [[ $(yq -r '{images}[]' ${PATH_TO_WORKSPACE_REPO}/hack/ci/${build_meta_file} -y -w 512 | grep -v ": null$") ]]; then
      echo "Success; An image was defined for one or more architecture(s)";

      # Get the images we need to push, store them in a bash-iterable variable. Filter out "null".
      images_multi_arch=$(yq -r '.images.multi_arch | select(. != null) | if type=="string" then . else .[] end' ${PATH_TO_WORKSPACE_REPO}/hack/ci/${build_meta_file})
      images_amd64=$(yq -r '.images.amd64 | select(. != null) | if type=="string" then . else .[] end' ${PATH_TO_WORKSPACE_REPO}/hack/ci/${build_meta_file})
      images_no_arch=$(yq -r '.images.no_arch | select(. != null) | if type=="string" then . else .[] end' ${PATH_TO_WORKSPACE_REPO}/hack/ci/${build_meta_file})
      login_registries
      process_amd64
      process_multi_arch
      process_no_arch
    else
      echo "Error encountered; The \"${build_meta_file}\" file did not contain any values for any architecture under images. "
      exit 1
    fi
else
    # If there isn't a build-meta.yaml file, see if either of vars specifying images to copy are set, and if so proceed with those values.
    # If those values are not set, exit with an error.
    if [[ ! -z ${IMAGES_TO_COPY_AMD64} || ${IMAGES_TO_COPY_MULTI_ARCH} ]]; then
        echo "WARNING: Images to upload were defined in the pipeline file instead of in a build-meta.yaml file"
        echo "WARNING: If this is a genctl repo, please update the repository to contain a build-meta.yaml instead of specifying in the pipeline file itself"
        echo "Setting variables from pipeline configuration"
        if [[ ${IMAGES_TO_COPY_AMD64} == "null" ]]; then
            images_amd64=""
        else
            images_amd64=${IMAGES_TO_COPY_AMD64}
        fi
        if [[ ${IMAGES_TO_COPY_MULTI_ARCH} == "null" ]]; then
            images_multi_arch=""
        else
            images_multi_arch=${IMAGES_TO_COPY_MULTI_ARCH}
        fi
        if [[ ${IMAGES_TO_COPY_NO_ARCH} == "null" ]]; then
            images_no_arch=""
        else
            images_no_arch=${IMAGES_TO_COPY_NO_ARCH}
        fi
        login_registries
        process_amd64
        process_multi_arch
        process_no_arch
    else
        echo "Error: Did not find a ${build_meta_file} file under the repository's hack/ci directory"
        exit 1
    fi
fi

# If required, check that everything we pushed can be pulled
if [[ "${VERIFY_COPIED_IMAGES_CAN_BE_PULLED}" == "true" ]]
then
    ensure_copied_images_can_be_pulled
fi
echo "Script completed successfully"
