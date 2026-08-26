#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2024
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# The following environment variables need to be set before executing the script:

#Required
# RELEASE_TAG_SHA
# REMOTE_BRANCH (aka INTEGRATION_TESTING_BRANCH)
# CC_ARTIF_ACCESS_TOKEN
# DOCKER_REG (aka ARTIFACTORY_DOCKER_STAGING_URL)

# Source the ibmcloud_utils.sh
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

export COPY_SMOTAINER_DRY_RUN_MODE=${COPY_SMOTAINER_DRY_RUN_MODE:-"false"}
echo COPY_SMOTAINER_DRY_RUN_MODE: ${COPY_SMOTAINER_DRY_RUN_MODE}
echo ICR_MIGRATION_MODE: ${ICR_MIGRATION_MODE}
set -ex

function check_if_exist_and_push(){
  IMAGE_PATH=$1
  BASE_DOCKER_REGISTRY=$2
  set +e # If the image does not exist allow this to fail.
  inspect_result=$(docker manifest inspect ${IMAGE_PATH} > /dev/null)
  statusCode=$?
  set -e
  if [[ "${statusCode}" -ne 0 ]]; then
    echo "Image tag was not found, continue pushing to ${BASE_DOCKER_REGISTRY}"
    if [[ ${COPY_SMOTAINER_DRY_RUN_MODE} = true ]]; then
        echo "DRY RUN MODE !!! - We would have run: docker push ${IMAGE_PATH}"
    else
      docker push ${IMAGE_PATH}
    fi
  else
    echo "WARNING: Image tag was found, skipping the push to ${BASE_DOCKER_REGISTRY}"
  fi
}

echo PATH_TO_WORKSPACE_REPO: ${PATH_TO_WORKSPACE_REPO}
cd ${PATH_TO_WORKSPACE_REPO}

if [[ "${ICR_MIGRATION_MODE}" == "true" ]]; then
  set +x
  # Login to ibmcloud using function defined in ibmcloud_utils.sh
  ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"
  set -x
  SMOTAINER_SANDBOX_IMAGE=${DOCKER_REG_ICR_SANDBOX}/${CSI_NAMESPACE}/smotainer-${REMOTE_BRANCH}:${RELEASE_TAG_SHA}
else
  set +x  # so we will not log the password
  echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${DOCKER_REG} -u ${ARTIFACTORY_USER} --password-stdin
  set -x
  SMOTAINER_SANDBOX_IMAGE=${DOCKER_REG}/${CSI_NAMESPACE}/smotainer-${REMOTE_BRANCH}:${RELEASE_TAG_SHA}
fi

#pull smotainer image from ${DOCKER_REG}
echo "pulling image from ${SMOTAINER_SANDBOX_IMAGE}"
docker pull ${SMOTAINER_SANDBOX_IMAGE}

mkdir -p ${WORKSPACE}/release-environment
BUILD_TIME=`date -u +"%Y%m%dT%H%M%SZ"`
TAG_VALUE=${BUILD_TIME}_${RELEASE_TAG_SHA}
echo "${TAG_VALUE}" > ${PATH_TO_RELEASE_ENVIRONMENT}/build_tag
cat ${PATH_TO_RELEASE_ENVIRONMENT}/build_tag

# tag and push to ${ARTIFACTORY_DOCKER_URL}
SMOTAINER_PROD_IMAGE=${ARTIFACTORY_DOCKER_URL}/${CSI_NAMESPACE}/smotainer-${REMOTE_BRANCH}:${TAG_VALUE}
docker tag ${SMOTAINER_SANDBOX_IMAGE} ${SMOTAINER_PROD_IMAGE}
set +x  # so we will not log the password
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_URL} -u ${ARTIFACTORY_USER} --password-stdin
set -x

check_if_exist_and_push ${SMOTAINER_PROD_IMAGE} ${ARTIFACTORY_DOCKER_URL}

if [[ "${ICR_MIGRATION_MODE}" == "true" ]]; then
    echo "push smotainer image to ICR prod and backup"
    NEW_IMAGENAME_ICR=${DOCKER_REG_ICR}/${CSI_NAMESPACE}/smotainer-${REMOTE_BRANCH}:${TAG_VALUE}
    NEW_IMAGENAME_ICR_BACKUP=${DOCKER_REG_ICR_BACKUP}/${CSI_NAMESPACE}/smotainer-${REMOTE_BRANCH}:${TAG_VALUE}
    set +x
    # Login to ibmcloud using function defined in ibmcloud_utils.sh
    ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"
    set -x

    ibmcloud cr login

    docker tag ${SMOTAINER_SANDBOX_IMAGE} ${NEW_IMAGENAME_ICR}
    check_if_exist_and_push ${NEW_IMAGENAME_ICR} ${DOCKER_REG_ICR}

    # Push to backup ICR registry
    export ICR_PUSH_BACKUP_REGISTRY_REGION="eu-gb"
    if [[ ! -z "${ICR_PUSH_BACKUP_REGISTRY_REGION}" ]]
    then
        echo "Will change IBM Cloud target to ${ICR_PUSH_BACKUP_REGISTRY_REGION}"
        ibmcloud target -r ${ICR_PUSH_BACKUP_REGISTRY_REGION}
        ibmcloud cr login

        docker tag ${SMOTAINER_SANDBOX_IMAGE} ${NEW_IMAGENAME_ICR_BACKUP}
        check_if_exist_and_push ${NEW_IMAGENAME_ICR_BACKUP} ${DOCKER_REG_ICR_BACKUP}
    fi
else
   echo "skip pushing to ICR"
fi
