#!/usr/bin/env bash

function ibmcloud_login() {
    # Expected parameters:

    # $1 --> The IBM CLOUD KEY
    # $2 --> The region (default is us-south)
    
    # Put some friendly names
    IBM_CLOUD_KEY=$1
    
    # Default region is us-south
    REGION=${2:-"us-south"}
    
    #Get kube config for RIAS cluster
    ibmcloud config --check-version=false
    
    # Save current bash flags and do set +x to ensure no password is leaked
    orig_opts=$-
    set +x
    
    echo "${IBM_CLOUD_KEY}" > con_key_file
    
    # Bring back previous bash flags
    set -${orig_opts}
    
    MAX_RETRIES=5
    RETRY_DELAY=5  # seconds
    COUNT=0

    while true; do
    echo "Attempting IBM Cloud login (try $((COUNT+1))/$MAX_RETRIES)..."
    if ibmcloud login --apikey @con_key_file -r "${REGION}"; then
        echo "IBM Cloud login succeeded."
        break
    else
        COUNT=$((COUNT+1))
        if [ "$COUNT" -ge "$MAX_RETRIES" ]; then
        echo "IBM Cloud login failed after $MAX_RETRIES attempts."
        exit 1
        fi
        echo "Login failed. Retrying in $RETRY_DELAY seconds..."
        sleep "$RETRY_DELAY"
    fi
    done
    
    # ibmcloud login --apikey @con_key_file -r "${REGION}"
    rm -f con_key_file
}
function get_iks_cluster_config() {
    # Expected parameters:

    # $1 --> The cluster to get the config from

    # IMPORTANT: This function assumes we are already logged in IBM Cloud
    
    # Put some friendly names
    CLUSTER_TO_GET_CONFIG=$1
    
    for i in {1..5}
    do   
        echo "Attempt $i to fetch cluster config..."
        set +e
        ibmcloud ks cluster config --cluster ${CLUSTER_TO_GET_CONFIG}
        result_ibm_cloud_command=$?
        set -e
        if [ ${result_ibm_cloud_command} -eq 0 ]
        then
            echo "IBM cloud command OK" 
            break
        else
            echo "Will wait 5 seconds and retry IBM cloud command"
            sleep 5
        fi
    done

    CLUSTER_CONTEXT=$(kubectl config current-context)
    
    if [[ -z "${CLUSTER_CONTEXT}" ]]; then
        echo "Failed to obtain cluster context for $1 Exiting ..."
        exit 1
    fi
}
