#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script builds the genctl-release bundle and pushes it to artifactory

set -ex

export RESULT_DEV_INT_SHA=${RESULT_DEV_INT_SHA:-""}
export TEST_COMPONENT_IN_GENCTL_RELEASE=${TEST_COMPONENT_IN_GENCTL_RELEASE:-"true"}
export PIPELINE_TEMPLATE_TYPE=${PIPELINE_TEMPLATE_TYPE:-""}

# ICR Migration related
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh 
export ICR_MIGRATION_MODE=${ICR_MIGRATION_MODE:-"false"} # By default we are not pushing images to ICR
export ICR_URL_TO_PUSH_ON_PREPARE_GENCTL_RELEASE_BUNDLE=${ICR_URL_TO_PUSH_ON_PREPARE_GENCTL_RELEASE_BUNDLE:-""}

echo "Running prepare-genctl-release-bundle pipeline"

if [[ -d ${PATH_TO_RELEASE_ENVIRONMENT} ]]
then
    echo "Release environment directory exists"
else
    echo "Release environment directory not exist, need to create..."
    mkdir -p ${PATH_TO_RELEASE_ENVIRONMENT}
fi

# Skip genctl release bundle build if the pipeline is for a non-genctl hotfix
if [[ "$HOTFIX_MAJOR_COMPONENT" != "" && "$HOTFIX_MAJOR_COMPONENT" != "genctl" ]]; then
    echo "This is a hotfix pipeline for ${HOTFIX_MAJOR_COMPONENT}; skipping genctl build"
    exit 0
fi

build_root=$(pwd)

eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts

# Set NSD version variable
export NSD_VERSION=${NEXTGEN_SERVICE_DEPLOYER_VER}

cd ${build_root}
### create release bundle
mkdir -p ~/.pip
echo [global] > ~/.pip/pip.conf
set +x  # so we don't log the password
echo index-url = https://${WCP_ARTIFACTORY_USERNAME}:${CC_ARTIF_ACCESS_TOKEN}@na.artifactory.swg-devops.com/artifactory/api/pypi/hyc-nextgen-pypi-virtual/simple >> ~/.pip/pip.conf
set -x

# install nextgen-service-deployer
if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
  python3 -m pip install ${NEXTGEN_SERVICE_DEPLOYER}==${NEXTGEN_SERVICE_DEPLOYER_VER}
else
  python -m pip install ${NEXTGEN_SERVICE_DEPLOYER}==${NEXTGEN_SERVICE_DEPLOYER_VER}
fi

cd ${build_root}

if [[ -n "${SUBMODULE}" && ${TEST_COMPONENT_IN_GENCTL_RELEASE} == true ]];  then
    ### get new genctl component hash tag and url (in case it comes from a fork)
    cd ${PATH_TO_WORKSPACE_REPO}
    remote_repo_url=`git config --get remote.origin.url`
    if [[ $IS_ONE_PIPELINE_RUN == "true" ]] && [[ $PIPELINE_TEMPLATE_TYPE == "razee" ]]
    then
      set -x
      if [[ ! -z "${RESULT_DEV_INT_SHA}" ]]
      then
        echo "Equivalent dev-integ SHA is: ${RESULT_DEV_INT_SHA}"
        component_hash_new=${RESULT_DEV_INT_SHA}
      else
        echo "At this point, expected to have the equivalent dev-integ SHA on variable RESULT_DEV_INT_SHA, but is empty"
        echo "Will exit with error..."
        exit 1
      fi
    else
      component_hash_new=`git rev-parse --verify HEAD`
    fi
    echo new ${SUBMODULE} git ref: $component_hash_new
    set +e
    pr_url=`git config --get pullrequest.url`
    set -e
    echo new ${SUBMODULE} pr url: $pr_url
    cd ${build_root}
    ### replace hash and url in the inventory.json file i\f it is not genctl-release component
    if [[ "$SUBMODULE" != "genctl-release" ]]; then
        url="${remote_repo_url}"
        if [ -n "$pr_url" ]; then
            url=`${PATH_TO_GENCTL_CI}/scripts/git_url_to_clone_address.py ${pr_url}`
        fi
        if [[ $url == https://x-oauth-basic:* ]]; then
            org_repo=$(echo "$url" | sed -E 's#https://x-oauth-basic:[^@]+@github.ibm.com/([^/]+)/([^/]+)#\1/\2#g')
            url="git@github.ibm.com:$org_repo.git"
            echo "formatted 1pl url is: $url"
        fi
        ${PATH_TO_GENCTL_CI}/scripts/update_inventory_json.py $SUBMODULE $component_hash_new "${url}" $PATH_TO_GENCTL_RELEASE_REPO/component-input/inventory.json inventory.json
        #override inventory with a updated component hash
        cp inventory.json $PATH_TO_GENCTL_RELEASE_REPO/component-input/inventory.json
        cat $PATH_TO_GENCTL_RELEASE_REPO/component-input/inventory.json
    fi
    TAG_VALUE=$(cd ${PATH_TO_WORKSPACE_REPO} && git rev-parse --verify HEAD)
else
    cd $PATH_TO_GENCTL_RELEASE_REPO

    # Use the semver tag if it exists, else use git hash
    # Do not exit if SEMVER_TAG is empty
    set +e
    SEMVER_TAG=$(git describe --tags --exact-match --abbrev=0 2> /dev/null)
    set -e
    if [[ ! -z "$SEMVER_TAG" ]]; then
      TAG_VALUE=${SEMVER_TAG}
    else
      HASH=$(git rev-parse --verify HEAD)
      BUILD_TIME=`date -u +"%Y%m%dT%H%M%SZ"`
      TAG_VALUE=${BUILD_TIME}_${HASH}
    fi

    echo "${TAG_VALUE}" > $PATH_TO_RELEASE_ENVIRONMENT/build_tag
fi

### create the release bundle
cd $PATH_TO_GENCTL_RELEASE_REPO
if [[ -z ${FLAVOR} ]]; then
  DOCKER_OPTS="--no-cache" make distclean all
else
  DOCKER_OPTS="--no-cache" make distclean all FLAVOR=${FLAVOR}
fi
cd ${build_root}

# login to docker
set +x  # so we don't log the password
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_URL_FOR_PREPARE_GENCTL_RELEASE_BUNDLE} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
set -x

# tag release bundle image with component hash tag
if [[ -z $FLAVOR ]]; then
  ARTIFACTORY_FULL_PATH=${ARTIFACTORY_DOCKER_URL_FOR_PREPARE_GENCTL_RELEASE_BUNDLE}/${GENCTL_RELEASE_BUNDLE_IMAGE_NAME}:${TAG_VALUE}
  if [[ ${ICR_MIGRATION_MODE} == true ]]
  then
    ICR_FULL_PATH=${ICR_URL_TO_PUSH_ON_PREPARE_GENCTL_RELEASE_BUNDLE}/${GENCTL_RELEASE_BUNDLE_IMAGE_NAME}:${TAG_VALUE}
  fi
else
  ARTIFACTORY_FULL_PATH=${ARTIFACTORY_DOCKER_URL_FOR_PREPARE_GENCTL_RELEASE_BUNDLE}/${GENCTL_RELEASE_BUNDLE_IMAGE_NAME}/${FLAVOR}:${TAG_VALUE}
  if [[ ${ICR_MIGRATION_MODE} == true ]]
  then
    ICR_FULL_PATH=${ICR_URL_TO_PUSH_ON_PREPARE_GENCTL_RELEASE_BUNDLE}/${GENCTL_RELEASE_BUNDLE_IMAGE_NAME}/${FLAVOR}:${TAG_VALUE}
  fi
fi

docker tag ${GENCTL_NEXTGEN_SERVICE_DEPLOYER_RELEASE_IMAGE_NAME}:latest ${ARTIFACTORY_FULL_PATH}

if [[ ${ICR_MIGRATION_MODE} == true ]]
then
  docker tag ${GENCTL_NEXTGEN_SERVICE_DEPLOYER_RELEASE_IMAGE_NAME}:latest ${ICR_FULL_PATH}
fi

# If we are in OnePipeline, we write the full image name to a file to be used in next steps
# The reason we do this is because the naming does not include SHA, only SemVer
# And the default save artifacts logic relies either on SHA or explicit complete image name

if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
  IMG_FILE_FULL_NAME="${CI_NON_STANDARD_NAMING_IMAGES_DIR}/${PIPELINE_REPO_ORG}_${PIPELINE_REPO_NAME}"

  echo ${ARTIFACTORY_FULL_PATH} > "${IMG_FILE_FULL_NAME}"
  echo "Succesfully created a file ${IMG_FILE_FULL_NAME} with the following content: "
  cat "${IMG_FILE_FULL_NAME}"

  if [[ ${ICR_MIGRATION_MODE} == true ]]
  then
    IMG_FILE_FULL_NAME_ICR="${CI_NON_STANDARD_NAMING_IMAGES_DIR}/${PIPELINE_REPO_ORG}_${PIPELINE_REPO_NAME}_${SUFFIX_FOR_ICR_SAVE_ARTIFACTS}"

    echo ${ICR_FULL_PATH} > "${IMG_FILE_FULL_NAME_ICR}"
    echo "Succesfully created a file ${IMG_FILE_FULL_NAME_ICR} with the following content: "
    cat "${IMG_FILE_FULL_NAME_ICR}"
  fi
fi

set +e # If the image does not exist allow this to fail.
inspect_result=$(docker manifest inspect ${ARTIFACTORY_FULL_PATH} > /dev/null)
statusCode=$?
set -e
if [[ "${statusCode}" -ne 0 ]]; then
  echo "Image tag was not found, continue pushing to ${ARTIFACTORY_DOCKER_URL_FOR_PREPARE_GENCTL_RELEASE_BUNDLE}"
  echo "pushing docker image"
  docker push ${ARTIFACTORY_FULL_PATH}
elif [[ "${ARTIFACTORY_DOCKER_URL_FOR_PREPARE_GENCTL_RELEASE_BUNDLE}" = "wcp-genctl-stage-docker-local.artifactory.swg-devops.com" ]]; then
  echo "WARNING: Image tag was found, but the stage area is being used."
  echo "pushing docker image"
  docker push ${ARTIFACTORY_FULL_PATH}
else
  echo "WARNING: Image tag was found, skipping the push to ${ARTIFACTORY_DOCKER_URL_FOR_PREPARE_GENCTL_RELEASE_BUNDLE}"
fi

if [[ ${ICR_MIGRATION_MODE} == true ]]
then
  # Login to ibmcloud using function defined in ibmcloud_utils.sh
  ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"
  ibmcloud cr login

  set +e # If the image does not exist allow this to fail.
  inspect_result=$(docker manifest inspect ${ICR_FULL_PATH} > /dev/null)
  statusCode=$?
  set -e
  if [[ "${statusCode}" -ne 0 ]]; then
    echo "Image tag was not found, continue pushing to ${ICR_URL_TO_PUSH_ON_PREPARE_GENCTL_RELEASE_BUNDLE}"
    echo "pushing docker image"
    docker push ${ICR_FULL_PATH}
  elif [[ "${ARTIFACTORY_DOCKER_URL_FOR_PREPARE_GENCTL_RELEASE_BUNDLE}" = "${VPC_ICR_SANDBOX_URL}" ]]; then
    echo "WARNING: Image tag was found, but the ICR sandbox is being used."
    echo "pushing docker image"
    docker push ${ICR_FULL_PATH}
  else
    echo "WARNING: Image tag was found, skipping the push to ${ICR_URL_TO_PUSH_ON_PREPARE_GENCTL_RELEASE_BUNDLE}"
  fi
fi

echo ${GENCTL_RELEASE_BUNDLE_IMAGE_NAME}:${TAG_VALUE} >> ${PATH_TO_WORKSPACE_REPO}/high_level_release_bundles_build_info.txt
