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

    "PAT_GHE_1:PAT_GHE_1"
    "PAT_GHE_2:PAT_GHE_2"
    "PAT_GHE_3:PAT_GHE_3"
    "approver_pat_ghe:clconc_pat_ghe"
    "IBM_CLOUD_API_TOKEN:ibmcloud-api-key"

   

    "GIT_PRIVATE_KEY:ghe-private-key"
    "VAULT_GIT_CONFIG_USER_EMAIL:vault-git-config-user-email"
    "VAULT_GIT_CONFIG_USERNAME:vault-git-config-username"

  
)

env_props_text=(

)

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"