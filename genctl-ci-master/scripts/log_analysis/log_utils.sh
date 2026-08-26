#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

function download_pipeline_logs()
{
    export ONE_PIPELINE_CI_IBM_CLOUD_API_KEY=$(get_secret "ibmcloud-api-key")
    #Get IAM Bearer Token using IBM Cloud API Key    
    echo "Getting IAM token..."
    RESPONSE=$(curl -s -X POST \
    "https://iam.cloud.ibm.com/identity/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}")

    # Extract the access token
    BEARER_TOKEN=$(echo $RESPONSE | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

    if [ -z "$BEARER_TOKEN" ]; then
        echo "Error: Failed to get bearer token"
        echo "Response: $RESPONSE" 
    fi

    # Download pipeline logs
    echo "Downloading pipeline logs..."
    curl -L -H "Authorization: Bearer ${BEARER_TOKEN}" "https://cloud.ibm.com/devops/pipelines/tekton/api/v1/${PIPELINE_ID}/runs/${PIPELINE_RUN_ID}/export?env_id=ibm:yp:eu-gb" -o pipeline_logs.zip

    if [ $? -ne 0 ]; then
        echo "Failed to download logs"    
    fi
    if [ -f "pipeline_logs.zip" ]; then
        echo "Found the pipeline_logs.zip and extacting the file"
        mkdir -p pipeline_logs
        unzip -oq "pipeline_logs.zip" -d pipeline_logs
        if [ $? -eq 0 ]; then
            echo "Logs extracted successfully in ${PWD}"
        else
            echo "Unable to extact the logs"
        fi
    else
        echo "File: pipeline_logs.zip does not exist"
    fi

    # Upload logs zip and pipeline-config to COS
    upload_pipeline_logs_to_cos

    # Clean up the zip after upload
    rm -f pipeline_logs.zip
}

function upload_pipeline_logs_to_cos()
{
    local COS_BUCKET="pipeline-log-analyzer"
    local COS_ENDPOINT="https://s3.jp-tok.cloud-object-storage.appdomain.cloud"
    local LOGS_ZIP="pipeline_logs.zip"
    local LOGS_COS_PATH="pipeline_logs/${PIPELINE_ID}/${PIPELINE_RUN_ID}_pipeline_logs.zip"
    export COS_API_KEY=$(get_secret "cos-api-key")
    # Upload the zip to COS
    echo "Uploading pipeline logs zip to COS..."
    COS_BUCKET_NAME="${COS_BUCKET}" COS_ENDPOINT="${COS_ENDPOINT}" bash "${PATH_TO_GENCTL_CI}/scripts/generic_cos_operations/generic_cos_wrapper.sh" \
        upload "${LOGS_ZIP}" "${LOGS_COS_PATH}"

    # Upload the pipeline-config to COS
    local PIPELINE_CONFIG_FILE="${PATH_TO_GENCTL_CI}/$(get_env "pipeline-config")"
    local PIPELINE_CONFIG_FILENAME
    PIPELINE_CONFIG_FILENAME="$(basename "${PIPELINE_CONFIG_FILE}")"
    local CONFIG_COS_PATH="pipeline_logs/${PIPELINE_ID}/${PIPELINE_RUN_ID}_${PIPELINE_CONFIG_FILENAME}"

    echo "Uploading pipeline config to COS..."
    COS_BUCKET_NAME="${COS_BUCKET}" COS_ENDPOINT="${COS_ENDPOINT}" bash "${PATH_TO_GENCTL_CI}/scripts/generic_cos_operations/generic_cos_wrapper.sh" \
        upload "${PIPELINE_CONFIG_FILE}" "${CONFIG_COS_PATH}"
}
