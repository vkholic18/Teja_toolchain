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

    "SLACK_WEBHOOK_URL:slack-webhook-url"
    "BOBSHELL_API_KEY:bob-api-key"
  
)

env_props_text=(

)

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"

# Resolve secure properties reliably when pipelines provide secret refs.
resolve_secret_value() {
    local key="$1"
    local value=""
    value="$(get_secret "$key" 2>/dev/null || true)"
    if [[ -z "$value" ]]; then
        value="$(get_env "$key" "" 2>/dev/null || true)"
    fi
    printf '%s' "$value"
}

resolve_text_value() {
    local key="$1"
    local default_value="${2:-}"
    get_env "$key" "$default_value" 2>/dev/null || echo "$default_value"
}

# Keep backwards compatibility with older variable names while supporting the
# newer test1 module variable contract.
export TF_VAR_ibmcloud_api_key_value="$(resolve_secret_value "ibmcloud-api-key")"
export TF_VAR_account_id="$(resolve_secret_value "account-id")"
if [[ -z "${TF_VAR_account_id}" ]]; then
    export TF_VAR_account_id="$(resolve_secret_value "ibmcloud-account-id")"
fi
export TF_VAR_cos_api_key="$(resolve_secret_value "cos-api-key")"
export TF_VAR_artifactory_token="$(resolve_secret_value "ARTIFACTORY_TOKEN")"
if [[ -z "${TF_VAR_artifactory_token}" ]]; then
    export TF_VAR_artifactory_token="$(resolve_secret_value "artifactory_token")"
fi
export TF_VAR_pipeline_dockerconfigjson="$(resolve_secret_value "pipeline-dockerconfigjson")"
export TF_VAR_pnp_ibmcloud_api_key="$(resolve_secret_value "pnp-ibmcloud-api-key")"
export TF_VAR_git_token="$(resolve_secret_value "git-token")"

export TF_VAR_tc_name="$(resolve_text_value "tc-name" "afi-ci-toolchain-tf-automation")"
export TF_VAR_sm_name="$(resolve_text_value "sm-name" "")"
export TF_VAR_sm_resource_group="$(resolve_text_value "sm-resource-grp" "")"
export TF_VAR_sm_secret_ref="$(resolve_text_value "sm-secret-ref" "")"
export TF_VAR_cos_instance_crn="$(resolve_text_value "cos-instance-crn" "")"
export TF_VAR_cos_integration_endpoint="$(resolve_text_value "cos-integration-endpoint" "")"
export TF_VAR_tc_build_repo_url="$(resolve_text_value "repo_url" "")"
if [[ -z "${TF_VAR_tc_build_repo_url}" ]]; then
    export TF_VAR_tc_build_repo_url="$(resolve_text_value "repository" "")"
fi
export TF_VAR_tc_afi_config_repo_url="$(resolve_text_value "repository" "")"
export TF_VAR_tc_git_token_secret_ref="$(resolve_text_value "git-token-secret-ref" "")"
