#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Secrets are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline
env_props_secure=(
    ### Used in retag, move ZIP from vetted to final destination, Download JSON and inventory add, deploy-dal, smoke ###
    "CC_ARTIF_ACCESS_TOKEN:wcp-genctl-docker-local-artifactory-token"

    ### Used in auto-semver, retag, prepare genctl release bundle, deploy-dal, smoke ###
    "GIT_PRIVATE_KEY:ghe-private-key"

    ### Used in auto-semver, retag, deploy-dal, smoke ###
    "VAULT_GIT_CONFIG_USER_EMAIL:vault-git-config-user-email"
    "VAULT_GIT_CONFIG_USERNAME:vault-git-config-username"

    ### Used in LaunchDarkly, deploy-dal ###
    "AUTH_TOKEN:vault-launch-darkly-api-key"

    ### Used in auto-semver ###
    "GITHUB_API_KEY:ghe-access-token"

    ### Used in retag ###
    "ARTIFACTORY_USER:wcp-genctl-docker-local-artifactory-username"
    # DOCKER_TOKEN= ?? - TODO: Add secrets ?
    # DOCKER_USERNAME= ?? - TODO: Add secrets ?

    ### Used in Update release version ###
    "JIRA_USERNAME:jira_username"
    "JIRA_PASSWORD:jira_password"

    ### Used in upload to COS ###
    "COS_SERVICE_CREDENTIALS:vault-ibm-cos-creds"

    ### Used in prepare genctl release bundle ###
    "GHE_USERNAME:clconc-ghe-username"

    ### Used in deploy dal ###
    "IBMCLOUD_KEY:clconc-Balaji-ibmcloud-key"
    "IBMCLOUD_ACCOUNT:ibmcloud-balaji-account-id"
    "DAL_VAULT_KEY:clconc-vault-dal-qz1-genctl-deploy-key"

    ### Used in smoke ###
    "SECRET_MANAGER_KEY_CSI:secret-manager-api-key-csi"
)


env_props_text=()

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"
