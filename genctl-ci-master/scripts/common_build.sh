#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2019
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

#**************************************************************************
#        NAME
#               genctl-ci/scripts/common_build.sh
# DESCRIPTION
#               basic local, single architecture build of component and images
#       NOTES
#               after successful component build, docker files, then docker
#               docker images are generated and pushed to artifactory
#**************************************************************************
set -e
export BUILD_ROOT=${PWD}
default_dir=${PWD}
workspace_directory=$1
# reads the build.yaml file (yq) to get the relative path to build
build_root_append=$(yq '.build_root | select(. != null)' ${workspace_directory}/hack/ci/build-meta.yaml)
# If we got a value that wasn't null or empty, append the path to BUILD_ROOT
if [[ ! -z "${build_root_append}" ]]; then
    BUILD_ROOT="${BUILD_ROOT}/${build_root_append}"
    echo "var BUILD_ROOT updated to ${BUILD_ROOT}"
fi
pushd ${workspace_directory}
echo "Loading general_utils.sh"
source ${default_dir}/cicd-common/general_utils.sh # load cicd-common utility functions for later use
echo "Loaded general_utils.sh"
log_banner "Build and stage artifacts $(realpath ${BASH_SOURCE[0]})"
initialize_submodules # Ensure submodules are updated with concourse hash
all_arch_images=$(yq -r '.images.multi_arch | select(. != null) | if type=="string" then . else .[] end' hack/ci/build-meta.yaml)
amd64_images=$(yq -r '.images.amd64 | select(. != null) | if type=="string" then . else .[] end' hack/ci/build-meta.yaml)
git_tag=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true
[[ ! -z "${git_tag}" ]] && VERSION_TAG="${git_tag}-${ENV_DOCKER_ARCH}" || VERSION_TAG=""
log "BUILD_ROOT=${BUILD_ROOT}"
CONTAINER_NAME="${CC_REPO_NAME}-$(git rev-parse --short HEAD)"      # Get container name based on git
GO_LANG_IMAGE="${CC_ARTIFACTORY_PROD_HOST}/${CC_GO_IMAGE_PATH}:${CC_GO_IMAGE_TAG}"
# looks like we need the below to satisfy external dependencies - not a good design - multiple vars with the same value/only used externally
PROD_ARTIFACTORY_HOST="${CC_ARTIFACTORY_PROD_HOST}"
VERSIONS="${CC_GIT_SHA}-${ENV_DOCKER_ARCH} ${VERSION_TAG}"
popd

echo "
   Concourse Provided Variables:
   ==============================
   CC_ARTIFACTORY_DEBIAN_REPO_PATH...${CC_ARTIFACTORY_DEBIAN_REPO_PATH}
   CC_ARTIFACTORY_GENERIC_REPO_PATH..${CC_ARTIFACTORY_GENERIC_REPO_PATH}
   CC_ARTIFACTORY_HOST...............${CC_ARTIFACTORY_HOST}
   CC_GO_IMAGE_PATH..................${CC_GO_IMAGE_PATH}
   CC_GO_IMAGE_TAG...................${CC_GO_IMAGE_TAG}
   CC_REPO_BRANCH....................${CC_REPO_BRANCH}
   CC_REPO_NAME......................${CC_REPO_NAME}
   CC_REPO_ORG.......................${CC_REPO_ORG}
   CC_TRAVIS_API_ENDPOINT............${CC_TRAVIS_API_ENDPOINT}
   CC_TRAVIS_CLI_VERSION.............${CC_TRAVIS_CLI_VERSION}
"

echo "
   Script Variables:
   ==================
   all_arch_images.........${all_arch_images}
   amd64_images............${amd64_images}
   BUILD_ROOT..............${BUILD_ROOT}
   CONTAINER_NAME..........${CONTAINER_NAME}
   GO_LANG_IMAGE...........${GO_LANG_IMAGE=}
   VERSIONS................${VERSIONS}
"

#**************************************************************************
#        NAME
#               local_build()
# DESCRIPTION
#               build all docker images and push to repos
#**************************************************************************
function local_build() {
    log_banner "local_build"
    log_trace_enter "${FUNCNAME[0]} $*"
    pushd ${workspace_directory}                      # make runs in repo git directory
    source .envrc
    make build BUILD_ROOT=${BUILD_ROOT}  # Build docker files
    [ $? != 0 ] && echo "Make returned error" && exit 1;  # Without this, make failure won't exit even on 'set -e'
    echo "SUCCESSFULLY executed make build"
    popd                                 # remaining steps run from BUILD_ROOT

    # Prevent creds from being printed out when debugging
    orig_opts=$-
    set +x
    echo "Logging into docker repo ${CC_ARTIFACTORY_HOST}"
    echo "${CC_ARTIF_ACCESS_TOKEN}" | docker login ${CC_ARTIFACTORY_HOST} -u ${CC_ARTIFACTORY_USERNAME} --password-stdin
    set -${orig_opts}

    # Build and push images to docker repositories
    for i in $amd64_images; do
        docker_image=$(echo ${i} | sed -e 's/^.*\///')
        docker_path=$(echo ${i}  | grep '/' | sed -e 's/\/[^\/]*$//')
        # [[ -z ${docker_path+x} ]] && docker_path="${CC_REPO_ORG}"  ### THIS IS FAILING TO DETECT NULL STRING
        [[ -z "${docker_path}" ]] && docker_path="${CC_REPO_ORG}"
        echo dockerpath="docker_path=\"${docker_path}\", docker_image=\"${docker_image}\", CC_REPO_ORG=\"${CC_REPO_ORG}\""
        echo "Building ${i} image"
        docker_build ${docker_image} "$VERSIONS"
        push_to_docker_repository "${CC_ARTIFACTORY_HOST}" "${docker_path}" "${docker_image}" "$VERSIONS"
    done

    log_trace_exit "${FUNCNAME[0]}"
}

#**************************************************************************
#        NAME
#               create_manifest_for_arch()
# DESCRIPTION
#               create a single docker manifest
#**************************************************************************
function create_manifest_for_arch() {
    local docker_path=$1
    local image_name=$2
    local version=$3
    local arch=$4
    create_docker_manifest "${CC_ARTIFACTORY_HOST}" "${docker_path}" "${image_name}" "${version}" "${arch}"
}

#**************************************************************************
#        NAME
#               local_create_manifest()
# DESCRIPTION
#               create docker manifests for all images
#                  This function should only be called after all architecture builds have been successful
#**************************************************************************
function local_create_manifest() {
    log_banner "local_create_manifest"

    # create a docker manifest for each amd64-only image so that it can be found without specifying arch
    for i in $amd64_images; do
        docker_image=$(echo ${i} | sed -e 's/^.*\///')
        docker_path=$(echo ${i}  | grep '/' | sed -e 's/\/[^\/]*$//')
        # [[ -z ${docker_path+x} ]] && docker_path="${CC_REPO_ORG}"  ### THIS IS FAILING TO DETECT NULL STRING
        [[ -z "${docker_path}" ]] && docker_path="${CC_REPO_ORG}"
        echo dockerpath="docker_path=\"${docker_path}\", docker_image=\"${docker_image}\", CC_REPO_ORG=\"${CC_REPO_ORG}\""
        create_manifest_for_arch "${docker_path}" "${docker_image}" "${CC_GIT_SHA}" amd64
        if [[ ! -z ${git_tag} ]]; then
            create_manifest_for_arch "${docker_path}" "${docker_image}" "${git_tag}" amd64
        fi
    done

    # create a docker manifest for each multi-arch image so that it can be found without specifying arch
    # (in this case, the manifest will point to each arch, and docker will automatically use the correct one for the current system)
    for i in $all_arch_images; do
        docker_image=$(echo ${i} | sed -e 's/^.*\///')
        docker_path=$(echo ${i}  | grep '/' | sed -e 's/\/[^\/]*$//')
        # [[ -z ${docker_path+x} ]] && docker_path="${CC_REPO_ORG}"  ### THIS IS FAILING TO DETECT NULL STRING
        [[ -z "${docker_path}" ]] && docker_path="${CC_REPO_ORG}"
        echo dockerpath="docker_path=\"${docker_path}\", docker_image=\"${docker_image}\", CC_REPO_ORG=\"${CC_REPO_ORG}\""
        create_manifest_for_arch "${docker_path}" "${docker_image}" all
    done
}

#main
case "$1" in

build) echo "Run travis build function..."
    local_build
    ;;
manifest) echo "Run travis create manifest function..."
    local_create_manifest
    ;;
*) echo "Running build and creating manifest..."
    local_build
    local_create_manifest
    ;;
esac
