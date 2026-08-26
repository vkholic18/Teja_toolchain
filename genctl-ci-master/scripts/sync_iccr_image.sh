#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# The following script leverage inventory repository to push new image to legacy ICCR namespace used by Concourse builds

# New commit to the https://github.ibm.com/genctl-cicd/vpc-compliance-inventory repo triggers the pipeline
# 1. Verify that the commit made for a new image, skip deployment type of file
# 2. Pull image stored in artifact key
# 3. Get image namespace, image name and architecture from name key
# 4. Get imane sha by the master sem. ver. tag getting it from Git repository
# 5. Login to ICCR registry
# 6. Retag image to push to ICCR
# 7. Push to ICCR

export DRY_RUN_MODE="false"

. ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

#split artifact information to tokens to get image details: namespace, name, archtecture
#rias_calicoctl_amd64_image -> rias calicoctl amd64
function get_image_detailes(){
    FULL_NAME=$1
    IFS='_' info_arr=($FULL_NAME)
    IMAGE_GENESIS_NAMESPACE=${info_arr[0]}
    IMAGE_NAME=${info_arr[1]}
    IMAGE_ARCHITECTURE=${info_arr[2]}
    if [[ ${IMAGE_ARCHITECTURE} == "" ]]; then
        echo "Failed to get image archtecture fro a filename: ${IMAGE_FILE_NAME}"
        exit 1
    fi
}

function get_commited_file(){
  SHA="$(git rev-parse --verify HEAD)"
  COMMITED_FILE=$(git diff-tree --no-commit-id --name-only ${SHA} -r)
  #cat ${PATH_TO_WORKSPACE_REPO}/${COMMITED_FILE}
}

function login_registries(){
    # Login to registries if we have both login credentials (user/pass), otherwise assume the registries don't need them
    options=$-
    set +x  # so we don't log the password
    insecure_flag="" # Instantiate var so we don't exit on var being unset; value is set (if it should be) via check_insecure function
    if [[ ! -z ${PULL_REGISTRY_USER} && ${PULL_REGISTRY_PASSWORD} ]]; then
        echo "Logging into pull registry ${PULL_REGISTRY}"
        echo ${PULL_REGISTRY_PASSWORD} | docker login ${PULL_REGISTRY} -u ${PULL_REGISTRY_USER} --password-stdin
    fi
    if [[ ! -z ${PUSH_REGISTRY_API_KEY} ]]; then
        echo "Logging into push registry ${PUSH_REGISTRY}"
        echo "Setting con_key_file for ibmcloud login"
        set +x
        # Login to ibmcloud using function defined in ibmcloud_utils.sh
        ibmcloud_login "${PUSH_REGISTRY_API_KEY}"
        set -x
        ibmcloud cr login
        ibmcloud cr namespace-list
    fi
    if [[ $(echo "$options") == *"x"* ]]; then
        set -x
    fi
}

# Configuration needed for working with the remote (Needed before fetching tags)
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

echo WORKSPACE_PATH: ${WORKSPACE_PATH}
echo PATH_TO_WORKSPACE_REPO: ${PATH_TO_WORKSPACE_REPO}
echo "pwd:"
pwd

TO_DATE=$(date +%F)
FROM_DATE=$(date -d "yesterday" +%F)

echo "Will work with commits that are between ${FROM_DATE} to ${TO_DATE}"
cd ${PATH_TO_WORKSPACE_REPO}
for commit in $(git log --after="${FROM_DATE}" --before="${TO_DATE}"  --format=format:%H); do
    echo "Processing commit  ${commit}"
    git checkout ${commit} --quiet
    get_commited_file
    echo "COMMITED_FILE: ${COMMITED_FILE}"

    if [[ ${COMMITED_FILE} == *"_image"* ]]; then
        echo "Found new commit for image in ${COMMITED_FILE}."
        
        PATH_TO_FILE="${PATH_TO_WORKSPACE_REPO}/${COMMITED_FILE}"

        echo "Will work with file ${PATH_TO_FILE}"

        IMAGE_REPOSITORY_URL_HTTPS=$(jq .repository_url "${PATH_TO_FILE}")
        echo IMAGE_REPOSITORY_URL_HTTPS: ${IMAGE_REPOSITORY_URL_HTTPS}
        # fetch image master tag
        IMAGE_MASTER_TAG=$(jq .version "${PATH_TO_FILE}")
        IMAGE_MASTER_TAG=$(echo ${IMAGE_MASTER_TAG} | tr -d '"')
        echo IMAGE_MASTER_TAG: ${IMAGE_MASTER_TAG}
        # fetch artifact full name
        ARTIFACT_FULL_NAME=$(jq .name "${PATH_TO_FILE}")
        ARTIFACT_FULL_NAME=$(echo "${ARTIFACT_FULL_NAME}" | tr -d '"')
        echo "ARTIFACT_FULL_NAME: ${ARTIFACT_FULL_NAME}"
        # fetch source image location
        IMAGE_TO_PULL=$(jq .artifact "${PATH_TO_FILE}")
        IMAGE_TO_PULL=$(echo "${IMAGE_TO_PULL}" | tr -d '"')
        echo "IMAGE_TO_PULL: ${IMAGE_TO_PULL}"
        #fetch image details information
        get_image_detailes "${ARTIFACT_FULL_NAME}"
        echo "IMAGE_GENESIS_NAMESPACE: ${IMAGE_GENESIS_NAMESPACE}"
        echo "IMAGE_NAME: ${IMAGE_NAME}"
        echo "IMAGE_ARCHITECTURE: ${IMAGE_ARCHITECTURE}"

        #replace https://github.ibm.com/ to git@github.ibm.com:
        suffix=".git"
        IMAGE_REPOSITORY_URL_SSH=${IMAGE_REPOSITORY_URL_HTTPS/https:\/\/github.ibm.com\//git@github.ibm.com:}
        echo "IMAGE_REPOSITORY_URL_SSH: ${IMAGE_REPOSITORY_URL_SSH}"
        IMAGE_REPOSITORY_URL_SSH=$(echo "${IMAGE_REPOSITORY_URL_SSH}" | tr -d '"')
        IMAGE_REPOSITORY_URL_SSH+=$suffix
        echo "IMAGE_REPOSITORY_URL_SSH: ${IMAGE_REPOSITORY_URL_SSH}"

        #fetch from workspace repository hash by tag
        git clone ${IMAGE_REPOSITORY_URL_SSH} workspace_directory
        pushd workspace_directory
        IMAGE_MASTER_HASH=$(git rev-list -n 1 ${IMAGE_MASTER_TAG})
        echo IMAGE_MASTER_HASH: ${IMAGE_MASTER_HASH}
        popd

        echo "Will delete workspace_directory"
        rm -rf workspace_directory


        # Set some required env vars for copy images
        export PULL_REGISTRY_USER=${ARTIFACTORY_USER}
        export PULL_REGISTRY_PASSWORD=${CC_ARTIF_ACCESS_TOKEN}
        export PULL_REGISTRY=${ARTIFACTORY_DOCKER_URL}

        export PUSH_REGISTRY_API_KEY=${IBMCLOUD_KEY_CLCONC}
        login_registries

        # Artifactory prod
        if [[ ! -z ${ARTIFACTORY_DOCKER_URL} ]]; then
            echo "Will pull image ${IMAGE_TO_PULL}"
            docker pull ${IMAGE_TO_PULL}
        fi

        # push to ICR
        if [[ ! -z ${IBMCLOUD_CR_URL} ]]; then
            # Set parameters for push
            export PUSH_REGISTRY=${IBMCLOUD_CR_URL}
            export RETAG_SEMVER_TO_PUSH=${IMAGE_MASTER_TAG}

            # tag image with master sem.ver
            IMAGE_TO_PUSH="${PUSH_REGISTRY}/${IMAGE_GENESIS_NAMESPACE}/${IMAGE_NAME}:${IMAGE_MASTER_TAG}-${IMAGE_ARCHITECTURE}"
            echo IMAGE_TO_PUSH: ${IMAGE_TO_PUSH}

            #check if image already exist
            set +e
            inspect_result=$(docker manifest inspect ${IMAGE_TO_PUSH})
            statusCode=$?
            set -e
            if [[ "${statusCode}" -ne 0 ]]; then
                echo "Image tag ${IMAGE_MASTER_TAG} was not found, continue pushing to ${PUSH_REGISTRY}"
                docker tag ${IMAGE_TO_PULL} ${IMAGE_TO_PUSH}
                if [[ $DRY_RUN_MODE = true ]]; then
                    echo "DRY RUN MODE !!! - We would have run: docker push ${IMAGE_TO_PUSH}"
                else
                    echo "Would have run docker push ${IMAGE_TO_PUSH}"
                    docker push ${IMAGE_TO_PUSH}
                fi

                # tag image with master hash
                IMAGE_TO_PUSH="${PUSH_REGISTRY}/${IMAGE_GENESIS_NAMESPACE}/${IMAGE_NAME}:${IMAGE_MASTER_HASH}-${IMAGE_ARCHITECTURE}"
                echo IMAGE_TO_PUSH: ${IMAGE_TO_PUSH}
                docker tag ${IMAGE_TO_PULL} ${IMAGE_TO_PUSH}
                if [[ $DRY_RUN_MODE = true ]]; then
                    echo "DRY RUN MODE !!! - We would have run: docker push ${IMAGE_TO_PUSH}"
                else
                    echo "Would have run docker push ${IMAGE_TO_PUSH}"
                    docker push ${IMAGE_TO_PUSH}
                fi
            else
                echo "WARNING: Image tag was found, skipping the push to ${PUSH_REGISTRY}"
            fi
        fi
    else
        echo "Committed file ${COMMITED_FILE} is not image. Moving forward to next commit ..."
    fi
done
