#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Usage:
#   source ./iam_utils.sh
#
# Prerequisites:
#   - The function get_env "ibmcloud-api-key" must return your API key.


get_iam_token() {
  API_KEY=$(get_secret "ibmcloud-api-key")

  if [[ -z "$API_KEY" ]]; then
    echo "Error: IBM Cloud API key not found. Make sure get_env 'ibmcloud-api-key' works."
    return 1
  fi

  RESPONSE=$(curl -s -X POST "https://iam.cloud.ibm.com/identity/token" \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --data "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=${API_KEY}")

  export IAM_ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')

  if [[ "$IAM_ACCESS_TOKEN" == "null" || -z "$IAM_ACCESS_TOKEN" ]]; then
    echo "Error: Failed to fetch access token."
    return 1
  fi

  echo "IAM_ACCESS_TOKEN exported successfully."
}

# Call it automatically when sourcing
get_iam_token
