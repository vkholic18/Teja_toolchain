#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Inherited from CI templates ###

### Used in scale up, scale down, validate razee cluster and validate feature flags ###
export DAL_VAULT_KEY=$(get_secret clconc-vault-dal-qz1-genctl-deploy-key)

### Used in build, workspace tests, check vetted files ###
export CC_ARTIF_ACCESS_TOKEN=$(get_secret wcp-genctl-docker-local-artifactory-token)

### Used in rollback environment, validate feature flags ###
export GIT_TOKEN=$(get_secret ghe-access-token)

### Used in build, promotion tests ###
export ARTIFACTORY_USER=$(get_secret wcp-genctl-docker-local-artifactory-username)
export GIT_PRIVATE_KEY=$(get_secret ghe-private-key)
export VAULT_GIT_CONFIG_USER_EMAIL=$(get_secret vault-git-config-user-email)
export VAULT_GIT_CONFIG_USERNAME=$(get_secret vault-git-config-username)

### Used in build ###
export CC_ARTIFACTORY_READER=$(get_secret clgitchk-artifactory-username)
export CC_ARTIFACTORY_READER_APIKEY=$(get_secret clgitchk-artifactory-token)
export GHE_RO_TOKEN=$(get_secret clconc-ghe-ro-token)
export GHE_USERNAME=$(get_secret clconc-ghe-username)

### Used in launch darkly ###
export AUTH_TOKEN=$(get_secret vault-launch-darkly-api-key)

### Used in promotion tests ###
export SECRET_MANAGER_KEY_CSI=$(get_secret secret-manager-api-key-csi)

### Used in go-notify slack notifications ###
export SLACK_TOKEN=$(get_secret cd-bot-bot-token)

### Used in scale up, scale down, validate razee cluster and validate feature flags ###
### Conditional based on the environment/workspace ###
if [[ "${PIPELINE_REPO_NAME}" == *prod ]]; then
  export IBMCLOUD_KEY=$(get_secret cd-vpc-prod-ibmcloud-apikey)
else
  export IBMCLOUD_KEY=$(get_secret cd-vpc-dev-ibmcloud-apikey)
fi
