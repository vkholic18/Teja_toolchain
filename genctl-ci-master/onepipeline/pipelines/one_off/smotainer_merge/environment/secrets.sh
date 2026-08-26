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

    "CC_ARTIF_ACCESS_TOKEN:wcp-genctl-docker-local-artifactory-token"

    "GIT_PRIVATE_KEY:ghe-private-key"
    "VAULT_GIT_CONFIG_USER_EMAIL:vault-git-config-user-email"
    "VAULT_GIT_CONFIG_USERNAME:vault-git-config-username"

    "GHE_RO_TOKEN:clconc-ghe-ro-token"
    "GHE_USERNAME:clconc-ghe-usernam"
    "ARTIFACTORY_USER:wcp-genctl-docker-local-artifactory-username"
    "SECRET_MANAGER_KEY_CSI:secret-manager-api-key-csi"

  
)

env_props_text=(

)

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"
