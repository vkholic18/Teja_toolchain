#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Secrets are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline
env_props_secure=(
    ### Used in check secrets, validate client API version, build, unit test, K3 tests ###
    "GIT_PRIVATE_KEY:ghe-private-key"
    "VAULT_GIT_CONFIG_USER_EMAIL:vault-git-config-user-email"
    "VAULT_GIT_CONFIG_USERNAME:vault-git-config-username"

    ### Used in build, unit tests, K3 tests ###
    "GHE_RO_TOKEN:clconc-ghe-ro-token"

    ### Used in build, unit tests ###
    "GHE_USERNAME:clconc-ghe-username"

    ### Used in build ###
    "ARTIFACTORY_USER:wcp-genctl-docker-local-artifactory-username"
    "CC_ARTIFACTORY_READER:clgitchk-artifactory-username"
    "CC_ARTIFACTORY_READER_APIKEY:clgitchk-artifactory-token"
    #ARTIFACTORY_API_KEY:wcp-genctl-docker-local-artifactory-token --> OLD as per  https://github.ibm.com/genctl-cicd/genctl-ci/pull/3350
    
    # --> New as per https://github.ibm.com/genctl-cicd/genctl-ci/pull/3350
    "CC_ARTIF_ACCESS_TOKEN:wcp-genctl-docker-local-artifactory-token"
    "GPG_SIGNING_KEY:gpg-signing-key" 
    "GPG_SIGNING_PW:gpg-signing-pw"
    "ICR_API_KEY:ibmcloud-icr-api-key"

    #### !!! CHECK IF NEEDED ####
    "GITHUB_API_KEY:ghe-access-token"    

    # Used in kali and nscon
    "SDN_READ_SECRETS_API_KEY:sdn-read-secrets-api-key"
)

env_props_text=()

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"
