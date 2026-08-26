#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Secrets are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

env_props_secure=(
    ### Used in auto-semver, build ###
    "GIT_PRIVATE_KEY:ghe-private-key"
    "VAULT_GIT_CONFIG_USER_EMAIL:vault-git-config-user-email"
    "VAULT_GIT_CONFIG_USERNAME:vault-git-config-username"

    ### Used in auto-semver ###
    "GITHUB_API_KEY:ghe-access-token"

    ### Used in build ###
    "GIT_PRIVATE_KEY:ghe-private-key"
    "CC_ARTIFACTORY_READER:clgitchk-artifactory-username"
    "CC_ARTIFACTORY_READER_APIKEY:clgitchk-artifactory-token"
    "GHE_RO_TOKEN:clconc-ghe-ro-token"
    "GHE_USERNAME:clconc-ghe-username"
    "ARTIFACTORY_USER:wcp-genctl-docker-local-artifactory-username"
    "CC_ARTIF_ACCESS_TOKEN:wcp-genctl-docker-local-artifactory-token"
    "VAULT_GIT_CONFIG_USER_EMAIL:vault-git-config-user-email"
    "VAULT_GIT_CONFIG_USERNAME:vault-git-config-username"

    ### Used by observability ###
    "GT_TORONTO_NON_PROD_CLOUD_API_KEY:gt-toronto-non-prod-cloud-api-key"
    "GT_TORONTO_PROD_CLOUD_API_KEY:gt-toronto-prod-cloud-api-key"

    ### Used by csi-automation ###
    "CSI_ARTIF_APIKEY:csi_artif_apikey"
    "CSI_GIT_PRIVATE_KEY:csi_git_private_key"
    "CSI_IBMCLOUD_APIKEY:csi_ibmcloud_apikey"

    "ICR_API_KEY:ibmcloud-icr-api-key"    
    "DATA_COS_API_KEY:data-cos-api-key"
    "CRYPTO_KEY:sm-crypto-key"
    "SERVICE_FID_GHE_PAT:service-functional-id-ghe-pat"
    "SERVICE_FID_CLOUD_APIKEY:service-functional-id-cloud-apikey"
)

env_props_text=(
    "SM_ENDPOINT_URL:secrets-manager-endpoint-url"
    "SERVICE_FID_EMAIL:service-functional-id-email"
    "SECRET_GROUP:secret-group"
    "RESOURCE_GROUP:resource-group"
    "COS_BUCKET_NAME:cos-bucket-name"
    "NETBOX_URL:netbox-url"
    "SCOPED_ENV:scoped-environment"
    "DATA_COS_BUCKET_NAME:data-cos-bucket-name"
    "DATA_COS_ENDPOINT:data-cos-endpoint"
)

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"
