#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2019
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# This bash requires the following values to be set:

#  PATH_TO_GENCTL_CI
#  PATH_TO_WORKSPACE_REPO
#  PATH_TO_RELEASE_ENVIRONMENT {OPTIONAL}
#  ARTIFACTORY_DOCKER_URL:
#  IBMCLOUD_URL:
#  IBMCLOUD_KEY:
#  IMAGE_LIST: {OPTIONAL}
#  IMAGE_TAGS: {OPTIONAL}
#  OPERATION:
#  SKIP_FLAG: {OPTIONAL}
#  CC_ARTIF_ACCESS_TOKEN:
#  WCP_ARTIFACTORY_USERNAME:

function check_tag_exists {
    # If the image exists the flag should be set to true in order to skip the current image push to ICCR
    SKIP_PUSH_FLAG=false
    DOCKER_TAG=$1
    # This function can fail if the image is not in ICCR and that's ok, if the image does not exist we continue to push the image.
    echo -n "Checking if image $image:${DOCKER_TAG}${ARCH_TYPE} exists in ICCR"
    # Retry the image-inspect command to mitigate connection issues
    for i in {1..2}; do
        set +e # Allow the command to fail if image does not exist.
        result=$(ibmcloud cr image-inspect ${DOCKER_PUSH_URL}/$image:${DOCKER_TAG}${ARCH_TYPE})
        statusCode=$?
        set -e
        if [[ "${statusCode}" -ne 0 ]]; then
            if [[ ${i} -ne 2 ]]; then
                echo -n "."
                sleep 5
            fi
        else
            # Inspecting the image succeeded, the image tag exists in ICCR, change the flag to skip the push
            SKIP_PUSH_FLAG=true
            break
        fi
    done
}

function docker_pull_and_push() {
    # Arguments expected:
    # 1 - A space-delimited list of image names - example: "rias/regional-compute-rest-server rias/regional-network-mock"
    # 2 - A docker repository URL to pull from
    # 3 - An image tag
    # 4 - An arch type (If there is none, this should be "")
    # 5 - A docker repository URL to push to
    if [ "$#" -ne 5 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 5 arguments but got $#. Please pass in the correct arguments."
        exit 1
    else
        IMAGES=($1)
        DOCKER_PULL_URL=$2
        IMAGE_TAGS=$3
        ARCH_TYPE=$4
        DOCKER_PUSH_URL=$5
    fi

    if [[ $ARCH_TYPE != "" ]]; then
        ARCH_TYPE="-$ARCH_TYPE"
    fi

    for image in ${IMAGES[@]}; do
        for tag in ${IMAGE_TAGS}; do
            check_tag_exists "${tag}"
            # Pulling down the image, renaming it, and uploading it to ICCR
            # SKIP_PUSH_FLAG - flag returned from check_tag_exists to determine if the image exists or not, and therfore if we should skip the push or not.
            if [[ "${SKIP_PUSH_FLAG}" == false ]]; then
                echo -e "\nINFO: Image was not found in ICCR, continue pushing the image"
                docker pull ${DOCKER_PULL_URL}/$image:${tag}${ARCH_TYPE}
                docker image tag ${DOCKER_PULL_URL}/$image:${tag}${ARCH_TYPE} ${DOCKER_PUSH_URL}/$image:${tag}${ARCH_TYPE}
                docker push ${DOCKER_PUSH_URL}/$image:${tag}${ARCH_TYPE}
                docker rmi ${DOCKER_PUSH_URL}/$image:${tag}${ARCH_TYPE}
                docker rmi ${DOCKER_PULL_URL}/$image:${tag}${ARCH_TYPE}
            else
                echo -e "\nWARNING: Image was found in ICCR, same image tags are not allowed, skip pushing to ICCR"
            fi
            # If we are running in OnePipeline, this is the moment where we save artifacts in order to be scanned later
            if [[ $ONE_PIPELINE_SAVE_ARTIFACTS_FOR_ICCR = true ]]; then
                # If the tag has a . in it, it means is a SemVer version tag, else is a SHA
                if [[ ${tag} == *"."* ]]; then
                    echo "For OnePipeline, we only save artifact with SHA, we don't work with SemVer"
                else
                    # At this point image should exist in ICCR, either because it was from a previous run or because we just pushed it
                    # Since the image should exist we can safely pull
                    ICCR_URL=${DOCKER_PUSH_URL}
                    docker pull ${ICCR_URL}/$image:${tag}${ARCH_TYPE} 
                        
                    DIGEST="$(docker inspect --format='{{index .RepoDigests 0}}' "${ICCR_URL}/$image:${tag}${ARCH_TYPE}" | awk -F@ '{print $2}')"
                    
                    IMAGE_NO_SLASHES=$(echo "$image" | tr / _)
                    NAME_FOR_SAVE_ARTIFACT="${IMAGE_NO_SLASHES}${ARCH_TYPE}_FOR_ICCR_SCAN"

                    save_artifact "${NAME_FOR_SAVE_ARTIFACT}" \
                    type=image \
                    "name=${ICCR_URL}/$image:${tag}${ARCH_TYPE}" \
                    "digest=${DIGEST}" \
                    "tags=${tag}"
                fi
            fi
        done
    done
}

function ICCR_check() {
    # Arguments expected:
    # 1 - A space-delimited list of image names - example: "rias/regional-compute-rest-server rias/profile-cacher"
    # 2 - An image tag
    # 3 - An IBMCLOUD docker registry URL
    if [ "$#" -ne 3 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 3 arguments but got $#. Please pass in the correct arguments."
        exit 1
    else
        IMAGES=($1)
        IMAGE_TAGS=$2
        IBMCLOUD_REG=$3
    fi

    # Wait for the scanning to be done
    echo "Checking if scans have completed"
    for tag in $IMAGE_TAGS; do
        while [[ $(ibmcloud cr image-list|grep ${tag}) =~ "Scan" ]]; do
        printf '.'
        sleep 120
        done
    done
    echo

    # Get any issues found in the image
    for image in ${IMAGES[@]}; do
       ibmcloud cr va -o json registry.${IBMCLOUD_REG}/$image > scan.json
       if [[ $(cat scan.json|jq '.[] |.status') =~ "FAIL" ]]; then
          vul_num=$(cat scan.json|jq '.[]|.vulnerabilities|length')
          echo "!! $image: $vul_num Vulnerabilities found !!"
          # TODO: Add flag here to error out if Vulnerabilities are found
       else
          echo "$image: No vulnerabilities found"
       fi
    done
}

# If SKIP_FLAG is defined, exit script
if [[ ${SKIP_FLAG} == "true" ]]; then
   echo "SKIP_FLAG has been provided - Cleanly exiting"
   exit 0
fi

if [ "${OPERATION}" != "PUSH" ] && [ "${OPERATION}" != "CHECK" ]; then
    echo "OPERATION must be PUSH or CHECK, but it's set to ${OPERATION}"
    exit 1
fi

if ! $(which ibmcloud > /dev/null); then
   echo " ibmcloud CLI is not installed"
   exit 1
fi

# Prevent creds from being printed out when debugging
orig_opts=$-
set +x
echo "Setting con_key_file for ibmcloud login"
echo "Logging into ${ARTIFACTORY_DOCKER_URL}"
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_URL} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
set -${orig_opts}

# Source the ibmcloud_utils.sh
. ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh
set +x
# Login to ibmcloud using function defined in ibmcloud_utils.sh
ibmcloud_login "${IBMCLOUD_KEY}"
set -x

ibmcloud cr login

# If IMAGE_TAG is not defined, define it with the current githash
if [[ -z ${IMAGE_TAGS} ]]; then
   pushd ${PATH_TO_WORKSPACE_REPO}
   HASH_TAG=$(git log -1 --format=%H)
   IMAGE_TAGS="${HASH_TAG}"
   SEMVER_TAG=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true
   [[ ! -z "${SEMVER_TAG}" ]] && IMAGE_TAGS+=" ${SEMVER_TAG}"
   echo "Image tags: ${IMAGE_TAGS}"
   popd
fi

# Find the list of artifacts
if [[ ! -z ${IMAGE_LIST} ]]; then
    echo "Using provided IMAGE_LIST"
    if [ -d ${PATH_TO_RELEASE_ENVIRONMENT} ]; then
        echo "Using tag in release-environment from a release bundle build"
        IMAGE_TAGS=$(cat ${PATH_TO_RELEASE_ENVIRONMENT}/build_tag)
    fi
    if [[ ${OPERATION} == "PUSH" ]]; then
        docker_pull_and_push "${IMAGE_LIST}" "${ARTIFACTORY_DOCKER_URL}" "${IMAGE_TAGS}" "" "${IBMCLOUD_URL}"
    fi
    # Adding the image tag to each image
    IMAGE_LIST=(${IMAGE_LIST})
    image_list=( "${IMAGE_LIST[@]/%/:${IMAGE_TAGS}}" )
elif [ -f ${PATH_TO_WORKSPACE_REPO}/hack/ci/build-meta.yaml ]; then
    echo "Using build-meta.yaml"
    # These yq commands pull out the needed image lists
    images_multi_arch=$(yq -r '.images.multi_arch | select(. != null) | if type=="string" then . else .[] end' ${PATH_TO_WORKSPACE_REPO}/hack/ci/build-meta.yaml)
    images_amd64=$(yq -r '.images.amd64 | select(. != null) | if type=="string" then . else .[] end' ${PATH_TO_WORKSPACE_REPO}/hack/ci/build-meta.yaml)
    if [[ ! ${images_amd64} == null ]]; then
        if [[ ${OPERATION} == "PUSH" ]]; then
            docker_pull_and_push "$images_amd64" "${ARTIFACTORY_DOCKER_URL}" "${IMAGE_TAGS}" "amd64" "${IBMCLOUD_URL}"
        fi
        # Adding -amd64 to the end of each image in the array
        images_amd64=($images_amd64)
        images_amd64=( "${images_amd64[@]/%/:${HASH_TAG}-amd64}" )
        [[ ! -z "${SEMVER_TAG}" ]] && images_amd64+=( "${IMAGE_LIST[@]/%/:${SEMVER_TAG}-amd64}" )
    else
        # Setting the array to be empty so that it can be joined in image_list
        images_amd64=()
    fi
    if [[ ! ${images_multi_arch} == null ]]; then
        # Change string into array and strip out anything before / in values then convert back to string
        for image_multi_arch in ${images_multi_arch}; do
            JQ_REGEX_MANIFEST_ARCHITECTURE='.manifests[].platform.architecture | select( . != null)'
            manifests=$(sudo docker manifest inspect ${ARTIFACTORY_DOCKER_URL}/${image_multi_arch}:${HASH_TAG})
            arch_types=($(echo ${manifests} | jq -r  "${JQ_REGEX_MANIFEST_ARCHITECTURE}"))
            if [[ ${OPERATION} == "PUSH" ]]; then
                for arch in ${arch_types[@]}; do
                    docker_pull_and_push "${image_multi_arch}" "${ARTIFACTORY_DOCKER_URL}" "${IMAGE_TAGS}" "${arch}" "${IBMCLOUD_URL}"
                done
            fi
            multi_tagged+=(${arch_types[@]/#/${image_multi_arch}:${HASH_TAG}-})
            [[ ! -z "${SEMVER_TAG}" ]] && multi_tagged+=(${arch_types[@]/#/${image_multi_arch}:${SEMVER_TAG}-})
        done
    else
        # Setting the array to be empty so that it can be joined in image_list
        multi_tagged=()
    fi
    image_list=(${images_amd64[@]} ${multi_tagged[@]})
else
    echo "docker image list not found"
    exit 1
fi

if [[ ${OPERATION} == "CHECK" ]]; then
    # Make the list spaced
    image_list="${image_list[@]}"
    ICCR_check "$image_list" "${IMAGE_TAGS}" "${IBMCLOUD_URL}"
fi
