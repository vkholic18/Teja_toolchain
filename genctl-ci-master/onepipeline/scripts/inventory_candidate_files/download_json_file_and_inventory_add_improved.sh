#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script download the candidate file required to perform the cocoa inventory add commands
# This script is intended to be used in the merge to master pipeline

# The basic process is

# 1) Identify the dev-integration version that has equivalent content to the master version of the pipeline we are running on
# 2) Use the dev-integration SHA to download the inventory candidate file
# 3) Execute a python script that takes as input the candidate file (JSON) and generates a .SH script with the cocoa inventory add commands
# 4) Execute the script of step 3, this should run the actual cocoa inventory add commands

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO, CI_TEMP_DIR, REPO_MAIN_BRANCH, ORG_AND_REPO, PIPELINE_TEMPLATE_TYPE
# ARTIFACTORY_BASE_URL, ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH, CANDIDATE_FILES_VETTED_DIR, CC_ARTIF_ACCESS_TOKEN
# CANDIDATE_FILES_JSON_FILE_NAME_PREFIX

# Source the file if it exists
if [ -f "${CI_TEMP_DIR}/inventory_file_path.sh" ]; then
    source "${CI_TEMP_DIR}/inventory_file_path.sh"
fi

# In additional the following variables are optional and if not have values they will take the default
INVENTORY_ADD_SKIP_DOWNLOAD_AND_USE_LOCAL_FILE=${INVENTORY_ADD_SKIP_DOWNLOAD_AND_USE_LOCAL_FILE:-""}
INVENTORY_ADD_DOWNLOAD_SPECIFIC_URL=${INVENTORY_ADD_DOWNLOAD_SPECIFIC_URL:-""}
INVENTORY_ADD_DRY_RUN=${INVENTORY_ADD_DRY_RUN:-"false"}
OVERRIDE_ORG_RESTRICTION_INVENTORY_ADD=${OVERRIDE_ORG_RESTRICTION_INVENTORY_ADD:-"false"}
FINAL_INVENTORY_BRANCH_TO_UPDATE=${FINAL_INVENTORY_BRANCH_TO_UPDATE:-""}

set -e

# This includes or not the app_artifacts field for each artifact on the python script
export INCLUDE_ARTIFACT_APP_ARTIFACTS=${INCLUDE_ARTIFACT_APP_ARTIFACTS:-"false"}

# Source utils
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Skip if needed
generic_skip $SKIP_ONE_PIPELINE_INVENTORY_ADD

# Check if repo is production org & flag
if ! repo_is_from_prod_org ${PATH_TO_WORKSPACE_REPO}
then
    if [ "$OVERRIDE_ORG_RESTRICTION_INVENTORY_ADD" == "true" ]; then
        echo "Repo is not a production repo, however, OVERRIDE_ORG_RESTRICTION_INVENTORY_ADD is true, so proceeding to inventory add..."
    else
        echo "By default, inventory add is not enabled for organizations that are not 'production'"
        echo "It might be the case that your repository is a fork..."
        echo "If you want to run inventory add anyway, set OVERRIDE_ORG_RESTRICTION_INVENTORY_ADD flag to true" 
        exit 0
    fi
fi

# Don't proceed if there are errors
set -e

# Check if need to download or we work with an existing local file
if [ -z "${INVENTORY_ADD_SKIP_DOWNLOAD_AND_USE_LOCAL_FILE}" ]
then
    # Move to the TMP folder 
    pushd "${CI_TEMP_DIR}"

    # Set the name we will give to the file locally once downloaded
    INV_FILE="${PWD}/inventory.json"
    
    if [ -z "${INVENTORY_ADD_DOWNLOAD_SPECIFIC_URL}" ]
    then
        # If is razee, we need to find the equivalent dev-integration version
        if [[ "${PIPELINE_TEMPLATE_TYPE}" == "razee" ]]
        then
            if [[ ! -z "${RESULT_DEV_INT_SHA}" ]]
            then
                echo "Equivalent dev-integ SHA is: ${RESULT_DEV_INT_SHA}"

                # Since on the upload script we cut the SHA to the first 12 characters, we need to do the same here to find & download
                SHA_TO_CUT=${RESULT_DEV_INT_SHA}
            else
                echo "At this point, expected to have the equivalent dev-integ SHA on variable RESULT_DEV_INT_SHA, but is empty"
                echo "Will exit with error..."
                exit 1
            fi
        else
            # If is not razee we assume the .json file has same SHA than current run (Both files creation and download/inventory add happen in same pipeline rather than it two different pipelines)
            SHA_TO_CUT=$(load_repo app-repo commit)
        fi

        # Shorten the SHA
        SHORT_SHA=${SHA_TO_CUT:0:12}

        # Build the URL to download
        URL_FILE_TO_DOWNLOAD="${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_VETTED_DIR}/${ORG_AND_REPO}/${CANDIDATE_FILES_JSON_FILE_NAME_PREFIX}_${SHORT_SHA}.json"
    else
        URL_FILE_TO_DOWNLOAD=${INVENTORY_ADD_DOWNLOAD_SPECIFIC_URL}
    fi

    # Actual download
    download_file_from_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${URL_FILE_TO_DOWNLOAD}" "${INV_FILE}"
    
    # Move back
    popd
else
    # This mode is helpful for debugging/testing purposes, it just uses a local file
    INV_FILE=${INVENTORY_ADD_SKIP_DOWNLOAD_AND_USE_LOCAL_FILE}
    echo "Skipping download; will just use local file ${INV_FILE}"
fi

# If we made it to here, we have the file

# Export environment variables required for python script
export PATH_TO_INVENTORY_JSON_FILE=${INV_FILE}
export PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND="${CI_TEMP_DIR}/cocoa_command.json"

if [[ ! -z "${INVENTORY_ORG_SPECIFIC_FOR_DEBIAN}" ]] && [[ ! -z "${INVENTORY_REPO_SPECIFIC_FOR_DEBIAN}" ]]
then
    export PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND_SPECIAL_DEBIAN="${CI_TEMP_DIR}/cocoa_command_special_debian.json"
fi

# If we are on a low_level release bundle, need some special logic
if [[ "${PIPELINE_TEMPLATE_TYPE}" == "release_bundles" ]] && [[ "$LOW_LEVEL_RELEASE_BUNDLE_TYPES" =~ (^|[[:space:]])$COMPONENT($|[[:space:]]) ]]
then
    # At this point we can assume that we are on a release bundle, specifically low level
    # We can assume that we have only one artifact and then we do some cutting to extract the version
    # Example of version: 5.0.10-20240412T055937Z_6c94b81
        
    export VERSION_FIELD_VALUE=$(jq '.artifacts[0].artifact' "${PATH_TO_INVENTORY_JSON_FILE}" | cut -d '@' -f1 | cut -d ':' -f2)
else
    # Move to the repo 
    pushd "${PATH_TO_WORKSPACE_REPO}"

    # Get SemVer
    SEMVER=$(git describe --tags --exact-match --abbrev=0 2> /dev/null || true)

    # Come back
    popd

    #If we have something in SemVer, use it, if not, use N/A
    if [[ -n "${SEMVER}" ]]
    then
        export VERSION_FIELD_VALUE="${SEMVER}"
    else
        export VERSION_FIELD_VALUE="N/A"
    fi
fi

echo "For version field; we will use the value ${VERSION_FIELD_VALUE}"

# This logic is to figure out which is the final branch of inventory that needs to be updated

# Set the PIPELINE_RUN_BRANCH as master/repo_branch if it's a razee pr to master pipeline
if [[ "${PIPELINE_RUN_BRANCH}" == "temp_dev-integration_temp" && "${PIPELINE_TEMPLATE_TYPE}" == "razee" ]]; then
    PIPELINE_RUN_BRANCH="${REPO_MAIN_BRANCH}"
fi

if [[ "${PIPELINE_RUN_BRANCH}" != "${REPO_MAIN_BRANCH}" ]]
then
    # If the current branch we are running is different than the repo main branch (master/main) then 
    # we assume that the final inventory branch we want to update is a different branch of the inventory repo than the "default" one    
    if [[ $PIPELINE_RUN_BRANCH == *"stable"* ]]
        then
            # If the branch has the word stable we assume is in the format of SDN in which
            # The branches names are like stable-1.6, stable-1.5
            # we are excluding this branching strategy for hotfix-razee templates as razee hotfix branch has the word stable

            # This will extract only the number
            BRANCH_NUMBER=${PIPELINE_RUN_BRANCH#"stable-"}

            # At this point we should have things like 1.6, 1.5
            FINAL_INVENTORY_BRANCH_TO_UPDATE=${BRANCH_NUMBER}
    else
        # Assume that in the inventory repo there is a branch with same name than the branch that we are executing now
        FINAL_INVENTORY_BRANCH_TO_UPDATE=${PIPELINE_RUN_BRANCH}
    fi        
else
    FINAL_INVENTORY_BRANCH_TO_UPDATE="master"
fi

if [[ "${PIPELINE_TEMPLATE_TYPE}" == "hotfix-razee" ]];
then
    FINAL_INVENTORY_BRANCH_TO_UPDATE="master" #$REPO_MAIN_BRANCH
fi

export INVENTORY_BRANCH_TO_USE=${FINAL_INVENTORY_BRANCH_TO_UPDATE}

echo "Cocoa inventory add commands will be prepared against branch ${INVENTORY_BRANCH_TO_USE}..."
   
# Execute
python3 -m pip install -q ${PATH_TO_GENCTL_CI}/tools/ci_python_tools
python3 ${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/generate_json_data_for_cocoa_command.py

if [ -f "${PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND}" ]; then
    echo "Succesfully generated JSON file with data for cocoa command"
    echo "File is located on ${PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND}"
else
    echo "Something went wrong when trying to generate JSON file with data for cocoa command... Exiting with error!!!"
    exit 1
fi

# If needed; override the inventory org and repo

if [[ -z "${INVENTORY_ORG_TO_USE}" ]]
then
    FINAL_INV_ORG=$(jq -r '.commons.org' "${PATH_TO_INVENTORY_JSON_FILE}")
else
    FINAL_INV_ORG=${INVENTORY_ORG_TO_USE}
fi

if [[ -z "${INVENTORY_REPO_TO_USE}" ]]
then
    FINAL_INV_REPO=$(jq -r '.commons.repo' "${PATH_TO_INVENTORY_JSON_FILE}")
else
    FINAL_INV_REPO=${INVENTORY_REPO_TO_USE}
fi

# If we made it to here we have a JSON file with the data for cocoa inventory add
if [[ $INVENTORY_ADD_DRY_RUN = true ]]; then
    echo "DRY RUN MODE !!!"
    echo "The content of the file is the following:"
    cat ${PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND}
    echo "We would have executed the following commands: "
    echo "cocoa inventory add --from-file ${PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND} --environment ${INVENTORY_BRANCH_TO_USE}  --org ${FINAL_INV_ORG} --repo ${FINAL_INV_REPO}"
else
    cocoa inventory add  --from-file "${PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND}" --environment "${INVENTORY_BRANCH_TO_USE}"  --org ${FINAL_INV_ORG} --repo ${FINAL_INV_REPO}    
fi

# Support for separated debians (kali/nscon)
if [[ -f "${PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND_SPECIAL_DEBIAN}" ]]
then
    echo "Need to do an additional run for debians against different inventory org and repo"
    if [[ $INVENTORY_ADD_DRY_RUN = true ]]; then
        echo "DRY RUN MODE !!!"
        echo "The content of the file is the following:"
        cat ${PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND_SPECIAL_DEBIAN}
        echo "We would have executed the following commands: "
        echo "cocoa inventory add  --from-file ${PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND_SPECIAL_DEBIAN} --environment ${INVENTORY_BRANCH_TO_USE} --org ${INVENTORY_ORG_SPECIFIC_FOR_DEBIAN} --repo ${INVENTORY_REPO_SPECIFIC_FOR_DEBIAN}"
    else
        cocoa inventory add  --from-file "${PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND_SPECIAL_DEBIAN}" --environment ${INVENTORY_BRANCH_TO_USE} --org ${INVENTORY_ORG_SPECIFIC_FOR_DEBIAN} --repo ${INVENTORY_REPO_SPECIFIC_FOR_DEBIAN}
    fi
fi