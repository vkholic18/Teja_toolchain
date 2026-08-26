#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Secrets are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

env_props_secure=(
    ### Used in build, ICCR, create and upload candidate files, move from pre-release to vetted ###
    "CC_ARTIF_ACCESS_TOKEN:wcp-genctl-docker-local-artifactory-token"

    ### Used in build, auto-semver ###
    "GIT_PRIVATE_KEY:ghe-private-key"
    "VAULT_GIT_CONFIG_USER_EMAIL:vault-git-config-user-email"
    "VAULT_GIT_CONFIG_USERNAME:vault-git-config-username"

    ### Used in auto-semver ###
    "GITHUB_API_KEY:ghe-access-token"

    ### Used in build ###
    "GHE_RO_TOKEN:clconc-ghe-ro-token"
    "GHE_USERNAME:clconc-ghe-username"
    "ARTIFACTORY_USER:wcp-genctl-docker-local-artifactory-username"
    "GPG_SIGNING_KEY:gpg-signing-key" 
    "GPG_SIGNING_PW:gpg-signing-pw"

    # ARTIFACTORY_API_KEY:wcp-genctl-docker-local-artifactory-token --> OLD as per  https://github.ibm.com/genctl-cicd/genctl-ci/pull/3350

    "CC_ARTIFACTORY_READER:clgitchk-artifactory-username"
    "CC_ARTIFACTORY_READER_APIKEY:clgitchk-artifactory-token"
    # DOCKER_TOKEN= ?? - TODO: Add secrets ?
    # DOCKER_USERNAME= ?? - TODO: Add secrets ?

    ### Used in upload to COS ###
    "COS_SERVICE_CREDENTIALS:vault-ibm-cos-creds"

    ### Used in LaunchDarkly ###
    "AUTH_TOKEN:vault-launch-darkly-api-key"

    ### Used for Security Services Workspace in their run-unit-tests.sh ###
    "GENCTL_IAM_REST_SERVER_API_KEY:genctl-iam-rest-server-api-key"
    "ICR_API_KEY:ibmcloud-icr-api-key"

    # Used in kali and nscon
    "SDN_READ_SECRETS_API_KEY:sdn-read-secrets-api-key"
)

env_props_text=()

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"
