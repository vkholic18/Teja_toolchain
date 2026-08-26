#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script builds the rias-release and the rias-etcd-release bundles and pushes them to artifactory

set -ex

export RESULT_DEV_INT_SHA=${RESULT_DEV_INT_SHA:-""}

# ICR Migration related
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh 

export ICR_MIGRATION_MODE=${ICR_MIGRATION_MODE:-"false"} # By default we are not pushing images to ICR
export ICR_URL_TO_PUSH_ON_PREPARE_RIAS_RELEASE_BUNDLE=${ICR_URL_TO_PUSH_ON_PREPARE_RIAS_RELEASE_BUNDLE:-""}

# Skip rias release bundle build if the pipeline is for a non-rias hotfix
if [[ "$HOTFIX_MAJOR_COMPONENT" != "" && "${HOTFIX_MAJOR_COMPONENT}-release" != "$RELEASE_REPO" ]]; then
    echo "This is a hotfix pipeline for ${HOTFIX_MAJOR_COMPONENT}; skipping ${RELEASE_REPO} build"
    exit 0
fi

if [[ -d ${PATH_TO_RELEASE_ENVIRONMENT} ]]
then
    echo "Release environment directory exists"
else
    echo "Release environment directory not exist, need to create..."
    mkdir -p ${PATH_TO_RELEASE_ENVIRONMENT}
fi

build_root=$(pwd)
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"

# Setup pip
mkdir -p ~/.pip
echo [global] > ~/.pip/pip.conf
set +x  # so we don't log the password
echo index-url = https://${WCP_ARTIFACTORY_USERNAME}:${CC_ARTIF_ACCESS_TOKEN}@na.artifactory.swg-devops.com/artifactory/api/pypi/hyc-nextgen-pypi-virtual/simple >> ~/.pip/pip.conf
set -x

# Build release bundle
# 'make all' looks for the specific release dir so clone to that

if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
  RELEASE_REPO=${PATH_TO_RELEASE_REPO}
else
  git clone release-repo ${RELEASE_REPO}
fi

cd ${build_root}

echo RIAS_COMPONENT: ${RIAS_COMPONENT}
echo RELEASE_REPO: ${RELEASE_REPO}

# Set NSD version variable
export NSD_VERSION=${NEXTGEN_SERVICE_DEPLOYER_VER}

# check if component exist on rias release / rias-etcd inventory. If not skip building the rias / rias-etcd bundle
# used in the genctl pipeline to build release bundles if the component is shared with rias
if [[ -n "${RIAS_COMPONENT}" ]];  then
  echo "check if the component ${RIAS_COMPONENT} is a shared genctl component"
  set +e
  python3 ${PATH_TO_GENCTL_CI}/scripts/exist_in_inventory_json.py ${RIAS_COMPONENT} ${RELEASE_REPO}/component-input/inventory.json
  result=$?
  echo $result
  set -e
  if [[ ${result} == 100 ]]; then
    echo "component ${RIAS_COMPONENT} is not a shared genctl component. No need to build the release bundle. Exiting ..."
    exit 0
  else
    echo "component ${RIAS_COMPONENT} is a shared genctl component. Proceed to creating the rias release bundle."
  fi
fi

# install nextgen-service-deployer
if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
  python3 -m pip install ${NEXTGEN_SERVICE_DEPLOYER}==${NEXTGEN_SERVICE_DEPLOYER_VER}
else
  python -m pip install ${NEXTGEN_SERVICE_DEPLOYER}==${NEXTGEN_SERVICE_DEPLOYER_VER}
fi

# if RIAS_COMPONENT exist build rias release bundle with custom RIAS_COMPONENT hash tag updated
# update rias-release inventory file
if [ -n "${RIAS_COMPONENT}" ];  then
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
    #set +e
    #pr_url=`git config --get pullrequest.url`
    #set -e
    
    echo "new ${SUBMODULE} pr url: ${PR_URL}"
    cd ${build_root}
    ### replace hash and url in the inventory.json file
    if [[ -f ${RELEASE_REPO}/component-input/inventory.json ]]; then
        url="${remote_repo_url}"
        # Check if we have something in PR_URL, if yes, means it is a PR run
        if [ -n "${PR_URL}" ]; then
            echo "We are running in a PR pipeline; PR_URL is ${PR_URL}"
            url=$(${PATH_TO_GENCTL_CI}/scripts/git_url_to_clone_address.py "${PR_URL}")
        fi
        # 1PL case
        if [[ $url == https://x-oauth-basic:* ]]; then
            org_repo=$(echo "$url" | sed -E 's#https://x-oauth-basic:[^@]+@github.ibm.com/([^/]+)/([^/]+)#\1/\2#g')
            url="git@github.ibm.com:$org_repo.git"
        fi
        ${PATH_TO_GENCTL_CI}/scripts/update_inventory_json.py $RIAS_COMPONENT $component_hash_new "${url}" ${RELEASE_REPO}/component-input/inventory.json inventory.json
        cat inventory.json
        cp inventory.json ${RELEASE_REPO}/component-input/inventory.json
    else
        echo "Failed to find a genctl-release/build/inventory.json file, quitting..."
        exit 1
    fi
fi

pushd ${RELEASE_REPO}
DOCKER_OPTS="--no-cache" make all
popd

# tag for release bundle image
if [ -n "${RIAS_COMPONENT}" ];  then
    pushd ${PATH_TO_WORKSPACE_REPO}
    TAG_VALUE=$(git rev-parse --verify HEAD)
    popd
else
    pushd ${PATH_TO_RELEASE_REPO}
    HASH=$(git rev-parse --verify HEAD)
    if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
        echo "We are in One Pipeline Run..." 
        if [ -n "$PR_ID" ]; then
          echo "PR_ID is ${PR_ID}"
        fi
    else
      set +e  # so we do not error if this is not a pull request
      PR_ID=$(git config --get pullrequest.id)
      set -e
    fi
    if [ -n "$PR_ID" ]; then
        TAG_VALUE=${HASH}
    else
        # Use the semver tag if it exists, else use git hash
        # Do not exit if SEMVER_TAG is empty
        set +e
        SEMVER_TAG=$(git describe --tags --exact-match --abbrev=0 2> /dev/null)
        set -e
        if [[ ! -z "$SEMVER_TAG" ]]; then
          TAG_VALUE=${SEMVER_TAG}
        else
          BUILD_TIME=`date -u +"%Y%m%dT%H%M%SZ"`
          TAG_VALUE=${BUILD_TIME}_${HASH}
        fi
    fi
    popd
fi

echo "${TAG_VALUE}" > $PATH_TO_RELEASE_ENVIRONMENT/build_tag

# Login to docker
set +x  # so we don't log the password
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_URL_FOR_PREPARE_RIAS_RELEASE_BUNDLE} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
set -x


# Tag and push new release bundle
docker tag ${NEXTGEN_SERVICE_DEPLOYER_RELEASE_IMAGE_NAME}:latest ${ARTIFACTORY_DOCKER_URL_FOR_PREPARE_RIAS_RELEASE_BUNDLE}/${RELEASE_BUNDLE_IMAGE_NAME}:${TAG_VALUE}

if [[ ${ICR_MIGRATION_MODE} == true ]]
then
  docker tag ${NEXTGEN_SERVICE_DEPLOYER_RELEASE_IMAGE_NAME}:latest ${ICR_URL_TO_PUSH_ON_PREPARE_RIAS_RELEASE_BUNDLE}/${RELEASE_BUNDLE_IMAGE_NAME}:${TAG_VALUE}
fi

# Save the full image name in a variable
PREPARED_BUNDLE_IMAGE_FULL_NAME="${ARTIFACTORY_DOCKER_URL_FOR_PREPARE_RIAS_RELEASE_BUNDLE}/${RELEASE_BUNDLE_IMAGE_NAME}:${TAG_VALUE}"

if [[ ${ICR_MIGRATION_MODE} == true ]]
then
  PREPARED_BUNDLE_IMAGE_FULL_NAME_ICR="${ICR_URL_TO_PUSH_ON_PREPARE_RIAS_RELEASE_BUNDLE}/${RELEASE_BUNDLE_IMAGE_NAME}:${TAG_VALUE}"
fi

# If we are in OnePipeline, we write the full image name to a file to be used in next steps
# The reason we do this is because the naming does not include SHA, only SemVer
# And the default save artifacts logic relies either on SHA or explicit complete image name

if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
  IMG_FILE_FULL_NAME="${CI_NON_STANDARD_NAMING_IMAGES_DIR}/${PIPELINE_REPO_ORG}_${PIPELINE_REPO_NAME}"

  echo ${PREPARED_BUNDLE_IMAGE_FULL_NAME} > "${IMG_FILE_FULL_NAME}"
  echo "Succesfully created a file ${IMG_FILE_FULL_NAME} with the following content: "
  cat "${IMG_FILE_FULL_NAME}"

  if [[ ${ICR_MIGRATION_MODE} == true ]]
  then
    IMG_FILE_FULL_NAME_ICR="${CI_NON_STANDARD_NAMING_IMAGES_DIR}/${PIPELINE_REPO_ORG}_${PIPELINE_REPO_NAME}_${SUFFIX_FOR_ICR_SAVE_ARTIFACTS}"

    echo ${PREPARED_BUNDLE_IMAGE_FULL_NAME_ICR} > "${IMG_FILE_FULL_NAME_ICR}"
    echo "Succesfully created a file ${IMG_FILE_FULL_NAME_ICR} with the following content: "
    cat "${IMG_FILE_FULL_NAME_ICR}"
  fi
fi

set +e # If the image does not exist allow this to fail.
inspect_result=$(docker manifest inspect ${PREPARED_BUNDLE_IMAGE_FULL_NAME} > /dev/null)
statusCode=$?
set -e
if [[ "${statusCode}" -ne 0 ]]; then
  echo "Image tag was not found, continue pushing to ${ARTIFACTORY_DOCKER_URL_FOR_PREPARE_RIAS_RELEASE_BUNDLE}"
  echo "pushing docker image"
  docker push ${PREPARED_BUNDLE_IMAGE_FULL_NAME}
elif [[ "${ARTIFACTORY_DOCKER_URL_FOR_PREPARE_RIAS_RELEASE_BUNDLE}" = "wcp-genctl-stage-docker-local.artifactory.swg-devops.com" ]]; then
  echo "WARNING: Image tag was found, but the stage area is being used."
  echo "pushing docker image"
  docker push ${PREPARED_BUNDLE_IMAGE_FULL_NAME}
else
  echo "WARNING: Image tag was found, skipping the push to ${ARTIFACTORY_DOCKER_URL_FOR_PREPARE_RIAS_RELEASE_BUNDLE}"
fi

if [[ ${ICR_MIGRATION_MODE} == true ]]
then
  # Login to ibmcloud using function defined in ibmcloud_utils.sh
  ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"
  ibmcloud cr login

  set +e # If the image does not exist allow this to fail.
  inspect_result=$(docker manifest inspect ${PREPARED_BUNDLE_IMAGE_FULL_NAME_ICR} > /dev/null)
  statusCode=$?
  set -e
  if [[ "${statusCode}" -ne 0 ]]; then
    echo "Image tag was not found, continue pushing to ${ICR_URL_TO_PUSH_ON_PREPARE_RIAS_RELEASE_BUNDLE}"
    echo "pushing docker image"
    docker push ${PREPARED_BUNDLE_IMAGE_FULL_NAME_ICR}
  elif [[ "${ICR_URL_TO_PUSH_ON_PREPARE_RIAS_RELEASE_BUNDLE}" = "${VPC_ICR_SANDBOX_URL}" ]]; then
    echo "WARNING: Image tag was found, but the ICR sandbox is being used."
    echo "pushing docker image"
    docker push ${PREPARED_BUNDLE_IMAGE_FULL_NAME_ICR}
  else
    echo "WARNING: Image tag was found, skipping the push to ${ICR_URL_TO_PUSH_ON_PREPARE_RIAS_RELEASE_BUNDLE}"
  fi
fi

echo ${RELEASE_BUNDLE_IMAGE_NAME}:${TAG_VALUE} >> ${PATH_TO_WORKSPACE_REPO}/high_level_release_bundles_build_info.txt