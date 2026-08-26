#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

function generic_skip() {
    # Generic function to skip - exiting 0 - according to a flag

    # Expected parameters:

    # $1 --> "true" if we want to skip, anything else otherwise

    if [[ $1 = true ]]; then
        echo "Just exiting ..."
        exit 0
    fi
}

function generic_python_execution() {
    # Generic function to install requirements (If they exist) and execute a python script

    # The function receives a path and assumes:
    # 1. That the requirements.txt is on that path
    # 2. That the script name is the same as the name of the directory

    # In addition we use retry logic so we need to get the path to the retry script

    # Expected parameters:

    # $1 --> Path to the directory where the script and the requirements are
    # $2 --> Path to retry script

    # Optional parameter

    # $3, $4, $N --> Each one of this will be passed as argument to the python script execution

    # Put some friendly names
    BASE_PATH=$1
    RETRY_SCRIPT_PATH=$2
    REQUIREMENTS_FILE_PATH=${BASE_PATH}/requirements.txt

    # Extract the directory name from the whole path, which we assume as the name of the script
    SCRIPT_NAME=$(basename ${BASE_PATH})

    # Source retry logic
    source ${RETRY_SCRIPT_PATH}

    # Check if there are requirements to install, and do it if so
    if [[ -f "${REQUIREMENTS_FILE_PATH}" ]]
    then
        retry python3 -m pip install -r "${REQUIREMENTS_FILE_PATH}"
    else
        echo "No requirements file found"
    fi

    # Execute
    python3 ${BASE_PATH}/${SCRIPT_NAME}.py "${@:3}"
}

function convert_yaml_to_bash_exports(){
    # Generic function that receives a path to a YAML file and outputs a .sh file that contains export commands
    # This supports only simple YAML files that have only top level key values

    # Expected parameters:

    # $1 --> Path to the yaml file

    # Put some friendly names
    PATH_TO_YAML=$1

    # First generate a temporary file discarding lines that start with #,= or - as well as empty lines
    sed -e '/^[#=-]/d ; /^$/d' ${PATH_TO_YAML} > temp_yaml.yaml

    # Iterate over the file
    while read line; do
        # First extract the key and value as they are
        value=${line#*:}
        key=${line%"$value"}

        # Format them (AKA for the key: Replace - with _ and lowercase with uppercase and for the value trim spaces)
        formatted_value=$(echo ${value} | sed 's/^[[:space:]]*//')

        # This is to handle some edge cases that were found in the pipeline-params.yaml we use in Concourse
        if [[ ${formatted_value:0:2} == "((" ]]
        then
            formatted_value="\"${formatted_value}\""
        fi

        formatted_key=$(echo ${key} | cut -d : -f 1 | tr - _ | tr [:lower:] [:upper:] )

        # Concatenate to a file
        echo "export ${formatted_key}=${formatted_value}" >> bash_exports.sh
    done < temp_yaml.yaml

    # Delete temp file
    rm -rf temp_yaml.yaml
}
function convert_overrides_yaml_to_bash_exports(){

    # Expected parameters:

    # $1 --> Path to the overrides file
    # $2 --> Name of the workspace
    # $3 --> Type of the pipeline

    # Put some friendly names
    PATH_TO_OVERRIDES=$1
    WORKSPACE_NAME=$2
    PIPELINE_TYPE=$3

    # First parsing using yq, this generates a file with the key and values of the override for that workspace and type of pipeline, the format is like the following

    #"snow-cli-flags": "--test",
    #"snowgo-flags": "-sa",

    yq -r ".pipelines[] | select(.name == \"${WORKSPACE_NAME}-${PIPELINE_TYPE}\") | .overrides" ${PATH_TO_OVERRIDES} | sed -e '/^[{}]/d ; /^$/d ; s/^[[:space:]]*//' > temp_file_after_yq

    if [ -f temp_file_after_yq ]; then
        # Iterate over the file
        while read line; do
            # First extract the key and value as they are
            value=${line#*:}
            key=${line%"$value"}

            # Format them (AKA for the key: Replace - with _ ,lowercase with uppercase and remove quotes; for the value trim spaces)
            formatted_value=$(echo ${value} | sed 's/^[[:space:]]*//')

            if [[ ${formatted_value: -1} == "," ]];then
                formatted_value=${formatted_value%?}
            fi

            formatted_key=$(echo ${key} | cut -d : -f 1 | tr - _ | tr [:lower:] [:upper:] | tr -d '"')

            # Concatenate to a file
            echo "export ${formatted_key}=${formatted_value}" >> bash_exports_override.sh
        done < temp_file_after_yq

        # Remove temporary file
        rm -rf temp_file_after_yq.yaml
    fi
}

function convert_and_source_pipeline_params_and_overrides(){
    # This function is kind of a "wrapper" for a common functionality
    # It converts from YAML format to bash exports the params of the pipeline-params and the override values for a specific workspace and type of pipeline
    # In addition it sources this converted files, making all the values available

    # IMPORTANT: Before doing any logic it checks if the file already exists (in the current location)
    # If the file exists, it just sources without doing any processing

    # Expected parameters:

    # $1 --> Path to the root of the repo containing pipeline params and override files
    # $2 --> Name of the workspace
    # $3 --> Type of the pipeline

    # Put some friendly names
    PATH_TO_GENCTL_CI=$1
    WORKSPACE_NAME=$2
    PIPELINE_TYPE=$3

    EXPORTS_FILE_NAME="bash_exports.sh"
    OVERRIDE_FILE_NAME="bash_exports_override.sh"

    # Assume some paths
    PATH_TO_PIPELINE_PARAMS=${PATH_TO_GENCTL_CI}/params/pipeline-params.yaml
    PATH_TO_OVERRIDE_FILE=${PATH_TO_GENCTL_CI}/params/pipeline-overrides.yaml

    if [ -f "${EXPORTS_FILE_NAME}" ];
    then
        echo "Exports file exists, sourcing it"
        source "${EXPORTS_FILE_NAME}"
    else
        echo "Exports file does not exist, processing..."
        # Create and source pipeline params
        convert_yaml_to_bash_exports ${PATH_TO_PIPELINE_PARAMS}
        if [ -f "${EXPORTS_FILE_NAME}" ]; then
            chmod +x "${EXPORTS_FILE_NAME}"
            
            # This logic is for optionally showing the content of the .sh file that has the pipeline-params.yaml info
            SHOW_PIPELINE_PARAMS_BASH_FILE_CONTENT=$(get_env show_pipeline_params_bash_file_content "false")
            
            if [[ "${SHOW_PIPELINE_PARAMS_BASH_FILE_CONTENT}" = "true" ]]
            then
                cat "${EXPORTS_FILE_NAME}"
            else
                echo "Won't show the content of the bash file generated from the pipeline-params.yaml"
                echo "If you wish to see the content set show_pipeline_params_bash_file_content = true in the properties of the pipeline"
            fi
            source "${EXPORTS_FILE_NAME}"
        else
            echo "No converted pipeline params file found for sourcing"
        fi
    fi

    if [ -f "${OVERRIDE_FILE_NAME}" ];
    then
        echo "Override file exists, sourcing it"
        echo "The following overrides will be sourced for ${WORKSPACE_NAME} on pipeline ${PIPELINE_TYPE} for run ${BUILD_NUMBER}"
        cat "${OVERRIDE_FILE_NAME}"
        source "${OVERRIDE_FILE_NAME}"
    else
        echo "Override file does not exist, processing..."

        echo "Will proceed to check if in file ${PATH_TO_OVERRIDE_FILE} there is an entry for ${WORKSPACE_NAME}-${PIPELINE_TYPE}"

        # Create and source pipeline params
        convert_overrides_yaml_to_bash_exports ${PATH_TO_OVERRIDE_FILE} ${WORKSPACE_NAME} ${PIPELINE_TYPE}
        if [ -f "${OVERRIDE_FILE_NAME}" ]; then
            chmod +x "${OVERRIDE_FILE_NAME}"
            echo "The following overrides will be sourced: "
            cat "${OVERRIDE_FILE_NAME}"
            source "${OVERRIDE_FILE_NAME}"
        else
            echo "No overrides found for ${WORKSPACE_NAME}-${PIPELINE_TYPE}"
        fi
    fi
}
function check_if_organization_is_prod(){
    # This function gets a string which should be a valid GitHub organization
    # Returns true if this is a "production" organization or false otherwise

    # Expected parameters:

    # $1 --> The organization to check

    ORG_TO_CHECK=$1

    PRODUCTION_ORGS="genctl riaas cloudlab cloudnet genctl-cicd gensec IPOPS-Automation iaas-rhos-platform-india IaaS-LDAP dcms nextgen-ns3 fabric-platform-services FAST"
    [[ "$PRODUCTION_ORGS" =~ (^|[[:space:]])$ORG_TO_CHECK($|[[:space:]]) ]]
}

function repo_is_from_prod_org(){
    # This function gets a string which is the path to a repo (locally)
    # Returns true if this repo is from a "production" organization or false otherwise

    # Expected parameters:

    # $1 --> The path to the repo (locally)

    PATH_TO_REPO=$1

    # First get the remote URL
    TMP_REMOTE_URL=$(cd $PATH_TO_REPO; git config --get remote.origin.url)

    # If starts with https://x-oauth-basic then the logic to extract workspace org is slightly different
    if [[ $TMP_REMOTE_URL == https://x-oauth-basic* ]]
    then
        REPO_ORG=$(echo ${TMP_REMOTE_URL} | cut -d @ -f 2 | cut -d / -f 2)
    else
        REPO_ORG=$(echo ${TMP_REMOTE_URL} | sed -E "s/.*:([^\/]*)\/.*/\\1/")
    fi

    echo "Will check if organization ${REPO_ORG} is a production organization..."

    check_if_organization_is_prod ${REPO_ORG}
}

function upload_file_to_artifactory(){
    # This function uploads a file to artifactory

    # Expected parameters:

    # $1 --> Artifactory token
    # $2 --> The full path to the file in artifactory
    #    Example:
            #https://na.artifactory.swg-devops.com/artifactory/wcp-genctl-sandbox-generic-local/davidf_test_2/mynewfile105.json

    # $3 --> Full path to the local file

    # Optional

    # $4 --> Max retries
    # $5 --> Exit on failure (If not passed, will be true)

    # Put some friendly names
    ART_TOKEN=$1
    ART_FILE_FULL_PATH=$2
    LOCAL_FILE_FULL_PATH=$3

    # By default set max retries on 10
    MAX_RETRIES=${4:-10}

    # By default set exit on failure to true
    EXIT_ON_FAILURE=${5:-true}

    ATTEMPTS_DONE=0

    while [ $ATTEMPTS_DONE -lt ${MAX_RETRIES} ]
    do
        # Upload
        STATUS_CODE=$(curl -s -o /dev/null --retry 5 -X PUT -H "Authorization: Bearer ${ART_TOKEN}" -w "%{http_code}" --upload-file "${LOCAL_FILE_FULL_PATH}" \
        "${ART_FILE_FULL_PATH}")

        # Check if need to exit the loop
        if [[ ${STATUS_CODE} == "201" ]]; then
            break
        else
            echo "Retrying... Attempt ${ATTEMPTS_DONE}"
            ATTEMPTS_DONE=$(( $ATTEMPTS_DONE + 1 ))

            # Wait a little bit
            sleep 2.5
        fi
    done

    if [[ ${STATUS_CODE} == "201" ]]; then
        echo "Succesfully uploaded local file ${LOCAL_FILE_FULL_PATH} to ${ART_FILE_FULL_PATH}"
    else
        echo "Something went wrong, could not upload local file ${LOCAL_FILE_FULL_PATH} to ${ART_FILE_FULL_PATH}"
        # If exit on failure logic, apply
        if [[ $EXIT_ON_FAILURE = true ]]; then
            exit 1
        else
            echo "Exit on failure is not true, so continue execution..."
        fi
    fi
}
function download_file_from_artifactory(){
    # This function downloads a file from artifactory

    # Expected parameters:

    # $1 --> Artifactory token
    # $2 --> The full path to the file in artifactory
    #    Example:
    #       https://na.artifactory.swg-devops.com/artifactory/wcp-genctl-sandbox-generic-local/davidf_test_2/mynewfile105.json

    # $3 --> Full path to the local file

    # Optional

    # $4 --> Max retries
    # $5 --> Exit on failure (If not passed, will be true)

    # Put some friendly names
    ART_TOKEN=$1
    ART_FILE_FULL_PATH=$2
    LOCAL_FILE_FULL_PATH=$3

    # By default set max retries on 10
    if [ -z "${4}" ]
    then
        MAX_RETRIES="10"
    else
        MAX_RETRIES="${4}"
    fi

    # By default set exit on failure to true
    if [ -z "${5}" ]
    then
        EXIT_ON_FAILURE="true"
    else
        EXIT_ON_FAILURE="${5}"
    fi

    ATTEMPTS_DONE=0

    echo "Will try up to ${MAX_RETRIES} times to download file ${ART_FILE_FULL_PATH} to local location ${LOCAL_FILE_FULL_PATH}"

    while [ $ATTEMPTS_DONE -lt ${MAX_RETRIES} ]
    do
         # Download
        STATUS_CODE=$(curl -s --retry 5 -X GET -H "Authorization: Bearer ${ART_TOKEN}" -w "%{http_code}" "${ART_FILE_FULL_PATH}" \
        -o "${LOCAL_FILE_FULL_PATH}")

        # Check if need to exit the loop
        if [[ ${STATUS_CODE} == "200" ]]; then
            break
        else
            echo "Download failed with HTTP status code: ${STATUS_CODE}"
            echo "Retrying... Attempt ${ATTEMPTS_DONE} of ${MAX_RETRIES}"
            ATTEMPTS_DONE=$(( $ATTEMPTS_DONE + 1 ))

            # Wait a little bit
            sleep 2.5
        fi
    done

    if [[ ${STATUS_CODE} == "200" ]]; then
        echo "Successfully downloaded from ${ART_FILE_FULL_PATH} to ${LOCAL_FILE_FULL_PATH}"
    else
        echo "=========================================="
        echo "ERROR: Failed to download file from Artifactory"
        echo "=========================================="
        echo "Final HTTP status code: ${STATUS_CODE}"
        echo "Source URL: ${ART_FILE_FULL_PATH}"
        echo "Destination: ${LOCAL_FILE_FULL_PATH}"
        echo "Attempts made: ${ATTEMPTS_DONE} of ${MAX_RETRIES}"
        echo ""
        echo "Common HTTP status codes:"
        echo "  401 - Unauthorized (check authentication token)"
        echo "  403 - Forbidden (check permissions)"
        echo "  404 - Not Found (file does not exist at this location)"
        echo "  500 - Internal Server Error (Artifactory issue)"
        echo "  503 - Service Unavailable (Artifactory temporarily down)"
        echo "=========================================="
        
        # If exit on failure logic, apply
        if [[ $EXIT_ON_FAILURE = true ]]; then
            exit 1
        else
            echo "Exit on failure is not true, so continue execution..."
        fi
    fi
}
function move_in_artifactory(){
    # This function moves a file/directory from artifactory

    # Expected parameters:

    # $1 --> Artifactory token
    # $2 --> The artifactory base URL (For example: https://na.artifactory.swg-devops.com/artifactory)
    # $3 --> The source (For example: wcp-genctl-sandbox-generic-local/source/myfile.json)
    # $4 --> The destination (For example: wcp-genctl-sandbox-generic-local/destination/myfile.json)

    # Optional

    # $5 --> Max retries
    # $6 --> Exit on failure (If not passed, will be true)

    # Put some friendly names
    ART_TOKEN=$1
    ART_BASE_URL=$2
    SRC=$3
    DST=$4
    
    # Encode
    ENCODED_DST=$(echo $DST | jq --raw-input --raw-output '@uri')

    # By default set max retries on 10
    MAX_RETRIES=${5:-"10"}

    # By default set exit on failure to true
    EXIT_ON_FAILURE=${6:-"true"}

    ATTEMPTS_DONE=0

    echo "Will try up to ${MAX_RETRIES} times to move file from ${SRC} to ${DST}, on ${ART_BASE_URL}"

    while [ $ATTEMPTS_DONE -lt ${MAX_RETRIES} ]
    do
         # Move
        STATUS_CODE=$(curl -s -o /dev/null --retry 5 -X POST -H "Authorization: Bearer ${ART_TOKEN}" -w "%{http_code}" "${ART_BASE_URL}/api/move/${SRC}?to=/${ENCODED_DST}")

        # Check if need to exit the loop
        if [[ ${STATUS_CODE} == "200" ]]; then
            break
        else
            echo "Retrying... Attempt ${ATTEMPTS_DONE}"
            ATTEMPTS_DONE=$(( $ATTEMPTS_DONE + 1 ))

            # Wait a little bit
            sleep 2.5
        fi
    done

    if [[ ${STATUS_CODE} == "200" ]]; then
        echo "Succesfully moved from ${SRC} to ${DST} in ${ART_BASE_URL}"
    else
        echo "Something went wrong, could not move from ${SRC} to ${DST} in ${ART_BASE_URL}"
        # If exit on failure logic, apply
        if [[ $EXIT_ON_FAILURE = true ]]; then
            exit 1
        else
            echo "Exit on failure is not true, so continue execution..."
        fi
    fi
}
function get_file_name_in_artifactory(){
    # This function returns the name of a file in artifactory directory, given a file_name_to_search

    # Expected parameters:

    # $1 --> Artifactory token
    # $2 --> The artifactory base URL (For example: https://na.artifactory.swg-devops.com/artifactory)
    # $3 --> The path in artifactory up to the directory in which search the file
    # $4 --> The filename to search

    # Optional

    # $5 --> Max retries
    # $6 --> Exit on failure (If not passed, will be true)

    # Put some friendly names
    ART_TOKEN=$1
    ART_BASE_URL=$2
    ART_PATH=$3
    FNTS=$4

    # By default set max retries on 10
    MAX_RETRIES=${5:-"10"}

    # By default set exit on failure to true
    EXIT_ON_FAILURE=${6:-"true"}

    # Set an empty var for the result
    FOUND_FILE_NAME_IN_ARTIFACTORY=""

    # Set the initial amount of attempts done
    ATTEMPTS_DONE=0

    echo "Will try up to ${MAX_RETRIES} times to search for only one file that starts with ${FNTS} under ${ART_PATH} on ${ART_BASE_URL}"

    while [ $ATTEMPTS_DONE -lt ${MAX_RETRIES} ]
    do
        echo "Will search for only one file that starts with ${FNTS} under ${ART_PATH} on ${ART_BASE_URL}"

        RESULT_CURL=$(curl -s --retry 5 -H "Authorization: Bearer ${ART_TOKEN}" -X GET -k "${ART_BASE_URL}/api/storage/${ART_PATH}" | jq -r .children[].uri | grep "^/${FNTS}")

        # Check that we got a result
        if [[ ! -z "${RESULT_CURL}" ]]
        then
            # Check that we got exactly one result
            AMOUNT_OF_FILES=$(echo "${RESULT_CURL}" | wc -l)

            # Check if need to exit the loop
            if [[ ${AMOUNT_OF_FILES} -eq 1 ]]; then
                FOUND_FILE_NAME_IN_ARTIFACTORY="${RESULT_CURL:1}"
                break
            else
                echo "Expected to get only one file as result, but got ${AMOUNT_OF_FILES}"
                echo "These are the files we got: "
                echo "${RESULT_CURL}"
                echo "Will exit with error"
                exit 1
            fi
        else
            echo "Retrying... Attempt ${ATTEMPTS_DONE}"
            ATTEMPTS_DONE=$(( $ATTEMPTS_DONE + 1 ))

            # Wait a little bit
            sleep 2.5
        fi
    done

    if [[ -z "${FOUND_FILE_NAME_IN_ARTIFACTORY}" ]]
    then

        echo "Something went wrong, couldn't find one file that starts with ${FNTS} under ${ART_PATH} on ${ART_BASE_URL}"
        # If exit on failure logic, apply
        if [[ $EXIT_ON_FAILURE = true ]]; then
            exit 1
        else
            echo "Exit on failure is not true, so continue execution..."
        fi
    else
        export FOUND_FILE_NAME_IN_ARTIFACTORY
    fi
}

function file_exists_in_artifactory(){
    # This function returns true if the file exists in artifactory, or false otherwise

    # Expected parameters:

    # $1 --> Artifactory token
    # $2 --> The artifactory base URL (For example: https://na.artifactory.swg-devops.com/artifactory)
    # $3 --> The path in artifactory in which we should check if file exists or not

    # Optional

    # $4 --> Max retries

    # Put some friendly names
    ART_TOKEN=$1
    ART_BASE_URL=$2
    ART_PATH=$3

    # By default set max retries on 10
    MAX_RETRIES=${4:-"3"}

    ATTEMPTS_DONE=0

    echo "Will check up to ${MAX_RETRIES} times if file ${ART_PATH} exists in ${ART_BASE_URL}"
    
    while [ $ATTEMPTS_DONE -lt ${MAX_RETRIES} ]
    do
        RESULT_CHECK=$(curl -s -o /dev/null --retry 5 -H "Authorization: Bearer ${ART_TOKEN}" -w "%{http_code}" ${ART_BASE_URL}/${ART_PATH})

        # Check if need to exit the loop
        if [[ ${RESULT_CHECK} -eq 200 ]]; then
            break
        else
            echo "Retrying... Attempt ${ATTEMPTS_DONE}"
            ATTEMPTS_DONE=$(( $ATTEMPTS_DONE + 1 ))

            # Wait a little bit
            sleep 2.5
        fi
    done

    [[ ${RESULT_CHECK} -eq 200 ]]
}

function get_last_commit_associated_pr_number(){
    # This function returns the PR number associated with the last commit, it does it through an environment variable
    # LAST_COMMIT_ASSOCIATED_PR_NUMBER

    # Expected parameters:

    # $1 --> Path to the repo

    PATH_TO_REPO=$1

    # Move to the repo
    pushd "${PATH_TO_REPO}"

    # First do some processing to extract the commit message
    RAW_GIT_LOG_RESULT=$(git log --oneline | head -n 1)
    ONLY_SHA=$(echo ${RAW_GIT_LOG_RESULT} | cut -d ' ' -f 1)
    COMMIT_MESSAGE=${RAW_GIT_LOG_RESULT#"$ONLY_SHA "}

    # Get the number of parents of the last commit
    number_of_parents_of_last_commit=$(git log --pretty=%P -n 1 HEAD| wc -w)

    if [ ${number_of_parents_of_last_commit} -eq 1 ]
    then
        # If the number of parents is 1, we assume is a squash commit with the commit message in the form of
        # SomeText (#PR_NUMBER)
        # For example:
        # fix: CIGC-8502: Fixing workspace input mapping. (#4837)

        # This line does the following
        # 1. The echo with //* removes everything before the last space, following the example, this would give us (#4837)
        # 2. The sed removes the following characters ( # )
        # The final result should be the PR_ID
        result=$(echo ${COMMIT_MESSAGE//* } | sed 's/[(#)]//g')
    elif [ ${number_of_parents_of_last_commit} -eq 2 ]
    then
        # If the number of parents is 2, we assume is a merge commit with the commit message in the form of
        # Merge pull request #PR_NUMBER from XXX
        # Merge pull request #3703 from riaas/dev-integration

        result=$(echo ${COMMIT_MESSAGE#"Merge pull request #"} | cut -d ' ' -f1)
    else
        echo "Something went wrong during the calculation of number of parents of last commit"
        echo "Will exit with error..."
        exit 1
    fi

    # Export result
    export LAST_COMMIT_ASSOCIATED_PR_NUMBER=${result}

    # Come back
    popd
}
function wait_for_file_to_exist(){
    # This function waits until a file exists
    # When the file exists, the function exits
    # If after some time the file does not exists it finishes its execution (Optionally with exit 1)

    # Expected parameters:

    # $1 --> Full path to the file that we wait for it to exists

    # Optional

    # $2 --> Max retries
    # $3 --> Seconds to wait between each retry
    # $4 --> Exit with error on non existing file

    # Put some friendly names
    PATH_TO_FILE_TO_CHECK=$1

    # By default set max retries on 180
    MAX_RETRIES=${2:-"180"}

    # By default set seconds to wait between retries to one minute
    SECONDS_TO_WAIT_BETWEEN_RETRIES=${3:-60}

    # By default set exit with error on non existing file to false
    EXIT_ON_FAILURE=${4:-"false"}

    ATTEMPTS_DONE=0

    echo "Will check up to ${MAX_RETRIES} times if the following file exists: ${PATH_TO_FILE_TO_CHECK}"
    
    while [ $ATTEMPTS_DONE -lt ${MAX_RETRIES} ]
    do
        # Check if need to exit the loop
        if [ -f "${PATH_TO_FILE_TO_CHECK}" ]; then
            echo "Found file ${PATH_TO_FILE_TO_CHECK}"
            break
        else
            echo "Retrying... Attempt ${ATTEMPTS_DONE}"
            ATTEMPTS_DONE=$(( $ATTEMPTS_DONE + 1 ))

            # Wait a little bit
            sleep ${SECONDS_TO_WAIT_BETWEEN_RETRIES}
        fi
    done

    # Check another time and if the file not there yet, exit with error
    if [ ! -f "${PATH_TO_FILE_TO_CHECK}" ]; then
        echo "After ${ATTEMPTS_DONE} attempts, could not find file ${PATH_TO_FILE_TO_CHECK}"
        if [[ $EXIT_ON_FAILURE = true ]]; then
            echo "Will exit with error..."
            exit 1
        fi
    fi
}

function repo_has_images_in_build_meta(){
    # This function returns true if the build-meta.yaml file has at least one image defined or false otherwise
    # The return is done by exporting environment variable RESULT_CHECK_IF_REPO_HAS_IMAGES
    # We assume that the build-meta.yaml file exists

    # Expected parameters:

    # $1 --> Full path to the build-meta.yaml file

    # Put some friendly names
    PATH_TO_BUILD_META_FILE=$1

    # First check we have the images section at all
    images=$(yq -r '.images ' "${PATH_TO_BUILD_META_FILE}")

    if [[ ! ${images} == null ]]
    then
        images_multi_arch=$(yq -r '.images.multi_arch | select(. != null) | if type=="string" then . else .[] end' ${PATH_TO_BUILD_META_FILE})
        images_amd64=$(yq -r '.images.amd64 | select(. != null) | if type=="string" then . else .[] end' ${PATH_TO_BUILD_META_FILE})
        images_no_arch=$(yq -r '.images.no_arch | select(. != null) | if type=="string" then . else .[] end' ${PATH_TO_BUILD_META_FILE})

        if [[ ${images_amd64} != "" ]]
        then
            echo "Found images for amd64"
            export RESULT_CHECK_IF_REPO_HAS_IMAGES="true"
        elif [[ ${images_multi_arch} != "" ]]
        then
            echo "Found images for multi_arch"
            export RESULT_CHECK_IF_REPO_HAS_IMAGES="true"
        elif [[ ${images_no_arch} != "" ]]
        then
            echo "Found images for no_arch"
            export RESULT_CHECK_IF_REPO_HAS_IMAGES="true"
        else
            echo "Could not find images neither for amd64, multi_arch, or no_arch..."
            export RESULT_CHECK_IF_REPO_HAS_IMAGES="false"    
        fi
    else
        echo "Could not find images section in build-meta.yaml so we consider this repo as not having images..."
        export RESULT_CHECK_IF_REPO_HAS_IMAGES="false"
    fi
}

function copy_in_artifactory(){
    # This function copies a file/directory in artifactory
    # Supports optional custom destination filename

    # Expected parameters:

    # $1 --> Artifactory token
    # $2 --> The artifactory base URL (For example: https://na.artifactory.swg-devops.com/artifactory)
    # $3 --> The source (For example: wcp-genctl-sandbox-generic-local/source/myfile.json)
    # $4 --> The destination (For example: wcp-genctl-sandbox-generic-local/destination/myfile.json)

    # Optional

    # $5 --> Max retries
    # $6 --> Exit on failure (If not passed, will be true)
    # $7 --> Custom destination filename (optional - if provided, replaces the filename in DST)

    # Put some friendly names
    ART_TOKEN=$1
    ART_BASE_URL=$2
    SRC=$3
    DST=$4

    # By default set max retries on 10
    MAX_RETRIES=${5:-"10"}

    # By default set exit on failure to true
    EXIT_ON_FAILURE=${6:-"true"}

    # Optional custom destination filename
    CUSTOM_DST_FILENAME=${7:-""}

    # If custom destination filename is provided, replace the filename in DST
    if [[ ! -z "${CUSTOM_DST_FILENAME}" ]]; then
        # Extract the directory path from DST
        DST_DIR=$(dirname "${DST}")
        # Construct new destination with custom filename
        DST="${DST_DIR}/${CUSTOM_DST_FILENAME}"
        echo "Using custom destination filename: ${CUSTOM_DST_FILENAME}"
    fi

    # Encode
    ENCODED_DST=$(echo $DST | jq --raw-input --raw-output '@uri')

    ATTEMPTS_DONE=0

    echo "Will try up to ${MAX_RETRIES} times to copy file from ${SRC} to ${DST}, on ${ART_BASE_URL}"

    while [ $ATTEMPTS_DONE -lt ${MAX_RETRIES} ]
    do
         # Copy
        STATUS_CODE=$(curl -s -o /dev/null --retry 5 -X POST -H "Authorization: Bearer ${ART_TOKEN}" -w "%{http_code}" "${ART_BASE_URL}/api/copy/${SRC}?to=/${ENCODED_DST}&suppressLayouts=1")

        # Check if need to exit the loop
        if [[ ${STATUS_CODE} == "200" ]]; then
            break
        else
            echo "Retrying... Attempt ${ATTEMPTS_DONE}"
            ATTEMPTS_DONE=$(( $ATTEMPTS_DONE + 1 ))

            # Wait a little bit
            sleep 2.5
        fi
    done

    if [[ ${STATUS_CODE} == "200" ]]; then
        echo "Succesfully copied from ${SRC} to ${DST} in ${ART_BASE_URL}"
    else
        echo "Something went wrong, could not copy from ${SRC} to ${DST} in ${ART_BASE_URL}"
        # If exit on failure logic, apply
        if [[ $EXIT_ON_FAILURE = true ]]; then
            exit 1
        else
            echo "Exit on failure is not true, so continue execution..."
        fi
    fi
}

fetch_and_checkout_merge_commit() {
    # ------------------------------------------------------------------------------
    # Purpose:
    #   Ensures the workspace is positioned exactly at the GitHub merge commit
    #   created after a PR is auto-merged (normal merge strategy).
    #
    # Why this is required:
    #   - git fetch only downloads objects but does NOT move HEAD.
    #   - Our workspace is cloned from PR branch.
    #   - Auto semver must run on the merge commit in base branch.
    #
    # What this function does:
    #   1. Push into repo directory
    #   2. Fetch merge commit object explicitly
    #   3. Validate commit exists locally
    #   4. Checkout base branch (create if missing)
    #   5. Reset base branch to merge commit
    #   6. Export MERGE_COMMIT_SHA for downstream steps
    #
    # Required environment variables:
    #   PATH_TO_REPO
    #   PR_MERGE_COMMIT_SHA
    #   PR_BASEBRANCH
    # ------------------------------------------------------------------------------
    local PATH_TO_REPO="$1"
    local PR_MERGE_COMMIT_SHA="$2"

    pushd "$PATH_TO_REPO" > /dev/null || {
        echo "ERROR: Unable to access repo path"
        return 1
    }

    echo "Fetching merge commit: $PR_MERGE_COMMIT_SHA"
    git fetch origin "$PR_MERGE_COMMIT_SHA" || {
        echo "ERROR: Failed to fetch merge commit"
        popd > /dev/null
        return 1
    }

    # Validate commit exists locally
    if ! git cat-file -e "${PR_MERGE_COMMIT_SHA}^{commit}" 2>/dev/null; then
        echo "ERROR: Merge commit not found locally after fetch"
        popd > /dev/null
        return 1
    fi

    echo "Checking out base branch: $PR_BASEBRANCH"

    # Try checkout existing local branch
    git checkout "$PR_BASEBRANCH" 2>/dev/null || \
    git checkout -b "$PR_BASEBRANCH" "origin/$PR_BASEBRANCH" || {
        echo "ERROR: Unable to checkout base branch"
        popd > /dev/null
        return 1
    }

    echo "Resetting base branch to merge commit"
    git reset --hard "$PR_MERGE_COMMIT_SHA" || {
        echo "ERROR: Failed to reset to merge commit"
        popd > /dev/null
        return 1
    }

    # Export for semver step
    export MERGE_COMMIT_SHA="$PR_MERGE_COMMIT_SHA"

    echo "Repository is now at merge commit: $MERGE_COMMIT_SHA"

    popd > /dev/null
}
