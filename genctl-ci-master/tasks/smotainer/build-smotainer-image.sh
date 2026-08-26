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
# LAST_RELEASE_TAG
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

#checkout to the last tag
git checkout ${LAST_RELEASE_TAG}

# Determine if tag points to a commit on REMOTE_BRANCH
if ! git rev-list --first-parent ${REMOTE_BRANCH} | grep ${RELEASE_TAG_SHA} >/dev/null; then
  echo ${LAST_RELEASE_TAG} not from ${REMOTE_BRANCH}; Exiting ...
  exit 1
fi

ALL_LOWER_LAST_RELEASE_TAG=$(tr '[A-Z]' '[a-z]' <<< $LAST_RELEASE_TAG)
FULL_IMAGENAME=${DOCKER_REG}/${CSI_NAMESPACE}/${DOCKER_NAME}-${ALL_LOWER_LAST_RELEASE_TAG}:${RELEASE_TAG_SHA}
NEW_IMAGENAME=${DOCKER_REG}/${CSI_NAMESPACE}/smotainer-${REMOTE_BRANCH}:${RELEASE_TAG_SHA}

set +x  # so we will not log the password
echo "loging in ${DOCKER_REG}"
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${DOCKER_REG} -u ${ARTIFACTORY_USER} --password-stdin
echo "loging in ${ARTIFACTORY_DOCKER_PROXY_URL}"
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_PROXY_URL} -u ${ARTIFACTORY_USER} --password-stdin
set -x

cd ${PATH_TO_WORKSPACE_REPO}/tools/smotainer
make REMOTE_BRANCH=$LAST_RELEASE_TAG build

echo "smotainer build completed"

# tag and push to ${DOCKER_REG}
docker tag ${FULL_IMAGENAME} ${NEW_IMAGENAME}
check_if_exist_and_push ${NEW_IMAGENAME} ${DOCKER_REG}

if [[ "${ICR_MIGRATION_MODE}" == "true" ]]; then
    echo "push smotainer image to ICR sandbox"
    NEW_IMAGENAME_ICR_SANDBOX=${DOCKER_REG_ICR_SANDBOX}/${CSI_NAMESPACE}/smotainer-${REMOTE_BRANCH}:${RELEASE_TAG_SHA}
    set +x
    # Login to ibmcloud using function defined in ibmcloud_utils.sh
    ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"
    set -x

    ibmcloud cr login
    docker tag ${FULL_IMAGENAME} ${NEW_IMAGENAME_ICR_SANDBOX}
    check_if_exist_and_push ${NEW_IMAGENAME_ICR_SANDBOX} ${DOCKER_REG_ICR_SANDBOX}
else
   echo "skip pushing to ICR"
fi
