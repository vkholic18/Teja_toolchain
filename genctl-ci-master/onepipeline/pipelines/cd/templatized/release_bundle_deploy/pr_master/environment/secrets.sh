#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Inherited from CI templates ###

### Used in scale up, scale down, validate razee cluster and validate feature flags ###
export IBMCLOUD_KEY=$(get_env clconc-Jason-ibmcloud-apikey)
export IBMCLOUD_ACCOUNT_ID=$(get_env clconc-Jason-ibmcloud-account-id)
export DAL_VAULT_KEY=$(get_env clconc-vault-dal-qz1-genctl-deploy-key)

### Used in build, workspace tests, check vetted files ###
export CC_ARTIF_ACCESS_TOKEN=$(get_env wcp-genctl-docker-local-artifactory-token)

### Used in rollback environment, validate feature flags ###
export GIT_TOKEN=$(get_env ghe-access-token)

### Used in build, promotion tests ###
export ARTIFACTORY_USER=$(get_env wcp-genctl-docker-local-artifactory-username)
export GIT_PRIVATE_KEY=$(get_env ghe-private-key)
export VAULT_GIT_CONFIG_USER_EMAIL=$(get_env vault-git-config-user-email)
export VAULT_GIT_CONFIG_USERNAME=$(get_env vault-git-config-username)

### Used in build ###
export GHE_USERNAME=$(get_env clconc-ghe-username)

### Used in launch darkly ###
export AUTH_TOKEN=$(get_env vault-launch-darkly-api-key)

### Used in legacy PR deployments for release bundles
export MDS_SERVICENOW_IAM_APIKEY=$(get_env snow-iam-api-key)
export MDS_JIRA_USERNAME=$(get_env jira_username)
export MDS_JIRA_APIKEY=$(get_env jira_password)

### Used in scale up, scale down, validate razee cluster and validate feature flags ###
### Conditional based on the environment/workspace ###
if [[ "${PIPELINE_REPO_NAME}" == *prod ]]; then
  export AUTH_TOKEN=$(get_env vault-launch-darkly-prod-api-key)
elif [[ "${PIPELINE_REPO_NAME}" == *staging ]]; then
  export AUTH_TOKEN=$(get_env vault-launch-darkly-staging-api-key)
elif [[ "${PIPELINE_REPO_NAME}" == *integ ]]; then
  export AUTH_TOKEN=$(get_env vault-launch-darkly-integ-api-key)
fi
