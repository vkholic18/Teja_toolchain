#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Secrets are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

export GHE_API_TOKEN=${GH_TOKEN}

env_props_secure=(
    "GIT_PRIVATE_KEY:ghe-private-key"
    "VAULT_GIT_CONFIG_USER_EMAIL:vault-git-config-user-email"
    "VAULT_GIT_CONFIG_USERNAME:vault-git-config-username"
    "GITHUB_TOKEN:git-token"

    "TR_ARTIFACTORY_LOGIN:wcp-genctl-docker-local-artifactory-username"
    "TR_ARTIFACTORY_ACCESS_TOKEN:wcp-genctl-docker-local-artifactory-token"

    "SDN_SANITY_SSH_KEY:sdn-sanity-ssh-key"
    "SDN_READ_SECRETS_API_KEY:sdn-read-secrets-api-key"
)

env_props_text=()

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"