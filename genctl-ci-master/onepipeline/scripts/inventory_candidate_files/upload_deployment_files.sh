#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script creates the JSON file with the inventory data
# In addition, if we have the hack/deploy/razee folder creates the ZIP file and also adds to the JSON information of metadata for deployment files
# This script is intended to be used in the merge to pr-master pipeline (In Razee) / merge pipeline for non-razee

# The files generated and uploaded are the following:

# 1 JSON file with the following content:
# 1 ZIP file with deployment files (For razee flows - as long as we don't explicitly skip it)

# An array of objects with information of the artifacts (Each object into the array represent information of one artifact)
# An object with the common params (Params that are used both for cocoa inventory add of image and deployment)
# An object with the metadata of the deployment file

# In order to shorten the length of the file names, we cut the sha to the first 12 characters

# As an example, if the sha is 587c431d476ceed9c90724e45ebc5c0e124a9d90 the new files will get create in the form of:


#|---- deployment_files_587c431d476c.zip

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO, CI_TEMP_DIR, ORG_AND_REPO, PIPELINE_TEMPLATE_TYPE
# CANDIDATE_FILES_PRE_RELEASE_DIR, CC_ARTIF_ACCESS_TOKEN
# CANDIDATE_FILES_VETTED_DIR, ZIP_FINAL_LOCATION_DIR
# CANDIDATE_FILES_JSON_FILE_NAME_PREFIX, CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX
# PARENT_PIPELINE_BUILD_NUMBER, PARENT_PIPELINE_RUN_ID
# DEPLOYMENT_FILES_SKIP_UPLOAD

# In additional the following variables are optional and if not have values they will take the default

DEPLOYMENT_FILES_EXTENSION_TO_ZIP=${DEPLOYMENT_FILES_EXTENSION_TO_ZIP:-'*.yaml'}
CREATE_DEPLOYMENT_FILES_DRY_RUN=${CREATE_DEPLOYMENT_FILES_DRY_RUN:-"false"}
SKIP_DEPLOYMENT_FILES_ZIP=${SKIP_DEPLOYMENT_FILES_ZIP:-"false"} # By default we do want to include the ZIP file

# Source required utils
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/candidate_files_utils.sh
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# First get the SHA (It will be used in different parts of this script), and cut it

# Get the SHA
GIT_SHA=$(load_repo app-repo commit)

# Take a "shorter" version of the SHA
SHORT_SHA=${GIT_SHA:0:12}

# Create a directory that will hold the created files
TMP_DIR="${CI_TEMP_DIR}/candidate_files"
mkdir -p "${TMP_DIR}"

# Set the basic path in artifactory
# Example: https://na.artifactory.swg-devops.com/artifactory/wcp-genctl-sandbox-generic-local/candidate_files/genctl/riaas/regional-storage
BASIC_PATH_IN_ARTIFACTORY="${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_PRE_RELEASE_DIR}/${ORG_AND_REPO}"

### ZIP FILE ###

# We deal with the ZIP file of the deployment data only for razee

if [[ "${PIPELINE_TEMPLATE_TYPE}" == "razee" ]] || [[ "${PIPELINE_TEMPLATE_TYPE}" == "hotfix-razee" ]]
then    
    # Zip file name
    ZIP_FILE_NAME="${CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX}_${SHORT_SHA}.zip"

    # Check if we have the directory with the files
    if [ -d "${PATH_TO_WORKSPACE_REPO}/${COS_UPLOAD_CONTENT_ROOT}" ]; then

        # Check if need to skip ZIP file
        if [[ "${SKIP_DEPLOYMENT_FILES_ZIP}" == "false" ]]
        then
            # Move to the TMP dir
            pushd ${TMP_DIR}

            # Create ZIP file
            zip -r ${ZIP_FILE_NAME} "${PATH_TO_WORKSPACE_REPO}/${COS_UPLOAD_CONTENT_ROOT}" -i ${DEPLOYMENT_FILES_EXTENSION_TO_ZIP}            
            popd
        else
            echo "It was explicitly required not to create ZIP file"
        fi
    else 
        echo "Warning: Could not find deployment files, ZIP file won't be created"
    fi
fi

# Move to the TMP dir
pushd ${TMP_DIR}

# Before proceeding to upload, perform some checks
check_deployment_file_before_upload "${PIPELINE_TEMPLATE_TYPE}"

if [[ "${DEPLOYMENT_FILES_SKIP_UPLOAD}" == "true" ]]
then
    echo "Skipping upload of files..."
else
    # If we have ZIP file, upload it
    if [[ -f "${ZIP_FILE_NAME}" ]]
    then
        URL_TO_UPLOAD_ZIP="${BASIC_PATH_IN_ARTIFACTORY}/${ZIP_FILE_NAME}"

        if [[ $CREATE_DEPLOYMENT_FILES_DRY_RUN = true ]]; then
            echo "DRY RUN MODE !!! - We would have uploaded to: ${URL_TO_UPLOAD_ZIP}..."
        else
            upload_file_to_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${URL_TO_UPLOAD_ZIP}" "${ZIP_FILE_NAME}"
        fi
    else
        echo "Could not find ${ZIP_FILE_NAME} in ${PWD}"
    fi
fi

# Come back
popd