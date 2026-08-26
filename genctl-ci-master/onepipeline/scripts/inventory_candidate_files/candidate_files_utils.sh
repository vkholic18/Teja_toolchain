#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# These are functions useful for dealing with one pipeline inventory 

function create_deployment_metadata_file(){
    # This function creates a JSON file that holds the deployment metadata
    # The parameters come from load_artifact

    # This function is intend to be used in the merge to dev-integration pipeline

    # Expected parameters:
    DEPLOYMENT_ARTIFACT=$1
    DEPLOYMENT_ARTIFACT_DIGEST=$2
    DEPLOYMENT_META_NAME=$3
    FILENAME=$4
    ARTIFACT_NAME_FOR_APP_ARTIFACTS_SECTION=$5 # The value of the artifact name in the app artifacts section (Or empty if nothing used)

    jq -n \
    --arg d_a "${DEPLOYMENT_ARTIFACT}" \
    --arg d_a_d "${DEPLOYMENT_ARTIFACT_DIGEST}" \
    --arg name "${DEPLOYMENT_META_NAME}" \
    --arg art_name_app_art_section "${ARTIFACT_NAME_FOR_APP_ARTIFACTS_SECTION}" \
    '{"deployment_metadata": {
        artifact: $name   ,
        type: "deployment" ,
        sha256: $d_a_d,
        provenance: $d_a    ,
        signature: $d_a_d    ,
        app_artifacts: {"artifact_name": $art_name_app_art_section },
        name: $name
    }}' > ${FILENAME}
}
function create_artifacts_file(){
    # This function creates a JSON file that holds the artifacts data
    # The parameters come from load_artifact

    # Prerequisites: Before calling this function, we should have performed the relevant save_artifact commands

    # This function is intend to be used in the merge to dev-integration pipeline

    # Note: We add the app_artifacts section to the JSON
    # however it might or might be not used later when we run the actual cocoa inventory add commands
    # in the merge to master pipeline

    # Expected parameters:
    FILENAME=$1 # The name of the file to be created
    ARTIFACT_NAME_FOR_APP_ARTIFACTS_SECTION=$2 # The value of the artifact name in the app artifacts section (Or empty if nothing used)
    fail_flag=$(mktemp)

    while read -r artifact
    do
        ARTIFACT_NAME_FOR_APP_ARTIFACTS_SECTION=$2
        ARTIFACT_OBJECT_SAVED_NAME=${artifact}        
        ARTIFACT="$(load_artifact "${artifact}" name)"        
        ARTIFACT_DIGEST="$(load_artifact "${artifact}" digest)"
        ARTIFACT_AND_ARTIFACT_DIGEST="${ARTIFACT}@${ARTIFACT_DIGEST}"
        
        # Get the type
        ARTIFACT_TYPE="$(load_artifact "${artifact}" type)"

         # Different logic for images and packages
        if [[ "${ARTIFACT_TYPE}" == "image" ]]
        then
            SIGNATURE="$(load_artifact "${artifact}" signature)"
            FINAL_NAME="${ARTIFACT_OBJECT_SAVED_NAME}_image"
            FINAL_VALUE_FOR_ARTIFACT_FIELD="${ARTIFACT_AND_ARTIFACT_DIGEST}"
            if [[ -z "${SIGNATURE:-}" && "${ARTIFACT_OBJECT_SAVED_NAME}" != *"${SUFFIX_FOR_ICR_SAVE_ARTIFACTS}" ]]; then
                >&2 echo "ERROR: Missing image signature detected."
                >&2 echo "       Image: ${FINAL_NAME}"
                >&2 echo "       Cause: Signature value is null or empty."
                >&2 echo "       Action: Verify the image signing step completed successfully and review the signing logs."
                echo "fail" > "${fail_flag}"
                break
            fi
        else
            SIGNATURE=""
            FINAL_NAME="${ARTIFACT_OBJECT_SAVED_NAME}_package"
            FINAL_VALUE_FOR_ARTIFACT_FIELD="${FINAL_NAME}"
        fi

        # Fetch the inventory artifact_name overrides 
        artifact_name_override_data=$(yq -r '.inventory_artifact_name_overrides[] | .image_name |= sub("/"; "_") | .image_name + ":" + .artifact_name' "${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml" 2>/dev/null)

        if [ ! -z "$artifact_name_override_data" ]; then
            # Iterate over extracted image_name and artifact_name pairs
            while IFS=":" read -r key value; do
                if [[ "$ARTIFACT_OBJECT_SAVED_NAME" == *"$key"* ]]; then                    
                    ARTIFACT_NAME_FOR_APP_ARTIFACTS_SECTION="${value}"
                    break
                fi
            done < <(echo "$artifact_name_override_data")
        fi

        jq -n \
        --arg fvfaf "${FINAL_VALUE_FOR_ARTIFACT_FIELD}" \
        --arg a_and_ad "${ARTIFACT_AND_ARTIFACT_DIGEST}" \
        --arg name "${FINAL_NAME}" \
        --arg sign "${SIGNATURE}" \
        --arg prov "${ARTIFACT_AND_ARTIFACT_DIGEST}" \
        --arg sha256 "${ARTIFACT_DIGEST}" \
        --arg art_name_app_art_section "${ARTIFACT_NAME_FOR_APP_ARTIFACTS_SECTION}" \
        --arg art_type "${ARTIFACT_TYPE}" \
        '{
            artifact: $fvfaf   ,
            name: $name ,
            app_artifacts: {"artifact_name": $art_name_app_art_section },
            signature: $sign    ,
            provenance: $prov   ,
            sha256: $sha256 ,
            type: $art_type
        }'
    done < <(list_artifacts) | jq -n '.artifacts |= [inputs]' > ${FILENAME}

    if [[ -s "${fail_flag}" ]]; then #Verify the file exists and the file size is greater than 0 bytes (i.e., not empty)
        rm -f "${fail_flag}"
        exit 1
    fi    
    rm -f "${fail_flag}"
}
function create_artifacts_and_commons_file(){
    # This function creates a new JSON file based on an existing file that has the artifacts information
    # It adds common parameters that are used both in inventory add for image and deployment
    # It gets the SHA, the path to the file that has the artifacts information and the name of the new file to generate
    # All the rest of the data comes from OnePipeline environment properties

    # This function is intend to be used in the merge to dev-integration pipeline

    # Expected parameters:
    SHA=$1 # A SHA
    BASE_FILE=$2 # The file used as base
    PIP_BUILD_NUM=$3 # The build number
    PIP_ID=$4 # The pipeline ID
    PIP_RUN_ID=$5 # The pipeline run ID
    FILENAME=$6 # The name of the file (Full path)

    # First some processing to OnePipeline environment properties
    
    # Repo
    APP_REPO="$(load_repo app-repo url)"

    # Inventory
    INVENTORY="$(get_env inventory-repo)"
    INVENTORY_ORG=${INVENTORY%/*}
    INVENTORY_ORG=${INVENTORY_ORG##*/}
    INVENTORY_REPO=${INVENTORY##*/}
    INVENTORY_REPO=${INVENTORY_REPO%.git}

    jq \
    --arg repo_url "${APP_REPO}" \
    --arg sha "${SHA}" \
    --arg build_number "${PIP_BUILD_NUM}" \
    --arg pi "${PIP_ID}" \
    --arg pri "${PIP_RUN_ID}" \
    --arg gtp "${GIT_TOKEN_PATH}" \
    --arg inv_org "${INVENTORY_ORG}" \
    --arg inv_repo "${INVENTORY_REPO}" \
    '.commons=
    {
        repository_url: $repo_url   ,
        commit_sha: $sha    ,
        build_number: $build_number ,
        pipeline_id: $pi        ,
        pipeline_run_id: $pri   ,
        git_token_path: $gtp    ,
        org: $inv_org ,
        repo: $inv_repo
    }' ${BASE_FILE} > ${FILENAME}
}
function check_inventory_json_file() {
    # This function verifies that we have the right keys in an inventory candidate file
    # If everything is OK it just exit 0; if there is an issue exits 1

    # Expected parameters:
    PTP=$1 # The pipeline template type
    PATH_TO_INV_FILE=$2 # The path to the file to check

    echo "Will check we have the right keys in ${PATH_TO_INV_FILE}..."

    # Define the minimum expected keys
    expected_keys_to_appear="artifacts commons"

    # If is razee we should also have information of the deployment metadata
    if [[ "${PTP}" == "razee" ]]
    then
        expected_keys_to_appear="${expected_keys_to_appear} deployment_metadata"
    fi

    # Iterate and check each key appears in JSON file
    for ek in $expected_keys_to_appear
    do
        grep -q -E "\"$ek\":" ${PATH_TO_INV_FILE}
        if [[ $? -ne 0 ]]; then
            echo "Key $ek does not appear in ${PATH_TO_INV_FILE}"
            exit 1
        fi

        # Extra check: 
        # Ensure that we have artifacts or if we don't have; then check that we have deployment_metadata
        if [[ $ek == "artifacts" ]]
        then
            artifacts_content=$(yq -r '.artifacts[]' "${PATH_TO_INV_FILE}")

            # If artifacts is empty we need to check that we have deployment_metadata
            if [[ -z "${artifacts_content}" ]]
            then
                echo "artifacts is empty; will verify if we have deployment_metadata key and it has values..."

                grep -q -E "\"deployment_metadata\":" ${PATH_TO_INV_FILE}
                if [[ $? -ne 0 ]]; then
                    echo "deployment_metadata does not appear in ${PATH_TO_INV_FILE}"
                    exit 1
                fi

                deployment_metadata_content=$(yq -r '.deployment_metadata' "${PATH_TO_INV_FILE}")

                if [[ -z "${deployment_metadata_content}" ]]
                then
                    echo "artifacts is empty and deployment_metadata is also empty; this is not allowed..."
                    echo "Will exit with error..."
                    exit 1
                fi
            fi
        fi
    done

    # OK
    echo "${PATH_TO_INV_FILE} has proper candidate inventory file format..."
}
function check_before_upload() {
    # This function verifies that we have the right number and type of candidate files
    # If everything is OK it just prints a message; if there is an issue exits 1

    # Pre-requisites: We should be in the directory where the candidate files are located
    
    PTP=$1 # The pipeline template type

    if [[ "${PTP}" == "razee" ]] || [[ "${PTP}" == "globals" ]] || [[ "${PTP}" == "hotfix-razee" ]]
    then
        expected_number_of_files=2
    elif [[ "${PTP}" == "uuc-ci" ]]
    then
        # uuc-ci can have 1 or 2 files
        expected_number_of_files="1 or 2"
    else
        expected_number_of_files=1
    fi

    # First, check that we have either one or two files in the directory
    number_of_files=$(ls | wc -l)
    
    # Validate number of files based on pipeline type
    valid_file_count=false
    if [[ "${PTP}" == "uuc-ci" ]] && [[ ${number_of_files} -ge 1 ]] && [[ ${number_of_files} -le 2 ]]
    then
        valid_file_count=true
        echo "Found ${number_of_files} file(s) for uuc-ci (valid: 1 or 2 files allowed)"
    elif [[ "${expected_number_of_files}" != "1 or 2" ]] && [[ ${number_of_files} -eq ${expected_number_of_files} ]]
    then
        valid_file_count=true
    fi
    
    if [[ "${valid_file_count}" == "true" ]]
    then

        # First check the JSON
        number_of_json_files=$(ls | grep .json | wc -l)

        # Check we have one JSON file
        if [[ ${number_of_json_files} -eq 1 ]]; then

            echo "Found one JSON file..."

            # At this point we can assume that the only JSON file is the inventory one
            inv_json_file=$(ls *.json | head -n1)
            
            # Check the format of the JSON file
            check_inventory_json_file "${PTP}" "${PWD}/${inv_json_file}"
        else
            echo "We expected to have 1 JSON file, but we found ${number_of_json_files}..."
            exit 1
        fi

        # If we have two files then there must be a ZIP file
        if [[ ${number_of_files} -eq 2 ]]
        then
            # Get number of zip files
            number_of_zip_files=$(ls | grep .zip | wc -l)
            
            # Check we have one
            if [[ ${number_of_zip_files} -eq 1 ]]; then
                echo "Found one ZIP file..."
            else
                echo "We expected to have 1 ZIP file, but we found ${number_of_zip_files}..."
                exit 1
            fi
        fi
    else
        echo "We expected to have ${expected_number_of_files} files; but we found ${number_of_files}..."
        exit 1
    fi
}

function check_deployment_file_before_upload() {
    # This function verifies that we have a single ZIP file for razee pipelines before upload
    # If everything is OK it just prints a message; if there is an issue exits 1
    
    # Pre-requisites: We should be in the directory where the candidate files are located
    
    PTP=$1 # The pipeline template type
    
    # Only check for ZIP file for razee pipelines
    if [[ "${PTP}" == "razee" ]]
    then
        # Get number of zip files
        number_of_zip_files=$(ls | grep .zip | wc -l)
        
        # Check we have one
        if [[ ${number_of_zip_files} -eq 1 ]]; then
            echo "Found one ZIP file..."
        else
            echo "We expected to have 1 ZIP file, but we found ${number_of_zip_files}..."
            exit 1
        fi
    fi
}

function create_artifacts_file_razee(){
    # This function creates a JSON file that holds the artifacts data
    # The parameters come from load_artifact

    # Prerequisites: Before calling this function, we should have performed the relevant save_artifact commands

    # This function is intend to be used in the merge to dev-integration pipeline

    # Note: We add the app_artifacts section to the JSON
    # however it might or might be not used later when we run the actual cocoa inventory add commands
    # in the merge to master pipeline

    # Expected parameters:
    FILENAME=$1 # The name of the file to be created
    ARTIFACT_NAME_FOR_APP_ARTIFACTS_SECTION=$2 # The value of the artifact name in the app artifacts section (Or empty if nothing used)    

    while read -r artifact
    do
        ARTIFACT_NAME_FOR_APP_ARTIFACTS_SECTION=$2
        ARTIFACT_OBJECT_SAVED_NAME=${artifact}        
        ARTIFACT="$(load_artifact "${artifact}" name)"        
        ARTIFACT_DIGEST="$(load_artifact "${artifact}" digest)"
        ARTIFACT_AND_ARTIFACT_DIGEST="${ARTIFACT}@${ARTIFACT_DIGEST}"

        # Get the type
        ARTIFACT_TYPE="$(load_artifact "${artifact}" type)"
        SIGNATURE=""
         # Different logic for images and packages
        if [[ "${ARTIFACT_TYPE}" == "image" ]]
        then
            FINAL_NAME="${ARTIFACT_OBJECT_SAVED_NAME}_image"
            FINAL_VALUE_FOR_ARTIFACT_FIELD="${ARTIFACT_AND_ARTIFACT_DIGEST}"            
        else            
            FINAL_NAME="${ARTIFACT_OBJECT_SAVED_NAME}_package"
            FINAL_VALUE_FOR_ARTIFACT_FIELD="${FINAL_NAME}"
        fi

        # Fetch the inventory artifact_name overrides 
        artifact_name_override_data=$(yq -r '.inventory_artifact_name_overrides[] | .image_name |= sub("/"; "_") | .image_name + ":" + .artifact_name' "${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml" 2>/dev/null)

        if [ ! -z "$artifact_name_override_data" ]; then
            # Iterate over extracted image_name and artifact_name pairs
            while IFS=":" read -r key value; do
                if [[ "$ARTIFACT_OBJECT_SAVED_NAME" == *"$key"* ]]; then                    
                    ARTIFACT_NAME_FOR_APP_ARTIFACTS_SECTION="${value}"
                    break
                fi
            done < <(echo "$artifact_name_override_data")
        fi

        jq -n \
        --arg fvfaf "${FINAL_VALUE_FOR_ARTIFACT_FIELD}" \
        --arg a_and_ad "${ARTIFACT_AND_ARTIFACT_DIGEST}" \
        --arg name "${FINAL_NAME}" \
        --arg sign "${SIGNATURE}" \
        --arg prov "${ARTIFACT_AND_ARTIFACT_DIGEST}" \
        --arg sha256 "${ARTIFACT_DIGEST}" \
        --arg art_name_app_art_section "${ARTIFACT_NAME_FOR_APP_ARTIFACTS_SECTION}" \
        --arg art_type "${ARTIFACT_TYPE}" \
        '{
            artifact: $fvfaf   ,
            name: $name ,
            app_artifacts: {"artifact_name": $art_name_app_art_section },
            signature: $sign    ,
            provenance: $prov   ,
            sha256: $sha256 ,
            type: $art_type
        }'
    done < <(list_artifacts) | jq -n '.artifacts |= [inputs]' > ${FILENAME}    
}
