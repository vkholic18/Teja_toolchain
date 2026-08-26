#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Secrets are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline
env_props_secure=(
    ### Used in scale up, scale down, validate razee cluster and validate feature flags ###
    "IBMCLOUD_KEY:clconc-Balaji-ibmcloud-key"
    "DAL_VAULT_KEY:clconc-vault-dal-qz1-genctl-deploy-key"

    ### Used in build, workspace tests, check vetted files ###
    "CC_ARTIF_ACCESS_TOKEN:wcp-genctl-docker-local-artifactory-token"

    ### Used in rollback environment, validate feature flags ###
    "GIT_TOKEN:ghe-access-token"

    ### Used in build, workspace tests ###
    "ARTIFACTORY_USER:wcp-genctl-docker-local-artifactory-username"
    "GIT_PRIVATE_KEY:ghe-private-key"
    "VAULT_GIT_CONFIG_USER_EMAIL:vault-git-config-user-email"
    "VAULT_GIT_CONFIG_USERNAME:vault-git-config-username"

    ### Used in build ###
    "CC_ARTIFACTORY_READER:clgitchk-artifactory-username"
    "CC_ARTIFACTORY_READER_APIKEY:clgitchk-artifactory-token"
    "GHE_RO_TOKEN:clconc-ghe-ro-token"
    "GHE_USERNAME:clconc-ghe-username"

    "GITHUB_API_KEY:ghe-access-token"
    "GHE_PAT:git-personal-access-token"

    ### Used in upload to COS ###
    "COS_SERVICE_CREDENTIALS:vault-ibm-cos-creds"

    ### used in upload
    "ICR_API_KEY:ibmcloud-icr-api-key"

    ### used in all UUC
    "ONEPL_IBMCLOUD_API_KEY:ibmcloud-api-key"
    
    "SERVICE_FID_GHE_PAT:service-functional-id-ghe-pat"
    "SERVICE_FID_CLOUD_APIKEY:service-functional-id-cloud-apikey"
    "CRYPTO_KEY:sm-crypto-key"
    "DATA_COS_API_KEY:data-cos-api-key"
)

env_props_text=(
    ### used in all UUC
    "SM_ENDPOINT_URL:secrets-manager-endpoint-url"
    "SERVICE_FID_EMAIL:service-functional-id-email"
    "SECRET_GROUP:secret-group"
    "COS_BUCKET_NAME:cos-bucket-name"
    "RESOURCE_GROUP:resource-group"
    "NETBOX_URL:netbox-url"
    "DATA_COS_ENDPOINT:data-cos-endpoint"    
    "DATA_COS_BUCKET_NAME:data-cos-bucket-name"    
    "SCOPED_ENV:scoped-environment"
)

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"
