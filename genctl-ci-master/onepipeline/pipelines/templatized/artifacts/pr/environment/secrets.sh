#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Secrets are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

env_props_secure=(
    ### Used in check pr title ###
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
    "PROD_VAULT_ENCRYPTION_KEY:prod-vault-encryption-key"
    "PROD_VAULT_CREDENTIALS_JSON:prod-source-vault-credentails-json"
    "VAULT_SECRETS_IBM_CLOUD_API_KEY:vault-secrets-ibm-cloud-api-key"

    ### Used by telemetry-dlc ###
    "TELEMETRY_DLC_IBMCLOUD_API_KEY:vpc-dev-telemetry-dlc-ibmcloud-api-key"

    ### Used by observability ###
    "GT_TORONTO_NON_PROD_CLOUD_API_KEY:gt-toronto-non-prod-cloud-api-key"
    "GT_TORONTO_PROD_CLOUD_API_KEY:gt-toronto-prod-cloud-api-key"


    ### Used by csi-automation ###
    "CSI_ARTIF_APIKEY:csi_artif_apikey"
    "CSI_GIT_PRIVATE_KEY:csi_git_private_key"
    "CSI_IBMCLOUD_APIKEY:csi_ibmcloud_apikey"

)

env_props_text=()

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"
