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
    ### Used in Used in create a release bundle ###
    "ARTIFACTORY_USER:wcp-genctl-docker-local-artifactory-username"
    "CC_ARTIF_ACCESS_TOKEN:wcp-genctl-docker-local-artifactory-token"

    ### Used in auto-semver, build ###
    "GIT_PRIVATE_KEY:ghe-private-key"
    "GITHUB_API_KEY:ghe-access-token"
    "VAULT_GIT_CONFIG_USER_EMAIL:vault-git-config-user-email"
    "VAULT_GIT_CONFIG_USERNAME:vault-git-config-username"

    "ICR_API_KEY:ibmcloud-icr-api-key"
)

env_props_text=()

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"

