#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script is run by 1P right before the CRA
# More details in this thread: https://ibmcloudlab.slack.com/archives/CFQHG5PP1/p1726558098860069

docker_login() {
    local registry_url=$1
    local username=$2
    local password=$3

    if [[ -n "$registry_url" && -n "$username" && -n "$password" ]]; then
        echo "logging into the ${registry_url}"
        echo "$password" | docker login "$registry_url" -u "$username" --password-stdin
        if [[ $? -ne 0 ]]; then
            echo "Docker login failed for $registry_url"
            exit 1
        fi
    fi
}

# Login to Artifactory Docker Proxy
docker_login "$ARTIFACTORY_DOCKER_PROXY_URL" "$ARTIFACTORY_USER" "$CC_ARTIF_ACCESS_TOKEN"


ICR_URL="us.icr.io"
ICR_API_KEY=$(get_env ibmcloud-icr-api-key)

# # Login to IBM Cloud ICR
docker_login "$ICR_URL" "iamapikey" "$ICR_API_KEY"
