#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2025
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##


# Multiple functions to be used for working with artifacts
# These function help clean up the build code, so the build code is focused on building the artifacts
# and the cicd common utilities are used to help pull/push/tag docker files, debian packages, for artifactory

# Functions and basic description:
# docker_login                    - login to docker repository - typically artifactory
# ibmcloud_login                  - login to ibmcloud
# docker_logout                   - logout of docker repository
# enable_docker_experimental      - enable docker experimental features - usually used for docker manifest
# create_docker_manifest          - creates a multiarch docker manifest file
# pull_from_docker_repository     - pulls docker files from multiple repos
# push_to_docker_repository       - pushes docker file to multiple repos
# put_to_artifactory              - put files (usually debian packages) to artifactory
# get_from_artifactory            - get files from artifactory

if [[ ! $(type -t exit_if_var_not_set) ]]; then
    source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/common/common_funcs.sh || $(echo "failed to load common_funcs.sh" && exit 1)
fi
if [[ ! $(type -t log_error) ]]; then
    source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/common/log_utils.sh || $(echo "failed to load log_utils.sh" && exit 1)
fi

# The following should come from Travis repo settings.
exit_if_var_not_set "TR_ARTIFACTORY_LOGIN"
exit_if_var_not_set "TR_ARTIFACTORY_ACCESS_TOKEN"
exit_if_var_not_set "ICR_API_KEY"

function docker_login() {
    # Arguments expected:
    # 1 - docker repo host

    # Make sure required arguments were passed in
    if [ "$#" -ne 1 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 1 argument but got $#. Please pass in the correct arguments."
        exit 1
    else
        dockerRepo=$1
    fi

    # Determine whether we are working with an authenticated repo
    boolCredsRequired=false
    # TODO(edmondsw): Specify via arg so we're not hardcoding "artifactory"
    if echo "${dockerRepo}" | grep -q "artifactory"; then
        boolCredsRequired=true
    fi

    DOCKER_OPTIONS=""
    # Login to docker registry only if required
    if [ "$boolCredsRequired" == true ]; then
        echo "Login to docker repo ${dockerRepo}...."
        sleep 1
        echo "${TR_ARTIFACTORY_ACCESS_TOKEN}" | docker login -u "${TR_ARTIFACTORY_LOGIN}" --password-stdin "${dockerRepo}"
        check_last_cmd_error "docker login failed!"
    fi
}

function icr_docker_login() {
    # Expected parameters:

    # $1 --> The IBM CLOUD KEY
    # $2 --> The region registry domain(Default is us.icr.io)
    
    # Put some friendly names
    IBM_CLOUD_KEY=$1
    
    # Default region registry domain us.icr.io
    REGISTRY_DOMAIN=${2:-"us.icr.io"}
    DOCKER_OPTIONS=""
    set +x # so we do not log the api key
    docker login -u iamapikey -p ${IBM_CLOUD_KEY} ${REGISTRY_DOMAIN}    
}

function docker_logout() {
    # Arguments expected:
    # 1 - docker repo host

    # Make sure required arguments were passed in
    if [ "$#" -ne 1 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 1 argument but got $#. Please pass in the correct arguments."
        exit 1
    else
        dockerRepo=$1
    fi

    # Determine whether we are working with an authenticated repo
    boolCredsRequired=false
    # TODO(edmondsw): Specify via arg so we're not hardcoding "artifactory"
    if echo "${dockerRepo}" | grep -q "artifactory" ;then
        boolCredsRequired=true
    fi

    # Logout of docker registry only if required
    if [ "$boolCredsRequired" == true ]; then
        echo "Logout of docker repo ${dockerRepo}...."
        docker logout "${dockerRepo}"
        check_last_cmd_error "docker logout failed!"
    fi
}


function enable_docker_experimental() {

    # Need to enable experimental in order for manifest command to work properly
    if ! grep "experimental" ~/.docker/config.json | grep enable; then
        sed -i '$i'"$(echo '\"experimental": "enabled"')" ~/.docker/config.json
        sed -i $(echo `grep -n "}" ~/.docker/config.json | tail -2 | head -1 | cut -f1 -d:`)'s/}/},/' ~/.docker/config.json
    fi
}

function create_docker_manifest() {
    # Arguments expected:
    # 1 - docker repository URL - example: docker-na-public.artifactory.swg-devops.com/wcp-genctl-sandbox-docker-local    
    # 2 - list of images - list of all images of a single architecture
    # 3 - list of image tags - list of images tags (SHA or Version)
    # 4 - image archs - amd64, s390x or multi_arch

    # Environment variables required:
    # TR_ARTIFACTORY_LOGIN
    # TR_ARTIFACTORY_ACCESS_TOKEN
    log_trace_enter "${FUNCNAME[0]} $*"

    # Make sure required arguments were passed in
    if [ "$#" -lt 4 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires at least 4 arguments but got $#. Please pass in the correct arguments."
        exit 1
    else
        DOCKER_REPO=$1        
        META_IMAGES_LIST=($2)
        IMAGE_TAGS=($3)
        IMAGE_ARCH=$4
    fi


    # If the repo contains .artifactory. we call function that supports artifactory login
    if [[ $DOCKER_REPO =~ ".artifactory." ]]
    then
        # Call docker login function
        docker_login "${DOCKER_REPO}"
    elif [[ $DOCKER_REPO =~ ".icr." ]]
    then
        # Login to ibmcloud icr using docker login
        # We assume we have environment variable ICR_API_KEY
        icr_docker_login "${ICR_API_KEY}"
    else
        echo "We don't know how to login against ${DOCKER_REPO}"
        echo "Will exit with error..."
        exit 1
    fi
    
    if [[ $(uname -m) =~ "x86_64" ]]; then
            enable_docker_experimental
    fi

    FAILED=0  # Tracks if any image/tag fails the check

    for image in "${META_IMAGES_LIST[@]}"; do        
        echo "Creating manifest for the image ${image}"
        image_path="${image%/*}"
        short_image_name=$(echo ${image} | sed -e 's/^.*\///')
        
        SUPPORTED_ARCHES="amd64 s390x"
        # Assign commonly used variable
        DOCKER_FULL_PATH="${DOCKER_REPO}/${image_path}/${short_image_name}"
        echo "DOCKER FULL PATH ${DOCKER_FULL_PATH}"

        for tag in "${IMAGE_TAGS[@]}"; do            
            arch_types=""
            full_arch_tags=""
            manifest_created=0  # Track if we actually made one
            
            echo "determining which architectures we need the manifest to point to"
            for arch in ${SUPPORTED_ARCHES}; do            
                set +e                
                docker buildx imagetools inspect "${DOCKER_FULL_PATH}:${tag}-${arch}" >/dev/null 2>&1
                rc=$?
                set -e
                if [[ "${rc}" -eq 0 ]]; then
                    echo "Found manifest for architecture: ${arch}"
                    arch_types+=" ${arch}"
                    full_arch_tags+=" ${DOCKER_FULL_PATH}:${tag}-${arch}"
                fi
            done
            
            arch_types="$(echo "$arch_types" | xargs)" # trim
            missing_arches=()

            if [[ "${IMAGE_ARCH}" == "amd64" ]]; then
                if [[ ! " ${arch_types} " =~ " amd64 " ]]; then
                    missing_arches+=("amd64")
                fi
            elif [[ "${IMAGE_ARCH}" == "s390x" ]]; then
                if [[ ! " ${arch_types} " =~ " s390x " ]]; then
                    missing_arches+=("s390x")
                fi
            elif [[ "${IMAGE_ARCH}" == "multi_arch" ]]; then
                for required_arch in amd64 s390x; do
                    if [[ ! " ${arch_types} " =~ " ${required_arch} " ]]; then
                        missing_arches+=("${required_arch}")
                    fi
                done
            else
                echo "ERROR: Unknown IMAGE_ARCH value '${IMAGE_ARCH}'. Allowed: amd64, s390x, multi_arch"
                FAILED=1
                continue
            fi

            if [[ ${#missing_arches[@]} -gt 0 ]]; then
                echo "ERROR: Missing architectures for ${DOCKER_FULL_PATH}:${tag} → ${missing_arches[*]}"
                FAILED=1
                # Skip creation & push for this tag
                continue
            fi

            echo "creating manifest with the following architecture annotations: ${arch_types}"
            sudo docker manifest create ${DOCKER_OPTIONS} "${DOCKER_FULL_PATH}:${tag}" ${full_arch_tags}
            manifest_created=1

            for arch in ${arch_types}; do
                echo "annotating with $arch architecture"
                sudo docker manifest annotate "${DOCKER_FULL_PATH}:${tag}" "${DOCKER_FULL_PATH}:${tag}-${arch}" --arch "${arch}"
            done        

            # Push only if manifest was created
            if [[ $manifest_created -eq 1 ]]; then                
                echo "Do a docker push of the manifest file:  docker push ${DOCKER_FULL_PATH}:${tag}"
                sudo docker manifest push ${DOCKER_OPTIONS} "${DOCKER_FULL_PATH}:${tag}"
                check_last_cmd_error "docker push manifest failed!"

                echo "docker manifest inspect "${DOCKER_FULL_PATH}:${tag}""
                sudo docker manifest inspect "${DOCKER_FULL_PATH}:${tag}"
                check_last_cmd_error "docker manifest inspect failed!"
            else
                echo "Skipping push for ${DOCKER_FULL_PATH}:${tag} (no manifest created)"
            fi
        done
    done

    docker_logout "${DOCKER_REPO}"
    
    # Exit after checking all images/tags
    if [[ $FAILED -eq 1 ]]; then
        echo "Some images/tags failed architecture checks. Exiting."
        exit 1
    else
        echo "All images/tags passed architecture checks."
    fi

    log_trace_exit "${FUNCNAME[0]}"
}

function create_docker_manifest_latest_docker() {
    # Arguments expected:
    # 1 - docker repository URL - example: docker-na-public.artifactory.swg-devops.com/wcp-genctl-sandbox-docker-local
    # 2 - docker repository image path - example:  genctl
    # 3 - image name - example:  libvirtmetrics    
    # 4 - a space-delimited list of image tags - example:  ${GIT_SHA} ${VERSION}    

    # Environment variables required:
    # TR_ARTIFACTORY_LOGIN
    # TR_ARTIFACTORY_ACCESS_TOKEN
    log_trace_enter "${FUNCNAME[0]} $*"

    # Make sure required arguments were passed in
    if [ "$#" -lt 4 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires at least 4 arguments but got $#. Please pass in the correct arguments."
        exit 1
    else
        DOCKER_REPO=$1
        IMAGE_PATH=$2
        IMAGE_NAME=$3        
        IMAGE_TAGS=($4)
    fi

    SUPPORTED_ARCHES="amd64 s390x"

    # If the repo contains .artifactory. we call function that supports artifactory login
    if [[ $DOCKER_REPO =~ ".artifactory." ]]
    then
        # Call docker login function
        docker_login "${DOCKER_REPO}"           
    elif [[ $DOCKER_REPO =~ ".icr." ]]
    then
        # Login to ibmcloud icr using docker login
        # We assume we have environment variable ICR_API_KEY
        icr_docker_login "${ICR_API_KEY}"        
    else
        echo "We don't know how to login against ${DOCKER_REPO}"
        echo "Will exit with error..."
        exit 1
    fi
    
    # Assign commonly used variable
    DOCKER_FULL_PATH="${DOCKER_REPO}/${IMAGE_PATH}/${IMAGE_NAME}"

    if [[ $(uname -m) =~ "x86_64" ]]; then
        enable_docker_experimental
    fi

    for tag in "${IMAGE_TAGS[@]}"; do
        echo "determining which architectures we need the manifest to point to"
        arch_types=
        full_arch_tags=
        for arch in ${SUPPORTED_ARCHES}; do
            docker pull ${DOCKER_FULL_PATH}:${tag}-${arch}
            rc=$?            
            if [[ "${rc}" -eq 0 ]]; then
                digest=$(docker inspect --format='{{index .RepoDigests 0}}' ${DOCKER_FULL_PATH}:${tag}-${arch})                
                full_arch_tags+=" ${digest}"
                arch_types+=" ${arch}"
            fi            
        done
        if [ -z "${arch_types}" ]; then
            echo "did not find any images for the supported architecture types"
            exit 1
        fi
        echo "creating manifest with the following architecture annotations: ${arch_types}"
        echo "docker manifest create ${DOCKER_OPTIONS} ${DOCKER_FULL_PATH}:${tag} ${full_arch_tags}"
        sudo docker manifest create ${DOCKER_OPTIONS} "${DOCKER_FULL_PATH}:${tag}" ${full_arch_tags}
        for arch in ${arch_types}; do
            echo "annotating with $arch architecture"
            sudo docker manifest annotate "${DOCKER_FULL_PATH}:${tag}" "${DOCKER_FULL_PATH}:${tag}-${arch}" --arch "${arch}"
        done
    done

    # push the manifest file ond then inspect it
    for tag in "${IMAGE_TAGS[@]}"; do
        echo "Do a docker push of the manifest file:  docker push ${DOCKER_FULL_PATH}:${tag}"
        sudo docker manifest push ${DOCKER_OPTIONS} "${DOCKER_FULL_PATH}:${tag}"
        check_last_cmd_error "docker push manifest failed!"

        echo "docker manifest inspect "${DOCKER_FULL_PATH}:${tag}""
        sudo docker manifest inspect "${DOCKER_FULL_PATH}:${tag}"
        check_last_cmd_error "docker manifest inspect failed!"
    done

    docker_logout "${DOCKER_REPO}"

    log_trace_exit "${FUNCNAME[0]}"
}


function push_to_docker_repository() {
    # Arguments expected:
    # 1 - docker repository URL - example: docker-na-public.artifactory.swg-devops.com/wcp-genctl-sandbox-docker-local
    # 2 - docker repository image path - example:  genctl
    # 3 - image name - example:  libvirtmetrics    
    # 4 - image arch - s390x / amd64
    # 5 - a space-delimited list of image tags - example:  ${GIT_SHA}-${DOCKER_ARCH} ${VERSION}-${DOCKER_ARCH}

    # Environment variables required:
    # TR_ARTIFACTORY_LOGIN
    # TR_ARTIFACTORY_ACCESS_TOKEN
    log_trace_enter "${FUNCNAME[0]} $*"

    # Make sure required arguments were passed in
    if [ "$#" -ne 5 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 5 arguments but got $#. Please pass in the correct arguments."
        exit 1
    else
        DOCKER_REPO=$1
        IMAGE_PATH=$2
        IMAGE_NAME=$3
        IMAGE_ARCH=$4
        IMAGE_TAGS=($5)
    fi

    # If the repo contains .artifactory. we call function that supports artifactory login
    if [[ $DOCKER_REPO =~ ".artifactory." ]]
    then    
        # Call docker login function
        docker_login "${DOCKER_REPO}"        
    elif [[ $DOCKER_REPO =~ ".icr." ]]
    then
        # Login to ibmcloud icr using docker login
        # We assume we have environment variable ICR_API_KEY
        icr_docker_login "${ICR_API_KEY}"        
    else
        echo "We don't know how to login against ${DOCKER_REPO}"
        echo "Will exit with error..."
        exit 1
    fi

    docker_base_url=$(echo "$DOCKER_REPO" | cut -d'/' -f1)
    remaining_url=$(echo "$DOCKER_REPO" | cut -d'/' -f2-)

    # Assign commonly used variable
    DOCKER_FULL_PATH="${DOCKER_REPO}/${IMAGE_PATH}/${IMAGE_NAME}"

    if [[ $(uname -m) =~ "x86_64" ]]; then
        enable_docker_experimental
    fi

    # Tag    
    full_image="${IMAGE_PATH}/${IMAGE_NAME}"    
    echo "Searching list of built docker images for ${IMAGE_NAME}..."
    # search the image list for the full image name. If that was successful, set "result" to that output,
    # otherwise check for the short image name, and if that was successful, set "result" to that output.
    # Otherwise, print an error message, and exit
    # Make sure we are exact matching images returned from the docker image list.
    
    # Extract the image ID of the oldest built image matching the given image name (full_image or IMAGE_NAME)
    # docker images --format lists image metadata: creation time, full repo name:tag, and ID
    # grep -E "(^|.*/)?${full_image}:" matches image names with or without a prefix (e.g., telemetry-base for docker, localhost/telemetry-base for podman)
    # sort arranges them by creation time (oldest first)
    # head -n1 picks the oldest matching image
    # awk '{print $NF}' extracts the image ID (the last field)
    confirmed_image_name=$(docker images --format "{{.CreatedAt}} {{.Repository}}:{{.Tag}} {{.ID}}" | grep -E "(^|.*/)?${full_image}:" | sort | head -n1 | awk '{print $NF}')
    if [[ -z "$confirmed_image_name" ]]; then            
        confirmed_image_name=$(docker images --format "{{.CreatedAt}} {{.Repository}}:{{.Tag}} {{.ID}}" | grep -E "(^|.*/)?${IMAGE_NAME}:" | sort | head -n1 | awk '{print $NF}')
    fi
    # error out if still not found
    if [[ -z "$confirmed_image_name" ]]; then
        echo "Failed to find ${full_image}! Exiting with error"
        exit 1
    fi
    echo "Confirmed that at least one image with a matching name was built"
    for tag in "${IMAGE_TAGS[@]}"; do
        # For no-arch images, don't add architecture suffix
        if [[ "${IMAGE_ARCH}" == "no-arch" ]]; then
            IMAGE_TAG_WITH_ARCH="${tag}"
        else
            IMAGE_TAG_WITH_ARCH="${tag}-${IMAGE_ARCH}"
        fi
        
        if manifests_exist_in_repo_for_tag ${DOCKER_REPO} ${full_image} "${IMAGE_TAG_WITH_ARCH}"; then
            statusCode=0
        else
            statusCode=$?
        fi
        if [[ "${statusCode}" -ne 0 ]]; then
            echo -e "\nINFO: Image tag was not found, continue pushing the image"
            echo "docker tag \"${confirmed_image_name}\" ${DOCKER_FULL_PATH}:${IMAGE_TAG_WITH_ARCH}"
            docker tag "${confirmed_image_name}" "${DOCKER_FULL_PATH}:${IMAGE_TAG_WITH_ARCH}"
            check_last_cmd_error "docker tag failed!"
            # Push
            echo "Docker Push ${DOCKER_FULL_PATH}:${IMAGE_TAG_WITH_ARCH}"
            docker push "${DOCKER_FULL_PATH}:${IMAGE_TAG_WITH_ARCH}"
            check_last_cmd_error "docker push failed!"
            docker rmi ${DOCKER_FULL_PATH}:${IMAGE_TAG_WITH_ARCH}
   echo "Deleted the image ${DOCKER_FULL_PATH}:${IMAGE_TAG_WITH_ARCH} from local successfully"
        else
            echo -e "\nWARNING: Image tag was found in ${DOCKER_REPO}, same image tags are not allowed, skip pushing the image"
        fi
    done

    docker_logout "${DOCKER_REPO}"
    log_trace_exit "${FUNCNAME[0]}"
}


function pull_from_docker_repository() {
    # Arguments expected:
    # 1 - docker repository URL - example: docker-na-public.artifactory.swg-devops.com/wcp-genctl-sandbox-docker-local
    # 2 - docker repository image path - example:  genctl/libvirtmetrics
    # 3 - image tag - example:  ${CC_GIT_SHA} or 1.0.0

    # Environment variables required:
    # TR_ARTIFACTORY_LOGIN
    # TR_ARTIFACTORY_ACCESS_TOKEN
    log_trace_enter "${FUNCNAME[0]} $*"

    # Make sure required arguments were passed in
    if [ "$#" -ne 3 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 3 arguments but got $#. Please pass in the correct arguments."
        exit 1
    fi

    DOCKER_REPO=$1
    IMAGE_PATH=$2
    IMAGE_TAG=$3    

    # If the repo contains .artifactory. we call function that supports artifactory login
    if [[ $DOCKER_REPO =~ ".artifactory." ]]
    then
        # Call docker login function
        docker_login "${DOCKER_REPO}"
    elif [[ $DOCKER_REPO =~ ".icr." ]]
    then
        # Login to ibmcloud icr using docker login
        # We assume we have environment variable ICR_API_KEY
        icr_docker_login "${ICR_API_KEY}"
    else
        echo "We don't know how to login against ${DOCKER_REPO}"
        echo "Will exit with error..."
        exit 1
    fi

    # Assign commonly used variable
    DOCKER_FULL_PATH="${DOCKER_REPO}/${IMAGE_PATH}"    

    # Pull with architecture tag or not (generic tag)
    docker pull ${DOCKER_OPTIONS} "${DOCKER_FULL_PATH}:${IMAGE_TAG}"
    check_last_cmd_error "docker pull failed!"

    # Get list of docker images
    docker image ls

    docker_logout "${DOCKER_REPO}"

    log_trace_exit "${FUNCNAME[0]}"
}


function get_from_artifactory() {
    # Arguments expected:
    # 1 - Artifactory file path - example: "https://${CC_ARTIFACTORY_HOST}/artifactory/${CC_ARTIFACTORY_GENERIC_REPO_PATH}/third-party/libvirt/${package}"
    # 2 - Temp directory path in workspace to copy files to - example:  "/tmp/${package}"

    # Environment variables required:
    # TR_ARTIFACTORY_LOGIN
    # TR_ARTIFACTORY_ACCESS_TOKEN
    log_trace_enter "${FUNCNAME[0]} $*"

    # Make sure required arguments were passed in
    if [ "$#" -ne 2 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 2 arguments but got $#. Please pass in the correct arguments."
        exit 1
    else
        ARTIFACTORY_FILE_PATH=$1
        ARTIFACT_LOCAL_FILE_PATH=$2
    fi

    wget --header="Authorization: Bearer ${TR_ARTIFACTORY_ACCESS_TOKEN}" "${ARTIFACTORY_FILE_PATH}" -O "${ARTIFACT_LOCAL_FILE_PATH}"
    check_last_cmd_error "wget failed!"

    log_trace_exit "${FUNCNAME[0]}"
}


function put_to_artifactory() {
    # Arguments expected:
    # 1 - Artifactory upload file path - example: "https://${CC_ARTIFACTORY_HOST}/artifactory/${CC_ARTIFACTORY_GENERIC_REPO_PATH}/third-party/libvirt/${package}"
    # 2 - File path in workspace to upload files from - example:  "/tmp/${package}"

    # Environment variables required:
    # TR_ARTIFACTORY_LOGIN
    # TR_ARTIFACTORY_ACCESS_TOKEN
    log_trace_enter "${FUNCNAME[0]} $*"

    # Make sure required arguments were passed in
    if [ "$#" -ne 2 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 2 arguments but got $#. Please pass in the correct arguments."
        exit 1
    else
        ARTIFACTORY_FILE_PATH=$1
        ARTIFACT_LOCAL_FILE_PATH=$2
    fi

    ARTIFACT_META=""

    if [[ ! -z "${CC_ARTIFACTORY_DEBIAN_REPO_PATH}" && "${ARTIFACTORY_FILE_PATH}" =~ ${CC_ARTIFACTORY_DEBIAN_REPO_PATH} ]]; then
        ARTIFACT_META=';deb.distribution=bionic;deb.component=main;deb.architecture=amd64;deb.architecture=ppc64el'
    fi

    curl --fail -X PUT -T "${ARTIFACT_LOCAL_FILE_PATH}" -H "Authorization: Bearer ${TR_ARTIFACTORY_ACCESS_TOKEN}" "${ARTIFACTORY_FILE_PATH}${ARTIFACT_META}"

    # error trap artifactory put errors and exit if error detected
    check_last_cmd_error "curl failed!"

    log_trace_exit "${FUNCNAME[0]}"
}

function delete_from_artifactory() {
    # Arguments expected:
    # 1 - Path/File to delete - example: "https://${CC_ARTIFACTORY_HOST}/artifactory/${CC_ARTIFACTORY_GENERIC_REPO_PATH}/third-party/libvirt/${package}"

    # Environment variables required:
    # TR_ARTIFACTORY_LOGIN
    # TR_ARTIFACTORY_ACCESS_TOKEN
    log_trace_enter "${FUNCNAME[0]} $*"

    # Make sure required arguments were passed in
    if [ "$#" -ne 1 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 2 arguments but got $#. Please pass in the correct arguments."
        exit 1
    else
        local artifactory_delete=$1
    fi

    curl --fail -H "Authorization: Bearer ${TR_ARTIFACTORY_ACCESS_TOKEN}" -X DELETE "${artifactory_delete}"
    # error trap artifactory put errors and exit if error detected
    check_last_cmd_error "curl failed!"

    log_trace_exit "${FUNCNAME[0]}"
}

function add_insecure_registry_to_docker() {
    echo "Insecure registries are not allowed!"
    exit 1
}

function manifests_exist_in_repo_for_tag() {
    # Arguments expected:
    # 1 - docker repository URL - example: docker-na-public.artifactory.swg-devops.com/wcp-genctl-sandbox-docker-local    
    # 2 - image name - example:  genctl/libvirtmetrics    
    # 3 - image arch - ${GIT_SHA}-${DOCKER_ARCH} OR ${VERSION}-${DOCKER_ARCH}    

    log_trace_enter "${FUNCNAME[0]} $*"
    
    # Make sure required arguments were passed in
    if [ "$#" -ne 3 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 3 arguments but got $#. Please pass in the correct arguments."
        exit 1
    else
        DOCKER_REPO=$1
        IMAGE_NAME=$2
        IMAGE_TAG=$3
    fi
    
    docker_base_url=$(echo "$DOCKER_REPO" | cut -d'/' -f1)
    docker_remaining_url=$(echo "$DOCKER_REPO" | cut -d'/' -f2-)

    # Assign commonly used variable
    DOCKER_FULL_PATH="${DOCKER_REPO}/${IMAGE_NAME}"

    if [[ $(uname -m) =~ "x86_64" ]]; then
        # copied from push_to_docker_repository
        enable_docker_experimental
    fi    
    
    # login to the repo
    if [[ $DOCKER_REPO =~ ".artifactory." ]]; then
        docker_login $DOCKER_REPO
    elif [[ $DOCKER_REPO =~ ".icr." ]]; then
        # Source the ibmcloud_utils.sh
        source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh
        set +x
        # Login to ibmcloud using function defined in ibmcloud_utils.sh
        ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"
        set -x
        ibmcloud cr login
    else
        echo "Do not know how to login to unexpected container registry repo: $DOCKER_REPO"
        exit 1
    fi
    exit_code=0
    if [[ $DOCKER_REPO =~ ".artifactory." ]]; then
        # This might fail if the image does not exist in the repository and we should allow it                
        set +e
        curl -silent -f -L \
            -u "${TR_ARTIFACTORY_LOGIN}:${TR_ARTIFACTORY_ACCESS_TOKEN}" \
            -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json" \
            "https://${docker_base_url}/v2/${docker_remaining_url}/${IMAGE_NAME}/manifests/${IMAGE_TAG}" > /dev/null
        exit_code=$?
        set -e
    elif [[ $DOCKER_REPO =~ ".icr." ]]; then
        set +e
        ibmcloud cr image-inspect "${DOCKER_FULL_PATH}:${IMAGE_TAG}" > /dev/null
        exit_code=$?        
        set -e
    else
        echo "Unknown registry in DOCKER_REPO: $DOCKER_REPO"
        return 1
    fi    
    return $exit_code    
}
