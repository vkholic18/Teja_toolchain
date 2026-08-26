#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================



env_props_secure=(

    "CC_GITHUB_TOKEN:CC_GITHUB_TOKEN"
    "CC_PRIVATE_KEY:CC_PRIVATE_KEY"

    
    "TR_ARTIFACTORY_LOGIN:TR_ARTIFACTORY_LOGIN"
    "TR_ARTIFACTORY_ACCESS_TOKEN:TR_ARTIFACTORY_ACCESS_TOKEN"

    "ART_API_KEY:TR_ARTIFACTORY_ACCESS_TOKEN"
    "ICR_API_KEY:ibmcloud-icr-api-key"
)

env_props_text=()

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"