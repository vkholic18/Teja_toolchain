#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================


# secrets used for scripts
export GIT_TOKEN_PATH="${WORKSPACE}/git-token"
export GITHUB_API_KEY=$(cat ${GIT_TOKEN_PATH})

# used for terraform vars(override values without having to use an input)
# https://developer.hashicorp.com/terraform/cli/config/environment-variables#tf_var_name
export TF_VAR_ibmgit_api_key=$GITHUB_API_KEY


env_props_secure=(

    "artifactory_token:ARTIFACTORY_TOKEN"
    "TF_VAR_ibmcloud_api_key:ibmcloud-api-key"

    "GIT_PRIVATE_KEY:ghe-private-key"
    "VAULT_GIT_CONFIG_USER_EMAIL:vault-git-config-user-email"
    "VAULT_GIT_CONFIG_USERNAME:vault-git-config-username"
  
)

env_props_text=(

)

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"