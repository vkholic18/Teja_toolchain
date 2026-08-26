#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023, 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Secrets are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline
env_props_secure=(
    ### Used in scale up, scale down, validate razee cluster and validate feature flags ###
    "IBMCLOUD_KEY:clconc-Balaji-ibmcloud-key"
    "DAL_VAULT_KEY:clconc-vault-dal-qz1-genctl-deploy-key"

    ### Used in the dynamic scan ###
    "VAULT_POK_CERT:vault-pok-cert"
    "VAULT_POK_KEY:vault-pok-key"

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
    "GPG_SIGNING_KEY:gpg-signing-key" 
    "GPG_SIGNING_PW:gpg-signing-pw"

    ### Used in launch darkly ###
    "AUTH_TOKEN:vault-launch-darkly-api-key"

    ### Used in workspace tests ###    
    "SECRET_MANAGER_KEY_CSI:secret-manager-api-key-csi"

    "GITHUB_API_KEY:ghe-access-token"
)

env_props_text=()

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"
