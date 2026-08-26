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

    "SDN_READ_SECRETS_API_KEY:sdn-read-secrets-api-key"
    "SDN_DEVELOPER_READ_SECRETS_API_KEY:sdn-developer-read-secrets-api-key"
    "E2E_SECRETS_READER:e2e-secrets-reader"

    "ICR_API_KEY:ibmcloud-icr-api-key"
)

env_props_text=()

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"
