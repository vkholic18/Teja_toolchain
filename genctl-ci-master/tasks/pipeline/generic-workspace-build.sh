#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO
# ARTIFACTORY_USER, CC_ARTIF_ACCESS_TOKEN
# GIT_PRIVATE_KEY
# CC_GITHUB_TOKEN
# VAULT_GIT_CONFIG_USER_EMAIL, VAULT_GIT_CONFIG_USERNAME
# CC_ARTIFACTORY_READER, CC_ARTIFACTORY_READER_APIKEY
# GPG_SIGNING_KEY, GPG_SIGNING_PW
# GHE_USERNAME, GHE_RO_TOKEN

# The following environment variables can be set before executing the script, if not they will use default values (Can be empty)

# ARTIFACTORY_DOCKER_URL, ARTIFACTORY_SANDBOX_DOCKER_URL, ARTIFACTORY_BASE_URL
# DEBIAN_PUSH_URLS : Space-separated URLs to upload debian package(s) to
# CC_ARTIFACTORY_GENERIC_REPO_PATH, CC_ARTIFACTORY_DEBIAN_REPO_PATH, CC_ARTIFACTORY_RPM_REPO_PATH
# CC_ARTIFACTORY_HOST
# CC_ARTIFACTORY_SANDBOX_DOCKER_URL
# CC_REPO_BRANCH, CC_REPO_NAME, CC_REPO_ORG
# CC_TRAVIS_API_ENDPOINT, CC_TRAVIS_CLI_VERSION
# UPLOAD
# UPLOAD_DEBIAN

# =============================================================================================
set -eu
# Set default values (Important since we have u flag and we can't have unbound variables)

export ARTIFACTORY_DOCKER_URL=${ARTIFACTORY_DOCKER_URL:-""}
export ARTIFACTORY_SANDBOX_DOCKER_URL=${ARTIFACTORY_SANDBOX_DOCKER_URL:-""}
export ARTIFACTORY_BASE_URL=${ARTIFACTORY_BASE_URL:-""}
export DEBIAN_PUSH_URLS=${DEBIAN_PUSH_URLS:-""}
export GOLANG_PUSH_URLS=${GOLANG_PUSH_URLS:-""}
export CC_ARTIFACTORY_GENERIC_REPO_PATH=${CC_ARTIFACTORY_GENERIC_REPO_PATH:-""}
export CC_ARTIFACTORY_DEBIAN_REPO_PATH=${CC_ARTIFACTORY_DEBIAN_REPO_PATH:-""}
export CC_ARTIFACTORY_RPM_REPO_PATH=${CC_ARTIFACTORY_RPM_REPO_PATH:-""}
export CC_ARTIFACTORY_HOST=${CC_ARTIFACTORY_HOST:-""}
export CC_ARTIFACTORY_SANDBOX_DOCKER_URL=${CC_ARTIFACTORY_SANDBOX_DOCKER_URL:-""}
export CC_REPO_BRANCH=${CC_REPO_BRANCH:-""}
export CC_REPO_NAME=${CC_REPO_NAME:-""}
export CC_REPO_ORG=${CC_REPO_ORG:-""}
export CC_TRAVIS_API_ENDPOINT=${CC_TRAVIS_API_ENDPOINT:-""}
export CC_TRAVIS_CLI_VERSION=${CC_TRAVIS_CLI_VERSION:-""}
export UPLOAD=${UPLOAD:-"false"} # Override this value for merge pipelines only (not PR)
export UPLOAD_DEBIAN=${UPLOAD_DEBIAN:-"false"}
export UPLOAD_GOLANG_BINARIES=${UPLOAD_GOLANG_BINARIES:-"false"}
export IS_ONE_PIPELINE_RUN=${IS_ONE_PIPELINE_RUN:-"false"}
export UPLOAD_PACKAGES_MODE=${UPLOAD_PACKAGES_MODE:-"legacy"} # By default keep legacy logic
export SKIP_UPLOAD_PACKAGES=${SKIP_UPLOAD_PACKAGES:-"true"} # By default do not upload packages
export UPLOAD_TO_REGISTRY_FLAG=${UPLOAD_TO_REGISTRY_FLAG:-""}

# This has the path to the directory in which we have the images as text files
export CI_NON_STANDARD_NAMING_IMAGES_DIR=${CI_NON_STANDARD_NAMING_IMAGES_DIR:-""}

export ICR_MIGRATION_MODE=${ICR_MIGRATION_MODE:-"false"} # By default we are not pushing images to ICR
export VPC_ICR_SANDBOX_URL=${VPC_ICR_SANDBOX_URL:-""}
export IBMCLOUD_CR_URL_ONEPIPELINE=${IBMCLOUD_CR_URL_ONEPIPELINE:-""}

source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh 

echo -e "${BYellow}Workspace Build starts at: $(date)............. ${NC}"
START=$(date +%s)

# This script implements generic-workspace-build
build_root="${PWD}"
export CI_BUILD_ROOT="${PWD}" # specifically used for cicd tasks
##############
# used for upload deb in image-service-workspace with put_to_artifactory common repo function called by image-service-workspace hack/ci/build.sh
export TR_ARTIFACTORY_LOGIN="${ARTIFACTORY_USER}"
export TR_ARTIFACTORY_ACCESS_TOKEN="${CC_ARTIF_ACCESS_TOKEN}"
##############
# Assign secrets to local vars and unset env vars so they don't propagate into build.sh
artifactory_user=${ARTIFACTORY_USER}
unset ARTIFACTORY_USER
cc_artif_access_token=${CC_ARTIF_ACCESS_TOKEN}
unset CC_ARTIF_ACCESS_TOKEN
artifactory_base_url=${ARTIFACTORY_BASE_URL}
artifactory_docker_url=${ARTIFACTORY_DOCKER_URL}
artifactory_sandbox_docker_url=${ARTIFACTORY_SANDBOX_DOCKER_URL}
debian_push_urls=${DEBIAN_PUSH_URLS}

# If the GIT_PRIVATE_KEY has a non-zero length, start ssh-agent and add that key to it
if [[ -n ${GIT_PRIVATE_KEY} ]]; then
    eval "$(ssh-agent -s)"
    ssh-add - <<< "${GIT_PRIVATE_KEY}"
fi
# If the VAULT_GIT_CONFIG_USER_EMAIL has a non-zero length, setup git email config
if [[ -n ${VAULT_GIT_CONFIG_USER_EMAIL} ]]; then
    git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
    unset VAULT_GIT_CONFIG_USER_EMAIL
fi
# If the VAULT_GIT_CONFIG_USERNAME has a non-zero length, setup git email config
if [[ -n ${VAULT_GIT_CONFIG_USERNAME} ]]; then
    git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"
    unset VAULT_GIT_CONFIG_USERNAME
fi
# if you see an error message such as:
# fatal: could not read Username for 'https://github.ibm.com': terminal prompts disabled
# The repo should be setting up the git config options, e.g.
# git config --global --add url."git@github.ibm.com:".insteadOf "https://github.ibm.com/"
# git config --global --add url."git@github.com:".insteadOf "https://github.com/"
if [[ ! -z ${artifactory_docker_url} ]]; then
    echo "docker login"
    echo ${cc_artif_access_token} | docker login ${artifactory_docker_url} -u ${artifactory_user} --password-stdin
fi
if [[ ! -z ${artifactory_sandbox_docker_url} ]]; then
    echo "sandbox docker login"
    echo ${cc_artif_access_token} | docker login ${artifactory_sandbox_docker_url} -u ${artifactory_user} --password-stdin
fi

if [[ ! -z ${ARTIFACTORY_DOCKER_PROXY_URL} ]]; then
    echo ${cc_artif_access_token} | docker login ${ARTIFACTORY_DOCKER_PROXY_URL} -u ${artifactory_user} --password-stdin
fi

##
# invoke boilerplate build script from dev repository
##
${PATH_TO_WORKSPACE_REPO}/hack/ci/build.sh

if [[ ${UPLOAD} == true ]]; then
    if [ "$(ls -A ${CI_NON_STANDARD_NAMING_IMAGES_DIR})" ]
    then
        echo "Instead of parsing build-meta.yaml, will upload according to what defined in ${CI_NON_STANDARD_NAMING_IMAGES_DIR}"

        # First login to prod and sandbox
        echo ${cc_artif_access_token} | docker login ${artifactory_docker_url} -u ${artifactory_user} --password-stdin
        echo ${cc_artif_access_token} | docker login ${artifactory_sandbox_docker_url} -u ${artifactory_user} --password-stdin

        if [[ ${ICR_MIGRATION_MODE} == true ]]
        then
            set +x
            # Login to ibmcloud using function defined in ibmcloud_utils.sh
            ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"
            set -x
        fi
        
        # Move to dir
        pushd "${CI_NON_STANDARD_NAMING_IMAGES_DIR}"

        # List content
        echo "Will list the content of ${PWD}"
        ls -la

        # Iterate and save artifacts
        for img_to_push in *
        do 
            echo "Processing file ${img_to_push}"
            url_to_push=$(cat ${img_to_push})

            # Push the image to artifactory
            set +e # If the image does not exist allow this to fail.
            inspect_result=$(docker manifest inspect ${url_to_push} > /dev/null)
            statusCode=$?
            set -e
            if [[ "${statusCode}" -ne 0 ]]; then
                docker push ${url_to_push}
            else
                echo "WARNING: Image tag was found, skipping the push to ${url_to_push}"
            fi
        done

        # Come back
        popd
    else
        export DOCKER_REGISTRY_PUSH_URL
        echo "Uploading image and creating manifest"
        cd ${PATH_TO_WORKSPACE_REPO}
        if [[ ! -z ${ARTIFACTORY_DOCKER_URL} ]]; then
            # Upload to prod only if the repo we are building is from a prod org
            if repo_is_from_prod_org ${PATH_TO_WORKSPACE_REPO}
            then
                # Login again just in case the workspace overwrote the CI user with another user not having permission to push
                echo ${cc_artif_access_token} | docker login ${artifactory_docker_url} -u ${artifactory_user} --password-stdin
                DOCKER_REGISTRY_PUSH_URL=${ARTIFACTORY_DOCKER_URL}
                echo "Uploading images to ${DOCKER_REGISTRY_PUSH_URL}"
                ${PATH_TO_GENCTL_CI}/scripts/process_build_meta.sh process_images
            else
                echo "Seems the repository is not from a production organization (For example, it might be a fork) ..."
                echo "We DON'T allow upload to ${ARTIFACTORY_DOCKER_URL} for repositories that are not from production organization"
            fi
        fi

        # Uploading images to ICR prod url
        if [[ ! -z ${IBMCLOUD_CR_URL_ONEPIPELINE} && ${ICR_MIGRATION_MODE} == true ]]; then
            # Upload to prod only if the repo we are building is from a prod org
            if repo_is_from_prod_org ${PATH_TO_WORKSPACE_REPO}
            then                
                set +x
                # Login to ibmcloud using function defined in ibmcloud_utils.sh
                ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"
                set -x

                ibmcloud cr login
                DOCKER_REGISTRY_PUSH_URL=${IBMCLOUD_CR_URL_ONEPIPELINE}
                echo "Uploading images to ${DOCKER_REGISTRY_PUSH_URL}"
                ${PATH_TO_GENCTL_CI}/scripts/process_build_meta.sh process_images
            else
                echo "Seems the repository is not from a production organization (For example, it might be a fork) ..."
                echo "We DON'T allow upload to ${IBMCLOUD_CR_URL_ONEPIPELINE} for repositories that are not from production organization"
            fi
        fi

        if [[ ! -z ${ARTIFACTORY_SANDBOX_DOCKER_URL} ]]; then
            echo ${cc_artif_access_token} | docker login ${artifactory_sandbox_docker_url} -u ${artifactory_user} --password-stdin
            DOCKER_REGISTRY_PUSH_URL=${ARTIFACTORY_SANDBOX_DOCKER_URL}
            echo "Uploading images to ${DOCKER_REGISTRY_PUSH_URL}"
            ${PATH_TO_GENCTL_CI}/scripts/process_build_meta.sh process_images
        fi

        # Uploading images to ICR sandbox url
        if [[ ! -z ${VPC_ICR_SANDBOX_URL} && ${ICR_MIGRATION_MODE} == true ]]; then
            set +x
            # Login to ibmcloud using function defined in ibmcloud_utils.sh
            ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"
            set -x

            ibmcloud cr login
            DOCKER_REGISTRY_PUSH_URL=${VPC_ICR_SANDBOX_URL}
            echo "Uploading images to ${DOCKER_REGISTRY_PUSH_URL}"
            ${PATH_TO_GENCTL_CI}/scripts/process_build_meta.sh process_images
        fi

        echo "Uploaded image and manifest"
        echo "done"
    fi
else
    echo "Skipping CI image upload (env var UPLOAD=${UPLOAD})"
fi

# Re-set the API key so it may be used by the debian package uploading script.
export CC_ARTIF_ACCESS_TOKEN=${cc_artif_access_token}
# Re-set url value
export ARTIFACTORY_BASE_URL=${artifactory_base_url}

if [[ "${UPLOAD_PACKAGES_MODE}" = "new" ]]; then

    if [[ "${SKIP_UPLOAD_PACKAGES}" = "false" ]]; then
        echo "Will upload packages..."
        ${PATH_TO_GENCTL_CI}/scripts/process_build_meta_new/process_build_meta_new.sh "packages" "upload"
    else
        echo "Not uploading packages..."
    fi
else
    if [[ ${UPLOAD_DEBIAN} == true ]]; then
        echo "Processing debian packages..."
        mkdir -p ${build_root}/build/build-versions
        for deb_push_url in ${DEBIAN_PUSH_URLS}; do
            cd ${PATH_TO_WORKSPACE_REPO}
            if [[ ! -z ${deb_push_url} ]]; then
                echo "Uploading packages to ${deb_push_url}"
                export DEBIAN_PUSH_URL=${deb_push_url}
                ${PATH_TO_GENCTL_CI}/scripts/process_build_meta.sh process_packages
            fi
        done
    fi

    if [[ ${UPLOAD_GOLANG_BINARIES} == true ]]; then
        echo "Processing golang packages..."
        mkdir -p ${build_root}/build/build-versions
        for golang_push_url in ${GOLANG_PUSH_URLS}; do
            cd ${PATH_TO_WORKSPACE_REPO}
            if [[ ! -z ${golang_push_url} ]]; then
                echo "Uploading packages to ${golang_push_url}"
                export GOLANG_PUSH_URL=${golang_push_url}
                ${PATH_TO_GENCTL_CI}/scripts/process_build_meta.sh process_packages
            fi
        done
    fi
fi

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Workspace Build ends at: $(date)............. ${NC}"
echo -e "${BYellow}Workspace Build took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete............. ${NC}"
