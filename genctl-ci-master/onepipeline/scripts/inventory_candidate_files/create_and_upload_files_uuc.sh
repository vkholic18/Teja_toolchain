#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script simply copies the ZIP file and pushes the inventory file without processing or merging
# Unlike create_and_upload_files_uuc.sh, this script does NOT:
# - Download the ZIP file
# - Process or merge inventory JSON files
# - Generate deployment metadata

# The files are simply copied/uploaded as-is:
# 1. ZIP file - copied from source to destination in Artifactory
# 2. JSON inventory file - uploaded directly to Artifactory

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO, CI_TEMP_DIR, ORG_AND_REPO, PIPELINE_TEMPLATE_TYPE
# ARTIFACTORY_BASE_URL, ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH, CANDIDATE_FILES_PRE_RELEASE_DIR, CC_ARTIF_ACCESS_TOKEN
# CANDIDATE_FILES_JSON_FILE_NAME_PREFIX, CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX
# CANDIDATE_FILES_SKIP_UPLOAD

# Optional variables with defaults
CREATE_AND_UPLOAD_CANDIDATE_FILES_DRY_RUN=${CREATE_AND_UPLOAD_CANDIDATE_FILES_DRY_RUN:-"false"}
SKIP_DEPLOYMENT_FILES_ZIP=${SKIP_DEPLOYMENT_FILES_ZIP:-"false"}

# Source required utils
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/candidate_files_utils.sh
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Get the SHA
GIT_SHA=$(load_repo app-repo commit)

# Take a "shorter" version of the SHA
SHORT_SHA=${GIT_SHA:0:12}

# Create a directory that will hold the files
TMP_DIR="${CI_TEMP_DIR}/candidate_files"
mkdir -p "${TMP_DIR}"

# Set the basic path in artifactory
BASIC_PATH_IN_ARTIFACTORY="${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_PRE_RELEASE_DIR}/${ORG_AND_REPO}"

FROM="${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_PRE_RELEASE_DIR}/${ORG_AND_REPO}/${LAST_COMMIT_ASSOCIATED_PR_NUMBER}"
TO="${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_PRE_RELEASE_DIR}/${ORG_AND_REPO}"

ZIP_FILE_NAME="${CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX}_${SHORT_SHA}.zip"
JSON_FILE_NAME="${CANDIDATE_FILES_JSON_FILE_NAME_PREFIX}_${SHORT_SHA}.json"

echo "=========================================="
echo "Simple Move and Upload Script"
echo "=========================================="
echo "Short SHA: ${SHORT_SHA}"
echo "ZIP File Name: ${ZIP_FILE_NAME}"
echo "JSON File Name: ${JSON_FILE_NAME}"
echo "=========================================="

# Handle ZIP file copy (if applicable)
if [[ "${PIPELINE_TEMPLATE_TYPE}" == "uuc-ci" ]] && [[ "${SKIP_DEPLOYMENT_FILES_ZIP}" != "true" ]]
then
    echo "Checking for deployment ZIP file to copy..."

    SOURCE_ZIP_PATH="${FROM}/deployment_files.zip"
    DESTINATION_ZIP_PATH="${TO}/${ZIP_FILE_NAME}"

    # Check if source ZIP exists
    if file_exists_in_artifactory ${CC_ARTIF_ACCESS_TOKEN} ${ARTIFACTORY_BASE_URL} ${SOURCE_ZIP_PATH}
    then
        echo "Source deployment ZIP found at ${SOURCE_ZIP_PATH}"

        if [[ $CREATE_AND_UPLOAD_CANDIDATE_FILES_DRY_RUN = true ]]; then
            echo "DRY RUN MODE !!! - Would copy ZIP from: ${SOURCE_ZIP_PATH}"
            echo "DRY RUN MODE !!! - Would copy ZIP to: ${DESTINATION_ZIP_PATH}"
        else
            echo "Copying ZIP file in Artifactory..."
            copy_in_artifactory ${CC_ARTIF_ACCESS_TOKEN} ${ARTIFACTORY_BASE_URL} "${SOURCE_ZIP_PATH}" "${DESTINATION_ZIP_PATH}"
            echo "ZIP file copied successfully to: ${DESTINATION_ZIP_PATH}"
        fi
    elif file_exists_in_artifactory ${CC_ARTIF_ACCESS_TOKEN} ${ARTIFACTORY_BASE_URL} ${DESTINATION_ZIP_PATH}
    then
        echo "Source ZIP not found at ${SOURCE_ZIP_PATH}"
        echo "ZIP file already exists at destination: ${DESTINATION_ZIP_PATH}"
        echo "Skipping copy operation (likely already copied in a previous run)."
    else
        echo "No ZIP file to process."
        echo "ZIP not found at source (${SOURCE_ZIP_PATH}) or destination (${DESTINATION_ZIP_PATH})."
        echo "This is acceptable - proceeding without ZIP file."
    fi
else
    if [[ "${SKIP_DEPLOYMENT_FILES_ZIP}" == "true" ]]; then
        echo "SKIP_DEPLOYMENT_FILES_ZIP is set to true. Skipping ZIP file operations."
    else
        echo "PIPELINE_TEMPLATE_TYPE is not 'uuc-ci'. Skipping ZIP file operations."
    fi
fi

# Handle JSON inventory file creation and upload
echo ""
echo "Creating inventory JSON file from artifacts..."

# Move to the TMP dir
pushd ${TMP_DIR}

# Initially set the repo name for app_artifacts section
art_name_app_art_section=${PIPELINE_REPO_NAME}

### ARTIFACTS ###

# Create artifacts file from saved artifacts
ARTIFACTS_FILE_NAME="tmp_artifacts.json"

echo "Creating artifacts file..."
create_artifacts_file ${ARTIFACTS_FILE_NAME} "${art_name_app_art_section}"

# Verify the artifacts file was created successfully
if [[ ! -f "${ARTIFACTS_FILE_NAME}" ]]
then
    echo "ERROR: Could not find created file ${ARTIFACTS_FILE_NAME} in ${PWD}"
    echo "Will exit with error..."
    exit 1
fi

echo "Artifacts file created successfully"

# Create artifacts and commons file
ARTIFACTS_AND_COMMONS_FILE_NAME="tmp_artifacts_and_commons.json"

# Set the right pipeline build number and pipeline run id
if [ ! -z "${PARENT_PIPELINE_BUILD_NUMBER}" ]
then
    BUILD_NUM="${PARENT_PIPELINE_BUILD_NUMBER}"
else
    BUILD_NUM="${BUILD_NUMBER}"
fi

if [ ! -z "${PARENT_PIPELINE_RUN_ID}" ]
then
    PIPELINE_RID="${PARENT_PIPELINE_RUN_ID}"
else
    PIPELINE_RID="${PIPELINE_RUN_ID}"
fi

echo "Adding common metadata to artifacts..."
create_artifacts_and_commons_file ${GIT_SHA} \
${ARTIFACTS_FILE_NAME} ${BUILD_NUM} ${PIPELINE_ID} ${PIPELINE_RID} ${ARTIFACTS_AND_COMMONS_FILE_NAME}

# Verify the artifacts_and_commons file was created successfully
if [[ ! -f "${ARTIFACTS_AND_COMMONS_FILE_NAME}" ]]
then
    echo "ERROR: Could not find created file ${ARTIFACTS_AND_COMMONS_FILE_NAME} in ${PWD}"
    echo "Will exit with error..."
    exit 1
fi

echo "Artifacts and commons file created successfully"

# For this simplified version, we just use the artifacts_and_commons file as the final JSON
# We do NOT merge with deployment metadata
echo "Using artifacts and commons as final inventory file (no deployment metadata merging)"
mv "${ARTIFACTS_AND_COMMONS_FILE_NAME}" "${JSON_FILE_NAME}"

# Remove temporary files
rm -f tmp_artifacts.json

echo "Inventory JSON file created: ${JSON_FILE_NAME}"

# Upload JSON file if not skipping
if [[ "${CANDIDATE_FILES_SKIP_UPLOAD}" == "true" ]]
then
    echo "Skipping upload of JSON file..."
else
    if [[ -f "${JSON_FILE_NAME}" ]]
    then
        URL_TO_UPLOAD_JSON="${BASIC_PATH_IN_ARTIFACTORY}/${JSON_FILE_NAME}"

        if [[ $CREATE_AND_UPLOAD_CANDIDATE_FILES_DRY_RUN = true ]]; then
            echo "DRY RUN MODE !!! - Would upload JSON to: ${URL_TO_UPLOAD_JSON}"
            echo "JSON file contents:"
            cat ${JSON_FILE_NAME}
        else
            echo "Uploading JSON file to Artifactory..."
            upload_file_to_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${URL_TO_UPLOAD_JSON}" "${JSON_FILE_NAME}"
            echo "JSON file uploaded successfully to: ${URL_TO_UPLOAD_JSON}"
        fi
    else
        echo "ERROR: Cannot upload - JSON file ${JSON_FILE_NAME} not found in ${PWD}"
    fi
fi

# Come back
popd

echo ""
echo "=========================================="
echo "Script execution completed"
echo "=========================================="
