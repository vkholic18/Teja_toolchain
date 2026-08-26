#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script downloads the ZIP file and inventory JSON from their locations,
# merges them with deployment metadata, and uploads the improved inventory to vetted directory.

# The basic process is:
# 1) Download the inventory JSON file from pre_release directory
# 2) Check if deployment ZIP file exists and download it
# 3) Calculate SHA256 for the ZIP file
# 4) Generate deployment metadata JSON
# 5) Merge inventory JSON with deployment metadata JSON
# 6) Upload the merged/improved inventory JSON to vetted directory

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, CI_TEMP_DIR, ORG_AND_REPO
# ARTIFACTORY_BASE_URL, ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH, ARTIFACTORY_GENERIC_REPO_PATH
# CANDIDATE_FILES_PRE_RELEASE_DIR, CANDIDATE_FILES_VETTED_DIR, ZIP_FINAL_LOCATION_DIR
# CANDIDATE_FILES_JSON_FILE_NAME_PREFIX, CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX
# CC_ARTIF_ACCESS_TOKEN, PIPELINE_REPO_NAME, PIPELINE_REPO_ORG

# Optional variables with defaults
SKIP_DEPLOYMENT_FILES_ZIP=${SKIP_DEPLOYMENT_FILES_ZIP:-"false"}
DOWNLOAD_MERGE_UPLOAD_DRY_RUN=${DOWNLOAD_MERGE_UPLOAD_DRY_RUN:-"false"}

set -e

# Source utils
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/candidate_files_utils.sh

echo "=========================================="
echo "Download, Merge, and Upload Inventory Script"
echo "=========================================="

# Get the SHA
GIT_SHA=$(load_repo app-repo commit)

# Take a "shorter" version of the SHA
SHORT_SHA=${GIT_SHA:0:12}

echo "Short SHA: ${SHORT_SHA}"

# Create a temporary directory for processing
TMP_DIR="${CI_TEMP_DIR}/merge_inventory"
mkdir -p "${TMP_DIR}"

# Move to the TMP dir
pushd ${TMP_DIR}

# Set file names
ZIP_FILE_NAME="${CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX}_${SHORT_SHA}.zip"
JSON_FILE_NAME="${CANDIDATE_FILES_JSON_FILE_NAME_PREFIX}_${SHORT_SHA}.json"

# Set artifact name for app_artifacts section
art_name_app_art_section=${PIPELINE_REPO_NAME}

# Source paths
SOURCE_JSON_PATH="${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_VETTED_DIR}/${ORG_AND_REPO}/${JSON_FILE_NAME}"
ZIP_FINAL_LOCATION_BASIC_PATH="${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_GENERIC_REPO_PATH}/${ZIP_FINAL_LOCATION_DIR}/${ORG_AND_REPO}"
SOURCE_ZIP_PATH="${ZIP_FINAL_LOCATION_BASIC_PATH}/${ZIP_FILE_NAME}"

# Destination path for merged inventory
DESTINATION_JSON_PATH="${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_VETTED_DIR}/${ORG_AND_REPO}/${JSON_FILE_NAME}"

echo "Source JSON: ${SOURCE_JSON_PATH}"
echo "Source ZIP: ${SOURCE_ZIP_PATH}"
echo "Destination JSON: ${DESTINATION_JSON_PATH}"

# Download inventory JSON
echo ""
echo "Downloading inventory JSON..."
download_file_from_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${SOURCE_JSON_PATH}" "${JSON_FILE_NAME}"

# Verify the JSON file was downloaded successfully
if [[ ! -f "${JSON_FILE_NAME}" ]]
then
    echo "ERROR: JSON file ${JSON_FILE_NAME} was not downloaded successfully to ${PWD}"
    echo "Will exit with error..."
    exit 1
fi

echo "Inventory JSON downloaded successfully"

# Download and process ZIP file if not skipped
if [[ "${SKIP_DEPLOYMENT_FILES_ZIP}" != "true" ]]
then
    echo ""
    echo "Checking if deployment ZIP exists in Artifactory..."

    # Check if ZIP file exists at the expected location
    if file_exists_in_artifactory ${CC_ARTIF_ACCESS_TOKEN} ${ARTIFACTORY_BASE_URL} "${ARTIFACTORY_GENERIC_REPO_PATH}/${ZIP_FINAL_LOCATION_DIR}/${ORG_AND_REPO}/${ZIP_FILE_NAME}"
    then
        echo "Deployment ZIP found at ${SOURCE_ZIP_PATH}"
        echo "Downloading deployment ZIP..."
        download_file_from_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${SOURCE_ZIP_PATH}" "${ZIP_FILE_NAME}"

        # Verify the ZIP file was downloaded successfully
        if [[ ! -f "${ZIP_FILE_NAME}" ]]
        then
            echo "ERROR: ZIP file ${ZIP_FILE_NAME} was not downloaded successfully to ${PWD}"
            echo "Cannot proceed with deployment metadata creation."
            echo "Will exit with error..."
            exit 1
        fi

        echo "ZIP file downloaded successfully"

        # Calculate SHA256 for the ZIP file
        echo ""
        echo "Calculating SHA256 for deployment ZIP..."
        DEPLOYMENT_ARTIFACT_DIGEST="sha256:$(sha256sum "${ZIP_FILE_NAME}" | awk '{print $1}')"

        # Validate that we got a valid SHA256 hash
        if [[ -z "${DEPLOYMENT_ARTIFACT_DIGEST##sha256:}" ]]
        then
            echo "ERROR: Failed to calculate SHA256 for ${ZIP_FILE_NAME}"
            echo "SHA256 value is empty or invalid: ${DEPLOYMENT_ARTIFACT_DIGEST}"
            echo "Will exit with error..."
            exit 1
        fi

        echo "Successfully calculated SHA256 for deployment ZIP: ${DEPLOYMENT_ARTIFACT_DIGEST}"

        # Generate deployment metadata
        echo ""
        echo "Generating deployment metadata..."

        TMP_DEPLOYMENT_METADATA_FILE_NAME="tmp_deployment_metadata.json"

        # Use the ZIP final location path as the deployment artifact path
        create_deployment_metadata_file "${ZIP_FINAL_LOCATION_BASIC_PATH}/${ZIP_FILE_NAME}" \
        ${DEPLOYMENT_ARTIFACT_DIGEST} "${PIPELINE_REPO_ORG}_${PIPELINE_REPO_NAME}_deployment" ${TMP_DEPLOYMENT_METADATA_FILE_NAME} "${art_name_app_art_section}"

        # Check the file was successfully created
        if [[ ! -f "${TMP_DEPLOYMENT_METADATA_FILE_NAME}" ]]
        then
            echo "Could not find created file ${TMP_DEPLOYMENT_METADATA_FILE_NAME} in ${PWD}"
            echo "Will exit with error..."
            exit 1
        fi

        echo "Deployment metadata created successfully"

        # Merge inventory JSON with deployment metadata
        echo ""
        echo "Merging inventory JSON with deployment metadata..."
        MERGED_JSON_FILE_NAME="merged_${JSON_FILE_NAME}"

        jq -s '.[0] * .[1]' "${JSON_FILE_NAME}" "${TMP_DEPLOYMENT_METADATA_FILE_NAME}" > "${MERGED_JSON_FILE_NAME}"

        # Verify merge was successful
        if [[ ! -f "${MERGED_JSON_FILE_NAME}" ]]
        then
            echo "ERROR: Failed to create merged inventory file"
            echo "Will exit with error..."
            exit 1
        fi

        echo "Successfully merged inventory JSON with deployment metadata"

        # Use the merged file as the final file to upload
        FINAL_JSON_TO_UPLOAD="${MERGED_JSON_FILE_NAME}"

        # Clean up temporary files
        rm -f "${TMP_DEPLOYMENT_METADATA_FILE_NAME}"
        rm -f "${ZIP_FILE_NAME}"

    else
        echo "Deployment ZIP not found at ${SOURCE_ZIP_PATH}"
        echo "Skipping deployment metadata processing."
        # Use the original JSON file for upload
        FINAL_JSON_TO_UPLOAD="${JSON_FILE_NAME}"
    fi

else
    echo ""
    echo "SKIP_DEPLOYMENT_FILES_ZIP is set to true. Skipping ZIP download and deployment metadata processing."
    # Use the original JSON file for upload
    FINAL_JSON_TO_UPLOAD="${JSON_FILE_NAME}"
fi

# Upload the final inventory JSON to vetted directory
echo ""
echo "Uploading improved inventory JSON to vetted directory..."

if [[ $DOWNLOAD_MERGE_UPLOAD_DRY_RUN = true ]]; then
    echo "DRY RUN MODE !!!"
    echo "Would upload to: ${DESTINATION_JSON_PATH}"
    echo "File contents:"
    cat ${FINAL_JSON_TO_UPLOAD}
else
    upload_file_to_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${DESTINATION_JSON_PATH}" "${FINAL_JSON_TO_UPLOAD}"
    echo "Successfully uploaded improved inventory JSON to: ${DESTINATION_JSON_PATH}"
fi

# Come back
popd

# Clean up temporary directory
rm -rf "${TMP_DIR}"

echo ""
echo "=========================================="
echo "Script execution completed"
echo "=========================================="
