#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Inherited from CI templates ###

### Used in scale up, scale down, validate razee cluster and validate feature flags ###
export IBMCLOUD_KEY=$(get_secret clconc-Jason-ibmcloud-apikey)
export IBMCLOUD_ACCOUNT_ID=$(get_secret clconc-Jason-ibmcloud-account-id)
export DAL_VAULT_KEY=$(get_secret clconc-vault-dal-qz1-genctl-deploy-key)

### Used in build, workspace tests, check vetted files ###
export CC_ARTIF_ACCESS_TOKEN=$(get_secret wcp-genctl-docker-local-artifactory-token)

### Used in rollback environment, validate feature flags ###
export GIT_TOKEN=$(get_secret ghe-access-token)
export JIRA_TOKEN=$(get_secret ff_retirement_jira_bearer_token)

### Used in build, promotion tests ###
export ARTIFACTORY_USER=$(get_secret wcp-genctl-docker-local-artifactory-username)
export GIT_PRIVATE_KEY=$(get_secret ghe-private-key)
export VAULT_GIT_CONFIG_USER_EMAIL=$(get_secret vault-git-config-user-email)
export VAULT_GIT_CONFIG_USERNAME=$(get_secret vault-git-config-username)

### Used in build ###
export GHE_USERNAME=$(get_secret clconc-ghe-username)
