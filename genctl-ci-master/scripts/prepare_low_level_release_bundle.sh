#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================

# The following environment variables need to be set before executing the script:

# PATH_TO_RELEASE_ENVIRONMENT
# ARTIFACTORY_LOGIN, CC_ARTIF_ACCESS_TOKEN
# ARTIFACTORY_URL, ARTIFACTORY_SANDBOX_URL
# GHE_RO_TOKEN
# COMPONENT
# PIPELINE_REPO_NAME
# MAKE_TARGET

set -exu

export PATH_TO_RELEASE_ENVIRONMENT=${PATH_TO_RELEASE_ENVIRONMENT:-""}

export ARTIFACTORY_SANDBOX_URL=${ARTIFACTORY_SANDBOX_URL:-""}
export ARTIFACTORY_URL=${ARTIFACTORY_URL:-""}
export ARTIFACTORY_PROD_URL=${ARTIFACTORY_PROD_URL:-""}

export PIPELINE_REPO_NAME=${PIPELINE_REPO_NAME:-""}
export MAKE_TARGET=${MAKE_TARGET:-"build"}
export ARTIF_USER=${ARTIF_USER:=""}

export PR_HEADSHA=${PR_HEADSHA:-""}

# OnePipeline related
export IS_ONE_PIPELINE_RUN=${IS_ONE_PIPELINE_RUN:-"false"} # By default we consider not being a OnePipeline run, OnePipeline runs override to true
export CI_TEMP_DIR=${CI_TEMP_DIR:-""}

# ICR Migration related
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh 

export ICR_MIGRATION_MODE=${ICR_MIGRATION_MODE:-"false"} # By default we are not pushing images to ICR
export ICR_URL_TO_PUSH_ON_PREPARE_LOW_LEVEL_RELEASE_BUNDLE=${ICR_URL_TO_PUSH_ON_PREPARE_LOW_LEVEL_RELEASE_BUNDLE:-""}

# Check if release environment dir exists, and if not create it
# In Concourse this should always exists, as it is an output of the YAML task
# In OnePipeline, should be created

if [[ ! -d "${PATH_TO_RELEASE_ENVIRONMENT}" ]]
then
  mkdir -p "${PATH_TO_RELEASE_ENVIRONMENT}"
fi

set +x
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login -u ${ARTIF_USER} --password-stdin ${ARTIFACTORY_PROD_URL} # Needed for Dockerfile to run
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login -u ${ARTIF_USER} --password-stdin ${ARTIFACTORY_SANDBOX_URL} # Needed for Dockerfile to run
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login -u ${ARTIF_USER} --password-stdin ${ARTIFACTORY_URL} # Needed for docker push command to run

echo "loging in ${ARTIFACTORY_DOCKER_PROXY_URL}"
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_PROXY_URL} -u ${ARTIF_USER} --password-stdin # Needed to pull proxy images

# export the GHE_RO_TOKEN if set
if [[ ! -z "${GHE_RO_TOKEN:-}" ]]; then
  export GHE_RO_TOKEN
fi
set -x

# Move to the workspace repo
pushd ${PATH_TO_WORKSPACE_REPO}

# build the docker image
DOCKER_OPTS="--no-cache" make "${MAKE_TARGET}"

# filters docker images by those that match the repository, and only returns the tags of those that match
# (without headers), then pipes it into grep which inverse searches on latest, thus giving us the tag we want
echo PIPELINE_REPO_NAME: ${PIPELINE_REPO_NAME}
TAG_VALUE=$(docker images --filter=reference=${PIPELINE_REPO_NAME}':*' --format "{{.Tag}}" | grep -v "latest")

# If this is a PR, adjust the TAG_VALUE to be the commit hash
ORIG_TAG_VALUE=$TAG_VALUE

# If we have something in PR_HEADSHA means that we are in a PR run
# Therefore, we override TAG_VALUE with the SHA of the PR
if [[ ! -z "${PR_HEADSHA}"  ]]
then
  TAG_VALUE=${PR_HEADSHA}
fi

echo "${TAG_VALUE}" > "${PATH_TO_RELEASE_ENVIRONMENT}/build_tag"

echo "Created file build_tag, under ${PATH_TO_RELEASE_ENVIRONMENT} with content: ${TAG_VALUE}"

# Re-tag the image for the artifactory where we will push it
if [[ "${APPLY_DMM_DEPLOY_PROCESS}" == true ]]
then
    docker tag ${PIPELINE_REPO_NAME}:${ORIG_TAG_VALUE} ${ARTIFACTORY_PROD_URL}/${COMPONENT}/${PIPELINE_REPO_NAME}:${TAG_VALUE}
else
    docker tag ${PIPELINE_REPO_NAME}:${ORIG_TAG_VALUE} ${ARTIFACTORY_URL}/${COMPONENT}/${PIPELINE_REPO_NAME}:${TAG_VALUE}
fi

if [[ ${ICR_MIGRATION_MODE} == true ]]
then
  docker tag ${PIPELINE_REPO_NAME}:${ORIG_TAG_VALUE} ${ICR_URL_TO_PUSH_ON_PREPARE_LOW_LEVEL_RELEASE_BUNDLE}/${COMPONENT}/${PIPELINE_REPO_NAME}:${TAG_VALUE}
fi

# List out the images we have in Concourse's log
docker images

# Save the full image name in a variable
if [[ "${APPLY_DMM_DEPLOY_PROCESS}" == true ]]
then
    PREPARED_BUNDLE_IMAGE_FULL_NAME="${ARTIFACTORY_PROD_URL}/${COMPONENT}/${PIPELINE_REPO_NAME}:${TAG_VALUE}"
else
    PREPARED_BUNDLE_IMAGE_FULL_NAME="${ARTIFACTORY_URL}/${COMPONENT}/${PIPELINE_REPO_NAME}:${TAG_VALUE}"
fi

if [[ ${ICR_MIGRATION_MODE} == true ]]
then
  PREPARED_BUNDLE_IMAGE_FULL_NAME_ICR="${ICR_URL_TO_PUSH_ON_PREPARE_LOW_LEVEL_RELEASE_BUNDLE}/${COMPONENT}/${PIPELINE_REPO_NAME}:${TAG_VALUE}"
fi

# If we are in OnePipeline, we write the full image name to a file to be used in next steps
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

# Push the image to artifactory
set +e # If the image does not exist allow this to fail.
inspect_result=$(docker manifest inspect ${PREPARED_BUNDLE_IMAGE_FULL_NAME} > /dev/null)
statusCode=$?
set -e
if [[ "${statusCode}" -ne 0 ]]; then
    echo "Image tag was not found, continue pushing to ${ARTIFACTORY_URL}"
    echo "pushing docker image"
    docker push ${PREPARED_BUNDLE_IMAGE_FULL_NAME}
else
    echo "WARNING: Image tag was found, skipping the push to ${ARTIFACTORY_URL}"
fi

if [[ ${ICR_MIGRATION_MODE} == true ]]
then
  # Login to ibmcloud using function defined in ibmcloud_utils.sh
  ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"
  ibmcloud cr login

  # Push the image to artifactory
  set +e # If the image does not exist allow this to fail.
  inspect_result=$(docker manifest inspect ${PREPARED_BUNDLE_IMAGE_FULL_NAME_ICR} > /dev/null)
  statusCode=$?
  set -e
  if [[ "${statusCode}" -ne 0 ]]; then
      echo "Image tag was not found, continue pushing to ${ICR_URL_TO_PUSH_ON_PREPARE_LOW_LEVEL_RELEASE_BUNDLE}"
      echo "pushing docker image"
      docker push ${PREPARED_BUNDLE_IMAGE_FULL_NAME_ICR}
  else
      echo "WARNING: Image tag was found, skipping the push to ${ICR_URL_TO_PUSH_ON_PREPARE_LOW_LEVEL_RELEASE_BUNDLE}"
  fi
fi

# Clean up credentials left in the container by the docker login command
rm -rf /root/.docker/config.json

# Logout
set +e  # continue anyway if these fail
docker logout $ARTIFACTORY_SANDBOX_URL
docker logout $ARTIFACTORY_URL
docker logout $ARTIFACTORY_PROD_URL

# Move back
popd
