#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================

# The following environment variables need to be set before executing the script:

#Required
# PATH_TO_RELEASE_ENVIRONMENT
# ARTIFACTORY_LOGIN, CC_ARTIF_ACCESS_TOKEN
# ARTIFACTORY_URL, ARTIFACTORY_SANDBOX_URL
# GHE_RO_TOKEN
# DDT_COMPONENT
# REPOSITORY
# MAKE_TARGET

set -exu

export PATH_TO_RELEASE_ENVIRONMENT=${PATH_TO_RELEASE_ENVIRONMENT:-""}

export ARTIFACTORY_SANDBOX_URL=${ARTIFACTORY_SANDBOX_URL:-""}
export ARTIFACTORY_URL=${ARTIFACTORY_URL:-""}
export DDT_COMPONENT=${DDT_COMPONENT:-""}
export REPOSITORY=${REPOSITORY:-""}
export MAKE_TARGET=${MAKE_TARGET:-"build"}

export PR_HEADSHA=${PR_HEADSHA:-""}

# OnePipeline related
export IS_ONE_PIPELINE_RUN=${IS_ONE_PIPELINE_RUN:-"false"} # By default we consider not being a OnePipeline run, OnePipeline runs override to true
export CI_TEMP_DIR=${CI_TEMP_DIR:-""}

# Check if release environment dir exists, and if not create it
# In Concourse this should always exists, as it is an output of the YAML task
# In OnePipeline, should be created

if [[ ! -d "${PATH_TO_RELEASE_ENVIRONMENT}" ]]
then
  mkdir -p "${PATH_TO_RELEASE_ENVIRONMENT}"
fi

# Login to the artifactory where make will get TOOLS_DOCKER_IMAGE
set +x  # so we don't log the password
echo "login to ${ARTIFACTORY_SANDBOX_URL} ..."
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login -u ${ARTIFACTORY_LOGIN} --password-stdin ${ARTIFACTORY_SANDBOX_URL}

# export the GHE_RO_TOKEN if set
if [[ ! -z "${GHE_RO_TOKEN:-}" ]]; then
  export GHE_RO_TOKEN
fi
set -x

# Move to the workspace repo
pushd ${PATH_TO_WORKSPACE_REPO}

# Build the docker image
DOCKER_OPTS="--no-cache" make "${MAKE_TARGET}"

# filters docker images by those that match the repository, and only returns the tags of those that match
# (without headers), then pipes it into grep which inverse searches on latest, thus giving us the tag we want
echo REPOSITORY: ${REPOSITORY}
TAG_VALUE=$(docker images --filter=reference=${REPOSITORY}':*' --format "{{.Tag}}" | grep -v "latest")

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
docker tag ${REPOSITORY}:${ORIG_TAG_VALUE} ${ARTIFACTORY_URL}/${DDT_COMPONENT}/${REPOSITORY}:${TAG_VALUE}

# Login to the artifactory where we will push the image
set +x  # so we don't log the password
echo "login to ${ARTIFACTORY_URL} ..."
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login -u ${ARTIFACTORY_LOGIN} --password-stdin ${ARTIFACTORY_URL}
set -x

# Save the full image name in a variable
PREPARED_BUNDLE_IMAGE_FULL_NAME="${ARTIFACTORY_URL}/${DDT_COMPONENT}/${REPOSITORY}:${TAG_VALUE}"

# If we are in OnePipeline, we write the full image name to a file to be used in next steps
if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
  echo ${PREPARED_BUNDLE_IMAGE_FULL_NAME} > "${CI_TEMP_DIR}/prepared_bundle_image_full_name.txt"
fi

# Push the image to artifactory

set +e # If the image does not exist allow this to fail.
inspect_result=$(docker manifest inspect ${PREPARED_BUNDLE_IMAGE_FULL_NAME} > /dev/null)
statusCode=$?
set -e
if [[ "${statusCode}" -ne 0 ]]; then
  echo "Image tag was not found, continue pushing to ${ARTIFACTORY_URL}"
  echo "pushing docker image"
  echo "debug skip"
  docker push ${PREPARED_BUNDLE_IMAGE_FULL_NAME}
else
  echo "WARNING: Image tag was found, skipping the push to ${ARTIFACTORY_URL}"
fi
# Logout
set +e  # continue anyway if these fail
docker logout $ARTIFACTORY_SANDBOX_URL
docker logout $ARTIFACTORY_URL

# Move back
popd


