#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="cd"

# Define type of pipeline (Used to search overrides)
# Also used to export PR info for the CD promotion pipeline in one_pipeline_utils.sh
# Some promotion pipelines use the non-standard PIPELINE_TYPE as 'promotion'
if [[ "${PIPELINE_REPO_NAME}" == *prod ]] || [[ "${PIPELINE_REPO_NAME}" == "staging" ]]; then
  PIPELINE_TYPE="promotion"
else
  PIPELINE_TYPE="pr"
fi
echo "PIPELINE_TYPE is ${PIPELINE_TYPE}"

# Define the repositories to be cloned
REPOS_TO_CLONE="
RIAS_GLOBALS
GENCTL_VETTED_VERSIONS
"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Clone required repos
clone_repos_from_env_vars "${IBM_HTTPS_BASE_URL}" "${WORKSPACE}" "${REPOS_TO_CLONE}"

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_VETTED_VERSIONS_REPO="${WORKSPACE}/${GENCTL_VETTED_VERSIONS_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Get the parent pipeline info to pass it to the sub-pipeline
get_parent_pipeline_info

# Download the promotion tar file and unzip for the promotion tests
pushd ${WORKSPACE}
export PROMOTION_TAR_FILE="promotion_${PARENT_PIPELINE_RUN_ID}.tar.gz"
export PROMOTION_TAR_PATH="${WORKSPACE}/${PROMOTION_TAR_FILE}"

URL_TO_DOWNLOAD="${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/genctl-cd/ci-promotion-tests/${PROMOTION_TAR_FILE}"

echo "Downloading ${URL_TO_DOWNLOAD}"
download_file_from_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${URL_TO_DOWNLOAD}" "${PROMOTION_TAR_FILE}"

if [ ! -f "${PROMOTION_TAR_FILE}" ]; then
  echo "ERROR: Failed to download promotion tar file from ${URL_TO_DOWNLOAD}"
  exit 1
fi

echo "Extracting promotion tar file..."
tar -xzvf "${PROMOTION_TAR_FILE}"
export PROMOTION_OUTPUT="${WORKSPACE}/promotion"

# Verify the promotion directory exists and has content
if [ ! -d "${PROMOTION_OUTPUT}" ]; then
  echo "ERROR: PROMOTION_OUTPUT directory does not exist after tar extraction!"
  echo "Contents of ${WORKSPACE}:"
  ls -la "${WORKSPACE}"
  exit 1
fi

echo "Promotion workspace extracted successfully. Contents:"
ls -la "${PROMOTION_OUTPUT}"

popd

# Actual execution of Promotion tests
${PATH_TO_GENCTL_CI}/scripts/run_promotion_tests.sh
