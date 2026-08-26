#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script checks the vetted files exist and do some basic validations to it
# This script is intended to be used in the pr to master pipeline (For razee)

# For non-razee can be used as an additional check through the pipeline before to proceed to the download

# For razee, if this check fails it can be either one of these options:

#   1) The merge to dev-int pipeline didn't finish 
#      therefore the vetted files are not in place
#
#   2) The merge to dev-int pipeline finished but it didn't succesfully completed all the stages
#      therefore the vetted files are not in place
#   
#   3) The vetted files are in place but for some reason the download fails
#   
#   4) The vetted files are in place, download is OK but something is not OK on the files content

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, ORG_AND_REPO, SKIP_CHECK_VETTED_FILES
# PIPELINE_TEMPLATE_TYPE
# ARTIFACTORY_BASE_URL, CC_ARTIF_ACCESS_TOKEN
# ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH
# CANDIDATE_FILES_VETTED_DIR
# CANDIDATE_FILES_JSON_FILE_NAME_PREFIX, CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX

# In additional the following variables are optional and if not have values they will take the default
CHECK_VETTED_FILES_DRY_RUN=${CHECK_VETTED_FILES_DRY_RUN:-"false"}
# Since the function of download waits 2.5 seconds between retries, the math is the following: 
# 1440 X 2.5 seconds = 3600 seconds = 60 minutes = 1 hour
CHECK_VETTED_FILES_DOWNLOAD_RETRIES=${CHECK_VETTED_FILES_DOWNLOAD_RETRIES:-"1440"}
CHECK_VETTED_FILES_SPECIFIC_SHA=${CHECK_VETTED_FILES_SPECIFIC_SHA:-""}

# Source required utils
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/candidate_files_utils.sh
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Skip if needed
generic_skip $SKIP_CHECK_VETTED_FILES

# Either take the current SHA of the dev integration head or use a hardcoded one that we got as param
if [ -z "${CHECK_VETTED_FILES_SPECIFIC_SHA}" ]
then
    GIT_SHA=$(load_repo app-repo commit)
else
    GIT_SHA=${CHECK_VETTED_FILES_SPECIFIC_SHA}
fi

# Some information for the user
if [[ "${PIPELINE_TEMPLATE_TYPE}" == "razee" ]]
then
    echo "This script checks that the inventory JSON and ZIP file are on place for commit ${GIT_SHA}"
    echo "If we need to retry it means either one of the following options:"
    echo "A) The merge to dev-integration pipeline didn't finish, therefore the vetted files are not in place yet"
    echo "B) The merge to dev-integration pipeline finished but it didn't succesfully completed all the stages, therefore the vetted files are not in place"
    echo "Since we can't be certain about what is the issue, in case after this message you see a lot of retries, check what is the status of the merge to dev-integration pipeline"
fi

# Take a "shorter" version of the SHA
SHORT_SHA=${GIT_SHA:0:12}

# Set base path to check
BASE_PATH_TO_CHECK="${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_VETTED_DIR}/${ORG_AND_REPO}"

# Move to the TMP folder 
pushd "${CI_TEMP_DIR}"

### JSON FILE ###

# Set the name of the file
JSON_FILE_NAME="${CANDIDATE_FILES_JSON_FILE_NAME_PREFIX}_${SHORT_SHA}.json"

# Set URL
URL_JSON_DOWNLOAD="${BASE_PATH_TO_CHECK}/${JSON_FILE_NAME}"

if [[ $CHECK_VETTED_FILES_DRY_RUN = true ]]; then
    echo "DRY RUN MODE !!! - We would have tried to download: ${URL_JSON_DOWNLOAD}"
else
    echo "Will check that the following JSON file exist: ${URL_JSON_DOWNLOAD}"

    # Actual download
    download_file_from_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${URL_JSON_DOWNLOAD}" "${JSON_FILE_NAME}" ${CHECK_VETTED_FILES_DOWNLOAD_RETRIES}

    # At this point we should have the JSON file
    # Do some basic validations on it
    check_inventory_json_file "${PIPELINE_TEMPLATE_TYPE}" "${PWD}/${JSON_FILE_NAME}" 

    # Extra check due to _true_image issue
    if grep -q '_true_image' "${PWD}/${JSON_FILE_NAME}"
    then
        echo "Found images with the issue of _true_image"
        echo "In order to fix this please re-run the merge to dev-integration pipeline and then re-run PR to master"
        echo "Will exit with error..."
        exit 1
    fi
fi

# We deal with the ZIP file only for razee and globals
if [[ "${PIPELINE_TEMPLATE_TYPE}" == "razee" ]] || [[ "${PIPELINE_TEMPLATE_TYPE}" == "globals" ]]
then

    ### ZIP FILE ###

    # Set the name of the file
    ZIP_FILE_NAME="${CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX}_${SHORT_SHA}.zip"

    # Set URL
    URL_ZIP_DOWNLOAD="${BASE_PATH_TO_CHECK}/${ZIP_FILE_NAME}"

    if [[ $CHECK_VETTED_FILES_DRY_RUN = true ]]; then
        echo "DRY RUN MODE !!! - We would have tried to download: ${URL_ZIP_DOWNLOAD}"
    else
        echo "Will check that the following ZIP file exist: ${URL_ZIP_DOWNLOAD}"

        # Actual download
        download_file_from_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${URL_ZIP_DOWNLOAD}" "${ZIP_FILE_NAME}" ${CHECK_VETTED_FILES_DOWNLOAD_RETRIES}
    fi
fi

# Come back
popd
