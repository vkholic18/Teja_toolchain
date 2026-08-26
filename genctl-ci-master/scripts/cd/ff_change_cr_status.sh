#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2024
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

set -eux

ticket_num=$(jq -r '.[0].number' ${TICKET_DIR}/data.json)
if [[ "$STATE" == "close" || "$STATE" == "cancel" ]]; then
  ibmcloud oss cr ${STATE} -n ${ticket_num} --apikey ${IBM_CLOUD_API_KEY} --endpoint ${IBM_CLOUD_ENDPOINT} --notes "${CLOSE_NOTES}"
else
  ibmcloud oss cr ${STATE} -n ${ticket_num} --apikey ${IBM_CLOUD_API_KEY} --endpoint ${IBM_CLOUD_ENDPOINT}
fi
