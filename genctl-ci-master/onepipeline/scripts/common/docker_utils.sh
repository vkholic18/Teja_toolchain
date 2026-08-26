#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2025
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##


# Helper functions to facilitate docker CLI usage


if [[ ! $(type -t log_error) ]]; then
    source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/common/log_utils.sh || $(echo "failed to load log_utils.sh" && exit 1)
fi

# pull out once we merge artifact_utils.sh
if [[ ! $(type -t docker_login) ]]; then
    source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/common/docker_utils.sh || $(echo "failed to load docker_utils.sh" && exit 1)
fi

function add_ibm_as_ca() {
    # when we fly around in travis builds, we are mostly likely using one of their own baked/installed images
    # (xenial 16.04). ie. not golang:123. In this instance, we will not have IBM's pub ssl certs to validate them as
    # a trusted CA. Install these will be trusted without needing any insecure
    # registry docker mojo
    SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
    OS_RELEASE=$(awk -F= '/^NAME/{print $2}' /etc/os-release)

    if [[ $OS_RELEASE =~ "Ubuntu" ]]; then
        CERT_PATH='/usr/local/share/ca-certificates'
    else
        CERT_PATH='/etc/pki/ca-trust/source/anchors/'
    fi

    sudo mkdir -p "${CERT_PATH}"
    sudo cp -vp "${SCRIPT_DIR}"/ibm_certs/* "${CERT_PATH}"
    [[ $OS_RELEASE =~ "Ubuntu" ]] && sudo /usr/sbin/update-ca-certificates || sudo /usr/bin/update-ca-trust
}

function docker_build() {
    # Builds a docker image
    # if you build it, they will come
    #   - voice in the corn field

    # Arguments expected:
    # 1 - image name
    # 2 - a space-delimited list of image tags - example:  ${GIT_SHA}-${DOCKER_ARCH} ${VERSION}-${DOCKER_ARCH}
    # 3 - optional dockerfile - relative/absolute
    # 4 - optional build context
    # 5 - optional space-delimited list of key value build arg pairs - example GITHASH=XXXXXX DATE=XXXXXX
    # Make sure required arguments were passed in
    if [ "$#" -lt 2 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires at least 2 arguments but got $#. Please pass in the correct arguments."
        exit 1
    fi

    IMAGE_NAME=$1
    IMAGE_TAGS=($2)
    DOCK_FILE=${3:-'Dockerfile'}
    BUILD_CONTEXT=${4:-"build/${IMAGE_NAME}"}
    BUILD_ARGS=${5:-}

    echo "--- ENTER docker_build ${IMAGE_NAME} ${IMAGE_TAGS} ${DOCK_FILE} ${BUILD_CONTEXT}"
    echo "------"

    if [[ ${DOCK_FILE} == 'Dockerfile' && ${BUILD_CONTEXT} != '.' ]]; then
        DOCK_FILE="${BUILD_CONTEXT}/${DOCK_FILE}"
    fi

    # verify if the dockerfile has an artifactory dependency. if so, we will need to auth
    # mac grep stinks - cant run this grep there. no posix matching
    set +e
    # not interested in taking errors here. we are testing for non-null
    DOCKER_HOST=($(grep -soP '^FROM\s\K(.*\.artifactory\.swg-devops\.com)' ${DOCK_FILE}|sort -u))
    set -e

    # if DOCKER_HOST is not null, we are artifactory and we have a repo we are interested in pulling from - so log in
    if [[ ! -z ${DOCKER_HOST:-} ]]; then
        for docker_host_name in "${DOCKER_HOST[@]}"
        do
            echo "We need to log into $docker_host_name prior to building. Doing that now..."
            docker_login $docker_host_name
        done
    fi

    # no-cache as dictated by: https://github.ibm.com/cloudlab/srb/blob/master/cheatsheets/NG/ARCH001b.9_Automate_Zero_Downtime_Deploy_Update.md
    options="--no-cache"
    for tag in ${IMAGE_TAGS[@]}; do
        options+=" -t ${IMAGE_NAME}:${tag}"
    done

    if [[ ! -z ${BUILD_ARGS} ]]; then
        for arg in ${BUILD_ARGS[@]}; do
            options+=" --build-arg ${arg}"
        done
    fi

    docker build $options -f ${DOCK_FILE} ${BUILD_CONTEXT}
    check_last_cmd_error "docker build failed for $IMAGE_NAME"
    log_trace_exit "${FUNCNAME[0]}"
}


function docker_build_v2() {
    # Builds a docker image

    # Arguments expected:
    # 1 - build context, example: "build/my-image-name"
    # 2 - space-delimited options, example: "-t ${IMAGE_NAME}:${GIT_SHA}-${DOCKER_ARCH} -t ${IMAGE_NAME}:${VERSION}-${DOCKER_ARCH} --build-arg GITHASH=XXXXXX"

    # Make sure required arguments were passed in
    if [ "$#" != 2 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 2 arguments but got $#. Please pass in the correct arguments."
        exit 1
    fi

    BUILD_CONTEXT=$1
    OPTIONS=$2

    echo "--- ENTER docker_build_v2 ${BUILD_CONTEXT} ${OPTIONS}"
    echo "------"

    # Always use --no-cache
    # See https://github.ibm.com/cloudlab/srb/blob/master/cheatsheets/NG/ARCH001b.9_Automate_Zero_Downtime_Deploy_Update.md
    if [[ ! "$OPTIONS" =~ "--no-cache" ]]; then
        OPTIONS+=" --no-cache"
    fi
    if [[ $ENV_DOCKER_ARCH == "amd64" ]]; then
        DOCKER_BUILDKIT=1 BUILDKIT_PROGRESS=plain docker build $OPTIONS ${BUILD_CONTEXT}
        check_last_cmd_error "docker build failed for ${BUILD_CONTEXT} with the following options: ${OPTIONS}"
    elif [[ $ENV_DOCKER_ARCH == "s390x" ]]; then
        BUILDAH_FORMAT=docker podman build --runtime=runc $OPTIONS ${BUILD_CONTEXT}
        check_last_cmd_error "docker build failed for ${BUILD_CONTEXT} with the following options: ${OPTIONS}"
    fi
    log_trace_exit "${FUNCNAME[0]}"
}

function get_docker_run_opts() {
    # Get docker run parameters based on the current working environment

    # Arguments expected:
    # 1 - Docker image name - example:  "${CC_ARTIFACTORY_HOST}/cloudnet:20190118.1"
    # 2 - Container name - example: "cloudnet_build_env"
    #
    # Outputs:
    # docker_opts - array containing the options for a docker run command

    local image_name=${1}
    local container_name=${2}
    local docker_env_file=${3:-none}
    local cap_add=${4:-none}

    # Make sure required arguments were passed in
    if [ "$#" -ne 2 ] && [ "$#" -ne 3 ] && [ "$#" -ne 4 ] ; then
        echo "ERROR: ${FUNCNAME[0]} requires 2 to 4 arguments but got $#. Please pass in the correct arguments."
        exit 1
    fi

    # # Setup local variables for the container user values.
    # local rlPWD="$(readlink -f "${PWD}")"
    # local rltoppath="$(readlink -f "${toppath}")"
    # local rlHOME="$( readlink -f "${HOME}")"
    # local dchome="/home/$(id -un)"

   if [[ "$cap_add" == "none" ]]; then
       # Basic docker options. Always mount the user's home directory.
       local -a docker_opts=( --name ${container_name} -v "${PATH_TO_WORKSPACE_REPO}:${PATH_TO_WORKSPACE_REPO}" -w "${PATH_TO_WORKSPACE_REPO}" )
    else
       # Basic docker options. Always mount the user's home directory.
       local -a docker_opts=( --name ${container_name} -v "${PATH_TO_WORKSPACE_REPO}:${PATH_TO_WORKSPACE_REPO}" -w "${PATH_TO_WORKSPACE_REPO}" --cap-add ${cap_add} )
    fi

    if [[ "$docker_env_file" != "none" ]]; then
       local -a docker_opts=( "${docker_opts[@]}" --env-file ${docker_env_file} )
    fi    
    if [[ $ENV_DOCKER_ARCH == "amd64" ]]; then
        docker_opts=( "${docker_opts[@]}" -it -d "${image_name}" )
    elif [[ $ENV_DOCKER_ARCH == "s390x" ]]; then
        docker_opts=( "${docker_opts[@]}" -d "${image_name}" )
    fi
    echo "${docker_opts[@]}"
}


function docker_run_with_apikey() {
    # Run a docker image with artifactory API key

    # Arguments expected:
    # 1 - Docker image path - example:  "${CC_ARTIFACTORY_HOST}/cloudnet:20190118.1"
    # 2 - Container name - example: "cloudnet_build_env"
    # 3 - Docker env file - env file is used to share env variables to docker container
    # 4 - Add capabilities - Add Linux capabilities to docker container
    log_trace_enter "${FUNCNAME[0]} $*"

    # Make sure required arguments were passed in
    if [ "$#" -ne 2 ] && [ "$#" -ne 3 ] && [ "$#" -ne 4 ] ; then
        echo "ERROR: ${FUNCNAME[0]} requires 2 to 4 arguments but got $#. Please pass in the correct arguments."
        exit 1
    fi

    local image_name=${1}
    local container_name=${2}
    local docker_env_file=${3:-none}
    local cap_add=${4:-none}

    if [[ "$docker_env_file" == "none" ]]; then
        if [[ "$cap_add" == "none" ]]; then
            # get environment options for docker run, saved to $docker_opts array
            docker_opts=( $(get_docker_run_opts ${image_name} ${container_name}) )
        else
            docker_opts=( $(get_docker_run_opts ${image_name} ${container_name} "none" ${cap_add}) )
        fi
    else
        if [[ "$cap_add" == "none" ]]; then
            # get environment options for docker run, saved to $docker_opts array
            docker_opts=( $(get_docker_run_opts ${image_name} ${container_name} ${docker_env_file}) )
        else
            docker_opts=( $(get_docker_run_opts ${image_name} ${container_name} ${docker_env_file} ${cap_add}) )
        fi
    fi    
    
    if [[ $ENV_DOCKER_ARCH == "amd64" ]]; then
        echo "Docker run command: docker run ${docker_opts[@]} /bin/bash"
        docker run ${docker_opts[@]} "/bin/bash"
        check_last_cmd_error "docker build failed with the following options: ${docker_opts[@]}"
    elif [[ $ENV_DOCKER_ARCH == "s390x" ]]; then
        echo "Podman run command: podman run --cgroups=disabled --privileged ${docker_opts[@]} sleep infinity"
        podman run --cgroups=disabled --privileged ${docker_opts[@]} sleep infinity
        check_last_cmd_error "docker build failed with the following options: ${docker_opts[@]}"
    fi

    
    check_last_cmd_error "ERROR: docker run failed"
    # echo "Setting art_apikey"
    # home_dir="$PATH_TO_WORKSPACE_REPO"    
    # echo "${TR_ARTIFACTORY_LOGIN}" > $home_dir/artif_user
    # echo "${TR_ARTIFACTORY_ACCESS_TOKEN}" > $home_dir/artif_apikey
    # sleep 3600
    # docker_exec $container_name "sudo cp $home_dir/artif_user /tmp/artif_user"
    # docker_exec $container_name "sudo cp $home_dir/artif_apikey /tmp/artif_apikey"
    # check_last_cmd_error "ERROR: docker exec failed"
    log_trace_exit "${FUNCNAME[0]}"
}


function docker_exec() {
    # execute commands in build container

    # Arguments expected:
    # 1 - Container name - example:  "cloudnet_build_env"
    # 2 - Command to run - example: "make && make unittests"
    log_trace_enter "${FUNCNAME[0]} $*"

    local container_name="$1"
    local cmd="$2"

    # Make sure required arguments were passed in
    if [ "$#" -ne 2 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 2 arguments but got $#. Please pass in the correct arguments."
        exit 1
    fi

    echo "Docker exec command: docker exec -it ${container_name} bash -c ${cmd}"
    # Check if the command contains shell-specific operators
    if [[ "$cmd" == *'>'* || "$cmd" == *'|'* || "$cmd" == *'&&'* || "$cmd" == *';'* ]]; then
        docker exec -i "$container_name" bash -c "$cmd"
    else
        # Safe to split command and args (preserve quoted args)
        docker exec -i "$container_name" $cmd
    fi
    check_last_cmd_error "ERROR: docker exec failed for $cmd"
    log_trace_exit "${FUNCNAME[0]}"
}


function cleanup_docker_env() {
    # Kill and remove a docker container

    # Arguments expected:
    # 1 - stop or kill - depending on the situation, we need flexibility here
    # 2 - Container name - example:  "cloudnet_build_env"
    log_trace_enter "${FUNCNAME[0]} $*"

    local action=${1}
    local container_name=${2}

    # Make sure required arguments were passed in
    if [ "$#" -ne 2 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 2 arguments but got $#. Please pass in the correct arguments."
        exit 1
    fi

    echo "Cleaning up docker container : ${container_name}"
    docker $action ${container_name}
    check_last_cmd_error "ERROR: docker $action failed"
    docker container rm ${container_name}
    check_last_cmd_error "ERROR: docker container rm failed"
    log_trace_exit "${FUNCNAME[0]}"
}