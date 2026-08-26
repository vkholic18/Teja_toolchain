#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -o pipefail

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="false"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_VETTED_VERSIONS_REPO="${WORKSPACE}/${GENCTL_VETTED_VERSIONS_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"
# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Configure ssh agent for git - used to do a git fetch on tags to get the most updated tags
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts

echo PATH_TO_WORKSPACE_REPO: ${PATH_TO_WORKSPACE_REPO}
cd ${PATH_TO_WORKSPACE_REPO}

#get the last tag
export LAST_RELEASE_TAG=$(git describe --tags $(git rev-list --tags --max-count=1))
if [[ $? -ne 0 ]] ; then
  echo "Failed to obtain the last release tag from ${PATH_TO_WORKSPACE_REPO} Exiting ..."
  exit 1
else
  echo "Last release smotainer tag is ${LAST_RELEASE_TAG}"
fi
#get the release tag sha
export RELEASE_TAG_SHA=$(git rev-list -n 1 ${LAST_RELEASE_TAG})
if [[ $? -ne 0 ]] ; then
  echo "Failed to obtain the release tag sha for ${LAST_RELEASE_TAG} Exiting ..."
  exit 1
else
  echo "Release smotainer tag sha is ${RELEASE_TAG_SHA}"
fi

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_VETTED_VERSIONS_REPO=${WORKSPACE}/${GENCTL_VETTED_VERSIONS_REPO_NAME}
export PATH_TO_DEV_REGIONS_REPO=${WORKSPACE}/${DEV_REGIONS_REPO_NAME}

#
# validate that the image is not already released in vetted versions
#
# get latest smotainer release from vetted version
RELEASED_SMOTAINER_IMAGE_TAG=`yq -r '.version."smotainer-release"' ${VETTED_VERSION_REPO}/${GENCTL_VETTED_VERSIONS}`
echo RELEASED_SMOTAINER_IMAGE_TAG: ${RELEASED_SMOTAINER_IMAGE_TAG}
if [[ ${RELEASED_SMOTAINER_IMAGE_TAG} == *${RELEASE_TAG_SHA}* ]]; then
  echo "Smotainer image with last released tag: ${LAST_RELEASE_TAG} and sha: ${RELEASE_TAG_SHA} is already released in pre-integration vetted version. Exiting..."
  exit 0
else
  echo "Smotainer image with last released tag: ${LAST_RELEASE_TAG} and sha: ${RELEASE_TAG_SHA} is not found in pre-integration vetted version. Continue..."
  ### build smotainer image
  run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "BUILD_SMOTAINER_IMAGE" ${EXIT_ON_TASK_FAILURE} \
  ${PATH_TO_GENCTL_CI}/tasks/smotainer/build-smotainer-image.sh

  ### test smotainer image
  run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "TEST_SMOTAINER_IMAGE" ${EXIT_ON_TASK_FAILURE} \
  ${PATH_TO_GENCTL_CI}/scripts/run_workspace_tests.sh

  ### release smotainer image
  run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "RELEASE_SMOTAINER_IMAGE" ${EXIT_ON_TASK_FAILURE} \
   ${PATH_TO_GENCTL_CI}/tasks/smotainer/release-smotainer-image.sh

  run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "UPDATE_VETTED_VERSION" ${EXIT_ON_TASK_FAILURE} \
  ${PATH_TO_GENCTL_CI}/scripts/update-vetted-versions.sh

fi


