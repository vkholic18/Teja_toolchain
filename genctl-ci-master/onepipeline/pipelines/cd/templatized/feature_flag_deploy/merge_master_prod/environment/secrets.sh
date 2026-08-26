#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Used in build, workspace tests, check vetted files ###
export CC_ARTIF_ACCESS_TOKEN=$(get_secret wcp-genctl-docker-local-artifactory-token)

### Used in rollback environment, validate feature flags ###
export GIT_TOKEN=$(get_secret ghe-access-token)
export GITHUB_TOKEN=$(get_secret ghe-access-token)
# export GITHUB_TOKEN=$(get_secret ghe-test-token)

### Used in build, promotion tests ###
export ARTIFACTORY_USER=$(get_secret wcp-genctl-docker-local-artifactory-username)
export GIT_PRIVATE_KEY=$(get_secret ghe-private-key)
export VAULT_GIT_CONFIG_USER_EMAIL=$(get_secret vault-git-config-user-email)
export VAULT_GIT_CONFIG_USERNAME=$(get_secret vault-git-config-username)
export IBM_CLOUD_API_KEY=$(get_secret ff-ibm-cloud-api-key)

### Used in build ###
export GHE_USERNAME=$(get_secret clconc-ghe-username)

### Used in featureflags upload ###
export COS_SERVICE_CREDENTIALS=$(get_secret vault-ibm-cos-creds)
export GHE_RO_TOKEN=$(get_secret clconc-ghe-ro-token)
export SLACK_TOKEN=$(get_secret cd-bot-bot-token)

export ENV_OVERRIDE=$(get_env env-override)
export NEXTGEN_ENVIRONMENTS_GITHUB_PAT=$(get_secret ghe_pat_vpciamdev_account)
