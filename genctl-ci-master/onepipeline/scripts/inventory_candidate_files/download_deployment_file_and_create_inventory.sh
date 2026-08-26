#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script creates the JSON file with the inventory data
# This script is intended to be used in the pr to master pipeline (In Razee)

# The following files generated 

# 1 JSON file with the following content:

# An array of objects with information of the artifacts (Each object into the array represent information of one artifact)
# An object with the common params (Params that are used both for cocoa inventory add of image and deployment)
# An object with the metadata of the deployment file

# In order to shorten the length of the file names, we cut the sha to the first 12 characters

# As an example, if the sha is 587c431d476ceed9c90724e45ebc5c0e124a9d90 the new files in the artifactory would be in the form of:

# |-- wcp-genctl-sandbox-generic-local
#               |---- candidate_files
#                        |---- pre_release
#                                 |---- riaas
#                                          |----- regional-storage
#                                                     |---- deployment_files_587c431d476c.zip
#                                                     |---- inventory_587c431d476c.json

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO, CI_TEMP_DIR, ORG_AND_REPO, PIPELINE_TEMPLATE_TYPE
# ARTIFACTORY_BASE_URL, CC_ARTIF_ACCESS_TOKEN
# ZIP_FINAL_LOCATION_DIR
# CANDIDATE_FILES_JSON_FILE_NAME_PREFIX, CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX
# PARENT_PIPELINE_BUILD_NUMBER, PARENT_PIPELINE_RUN_ID

# Source required utils
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/candidate_files_utils.sh
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# First get the SHA (It will be used in different parts of this script), and cut it

# Get the SHA
# GIT_SHA=$(load_repo app-repo commit)
# echo "GIT_SHA from app-repo commit : ${GIT_SHA}"

# We need to use the Post Merge commit sha as app-repo commit sha provides the PR commit sha
pushd ${PATH_TO_WORKSPACE_REPO}
GIT_SHA=$(git rev-parse --verify HEAD)
popd
# Take a "shorter" version of the SHA
SHORT_SHA=${GIT_SHA:0:12}

# This logic is to handle the APP_ARTIFACTS section; basically if we have a feature flag that is the value, if not, we put the name of the repo

# Initially set the repo name
art_name_app_art_section=${PIPELINE_REPO_NAME}

# First check if we have pipeline.yaml file
if [[ -f "${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml" ]]
then
    # Then check if we have feature flag
    feature_flag=$(yq -r '.deployment.feature_flag | select(. != null)' "${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml")

    # If we have something in feature flag put it for the app_artifacts section
    if [[ ! -z ${feature_flag} ]]
    then
        echo "Found feature flag section in pipeline.yaml file with value ${feature_flag}"
        echo "Will be used in app_artifacts"
        art_name_app_art_section=${feature_flag}
    fi
fi

# Create a directory that will hold the created files
TMP_DIR="${CI_TEMP_DIR}/candidate_files"
mkdir -p "${TMP_DIR}"

### ZIP FILE ###

# We deal with the ZIP file of the deployment data only for razee

if [[ "${PIPELINE_TEMPLATE_TYPE}" == "razee" ]]
then
    # Deployment file location to download
    ZIP_FINAL_LOCATION_BASIC_PATH_IN_ARTIFACTORY="${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_GENERIC_REPO_PATH}/${ZIP_FINAL_LOCATION_DIR}/${ORG_AND_REPO}"
    # Zip file name
    ZIP_FILE_NAME="${CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX}_${SHORT_SHA}.zip"

    # Move to the TMP dir
    pushd ${TMP_DIR}

    # Actual download
    download_file_from_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${ZIP_FINAL_LOCATION_BASIC_PATH_IN_ARTIFACTORY}/${ZIP_FILE_NAME}" "${ZIP_FILE_NAME}"

    DEPLOYMENT_ARTIFACT_DIGEST="sha256:$(sha256sum "${ZIP_FILE_NAME}" | awk '{print $1}')"

    ### DEPLOYMENT METADATA ###

    # We create this temporarily as a separate file, later we will merge the content with the rest of the JSON content

    # Prepare file name
    TMP_DEPLOYMENT_METADATA_FILE_NAME="tmp_deployment_metadata.json"

    # Create the file
    create_deployment_metadata_file "${ZIP_FINAL_LOCATION_BASIC_PATH_IN_ARTIFACTORY}/${ZIP_FILE_NAME}" \
    ${DEPLOYMENT_ARTIFACT_DIGEST} "${PIPELINE_REPO_ORG}_${PIPELINE_REPO_NAME}_deployment" ${TMP_DEPLOYMENT_METADATA_FILE_NAME} "${art_name_app_art_section}"

    # Check the file was succesfully created
    if [[ ! -f "${TMP_DEPLOYMENT_METADATA_FILE_NAME}" ]]
    then
        echo "Could not find created file ${TMP_DEPLOYMENT_METADATA_FILE_NAME} in ${PWD}"
        echo "Will exit with error..."
        exit 1
    fi
    # Come back
    popd        
fi

### ARTIFACTS ###

JSON_FILE_NAME="${CANDIDATE_FILES_JSON_FILE_NAME_PREFIX}_${SHORT_SHA}.json"

# Important: This logic relies on the load_artifacts
# In other words, at this point, we should have already executed the relevant save_artifact

# Move to the TMP dir
pushd ${TMP_DIR}

# Prepare file name
ARTIFACTS_FILE_NAME="tmp_artifacts.json"

# Create file
create_artifacts_file_razee ${ARTIFACTS_FILE_NAME} "${art_name_app_art_section}"

# Verify the artifacts file was created succesfully
if [[ ! -f "${ARTIFACTS_FILE_NAME}" ]]
then
    echo "Could not find created file ${ARTIFACTS_FILE_NAME} in ${PWD}"
    echo "Will exit with error..."
    exit 1
fi

# Take the artifacts file as base and add the commons resulting in a new file

# Prepare file name
ARTIFACTS_AND_COMMONS_FILE_NAME="tmp_artifacts_and_commons.json"

# Set the right pipeline build number and pipeline run id
# Note: The pipeline id itself should be always the same no matter if we are on a "parent" or a sub-pipeline

# If we have PARENT (For example razee) we prefer it, if not, use current pipeline
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

# Create file that has the artifacts and common info
create_artifacts_and_commons_file ${GIT_SHA} \
${ARTIFACTS_FILE_NAME} ${BUILD_NUM} ${PIPELINE_ID} ${PIPELINE_RID} ${ARTIFACTS_AND_COMMONS_FILE_NAME}

# Verify the artifacts_and_commons file was created succesfully
if [[ ! -f "${ARTIFACTS_AND_COMMONS_FILE_NAME}" ]]
then
    echo "Could not find created file ${ARTIFACTS_AND_COMMONS_FILE_NAME} in ${PWD}"
    echo "Will exit with error..."
    exit 1
fi

# If we have both the artifacts_and_commons and the deployment_metadata files, we merge them
if [[ -f "${TMP_DEPLOYMENT_METADATA_FILE_NAME}" ]]
then
    echo "We have both ${TMP_DEPLOYMENT_METADATA_FILE_NAME} and ${ARTIFACTS_AND_COMMONS_FILE_NAME} files under ${PWD}"
    echo "Proceeding to merge JSON..."
    jq -s '.[0] * .[1]' \
    ${ARTIFACTS_AND_COMMONS_FILE_NAME} ${TMP_DEPLOYMENT_METADATA_FILE_NAME} > ${JSON_FILE_NAME} 
else
    echo "Could not find ${TMP_DEPLOYMENT_METADATA_FILE_NAME} file under ${PWD}"
    echo "Will move forward considering only ${ARTIFACTS_AND_COMMONS_FILE_NAME} file"

    # We only have the artifacts_and_commons so we consider it the final file
    mv "${ARTIFACTS_AND_COMMONS_FILE_NAME}" "${JSON_FILE_NAME}"
fi

# Remove temporary files
rm -rf tmp*

# List content
echo "After processing and discarding temporary files, this is the content of ${PWD}:"
ls -la

# Export for current shell
export INVENTORY_ADD_SKIP_DOWNLOAD_AND_USE_LOCAL_FILE="${TMP_DIR}/${JSON_FILE_NAME}"

# Also write to a file that can be sourced by the next script
echo "export INVENTORY_ADD_SKIP_DOWNLOAD_AND_USE_LOCAL_FILE='${TMP_DIR}/${JSON_FILE_NAME}'" > "${CI_TEMP_DIR}/inventory_file_path.sh"

# Come back
popd