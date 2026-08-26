#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Used in build, workspace tests, check vetted files ###
export CC_ARTIF_ACCESS_TOKEN=$(get_secret wcp-genctl-docker-local-artifactory-token)

### Used in rollback environment, validate feature flags ###
export GIT_TOKEN=$(get_secret git-personal-access-token)
export JIRA_TOKEN=$(get_secret ff_retirement_jira_bearer_token)
export GITHUB_TOKEN=$(get_secret ghe-access-token)
export NEXTGEN_ENVIRONMENTS_GITHUB_PAT=$(get_secret ghe_pat_vpciamdev_account)

### Used in build, promotion tests ###
export ARTIFACTORY_USER=$(get_secret wcp-genctl-docker-local-artifactory-username)
export GIT_PRIVATE_KEY=$(get_secret ghe-private-key)
export VAULT_GIT_CONFIG_USER_EMAIL=$(get_secret vault-git-config-user-email)
export VAULT_GIT_CONFIG_USERNAME=$(get_secret vault-git-config-username)

### Used in build ###
export GHE_USERNAME=$(get_secret clconc-ghe-username)

### Used in featureflags upload ###
export GHE_RO_TOKEN=$(get_secret clconc-ghe-ro-token)

export NEXTGEN_FF_ALERTS_WEBHOOK=$(get_secret nextgen_ff_alerts_webhook)