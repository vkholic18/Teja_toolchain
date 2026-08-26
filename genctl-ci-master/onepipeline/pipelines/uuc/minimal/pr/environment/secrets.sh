#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Secrets are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

env_props=(    
    ### Used in build ###
    "GIT_PRIVATE_KEY:ghe-private-key"
    ### used in all UUC
    "ONEPL_IBMCLOUD_API_KEY:ibmcloud-api-key"    
    "SERVICE_FID_GHE_PAT:service-functional-id-ghe-pat"
    "SERVICE_FID_CLOUD_APIKEY:service-functional-id-cloud-apikey"    
    "DATA_COS_API_KEY:data-cos-api-key"    
    "CRYPTO_KEY:sm-crypto-key"    
)

env_props_text=(
    "SECRET_GROUP:secret-group"
    "RESOURCE_GROUP:resource-group"
    "COS_BUCKET_NAME:cos-bucket-name"
    "NETBOX_URL:netbox-url"
    "SM_ENDPOINT_URL:secrets-manager-endpoint-url"
    "SCOPED_ENV:scoped-environment"
    "SERVICE_FID_EMAIL:service-functional-id-email"
    "DATA_COS_ENDPOINT:data-cos-endpoint"
    "DATA_COS_BUCKET_NAME:data-cos-bucket-name"
)

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"
