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
    ### Used in retag, move ZIP from vetted to final destination, Download JSON and inventory add ###
    "CC_ARTIF_ACCESS_TOKEN:wcp-genctl-docker-local-artifactory-token"

    ### Used in auto-semver, retag ###
    "GIT_PRIVATE_KEY:ghe-private-key"
    "VAULT_GIT_CONFIG_USER_EMAIL:vault-git-config-user-email"
    "VAULT_GIT_CONFIG_USERNAME:vault-git-config-username"

    ### Used in auto-semver ###
    "GITHUB_API_KEY:ghe-access-token"

    ### Used in build ###
    "GPG_SIGNING_KEY:gpg-signing-key" 
    "GPG_SIGNING_PW:gpg-signing-pw"

    ### Used in retag ###
    "ARTIFACTORY_USER:wcp-genctl-docker-local-artifactory-username"

    # DOCKER_TOKEN= ?? - TODO: Add secrets ?
    # DOCKER_USERNAME= ?? - TODO: Add secrets ?

    ### Used in Update release version ###
    "JIRA_USERNAME:jira_username"
    "JIRA_PASSWORD:jira_password"

    ### Used in upload to COS ###
    "COS_SERVICE_CREDENTIALS:vault-ibm-cos-creds"

    ### Used in LaunchDarkly ###
    "AUTH_TOKEN:vault-launch-darkly-api-key"
)

env_props_text=()

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"
