#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Secrets are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

### Used in check secrets, validate client API version, build, unit test, K3 tests ###
export GIT_PRIVATE_KEY=$(get_env ghe-private-key)

### Used in scan go ast, unit tests, K3 tests ###
export CC_ARTIFACTORY_READER=$(get_env clgitchk-artifactory-username)
export CC_ARTIFACTORY_READER_APIKEY=$(get_env clgitchk-artifactory-token)

### Used in build, unit tests, K3 tests ###
export GHE_RO_TOKEN=$(get_env clconc-ghe-ro-token)

### Used in build, unit tests ###
export GHE_USERNAME=$(get_env clconc-ghe-username)

### Used in anti-patterns, check secrets  ###
export VAULT_GIT_CONFIG_USER_EMAIL=$(get_env vault-git-config-user-email)
export VAULT_GIT_CONFIG_USERNAME=$(get_env vault-git-config-username)

### Used in validate global keys, check secrets ###
export IBMCLOUD_KEY=$(get_env clconc-Balaji-ibmcloud-key)
export DAL_VAULT_KEY=$(get_env clconc-vault-dal-qz1-genctl-deploy-key)

### Used in build ###
export ARTIFACTORY_USER=$(get_env wcp-genctl-docker-local-artifactory-username)
#export ARTIFACTORY_API_KEY=$(get_env wcp-genctl-docker-local-artifactory-token) --> OLD as per  https://github.ibm.com/genctl-cicd/genctl-ci/pull/3350
export CC_ARTIF_ACCESS_TOKEN=$(get_env wcp-genctl-docker-local-artifactory-token) # --> New as per https://github.ibm.com/genctl-cicd/genctl-ci/pull/3350
export GPG_SIGNING_KEY=$(get_env gpg-signing-key) 
export GPG_SIGNING_PW=$(get_env gpg-signing-pw)

# export DOCKER_TOKEN= ?? - TODO: Add secrets ?
# export DOCKER_USERNAME= ?? - TODO: Add secrets ?

### Used in K3 tests ###
export STORAGE_FYRE_KEY=$(get_env storage-fyre-key) 
export TERRAFORM_API_KEY=$(get_env k3s_terraform_api_key)

### Used in upload to COS ###
export COS_SERVICE_CREDENTIALS=$(get_env vault-ibm-cos-creds)


#### !!! CHECK IF NEEDED
export GITHUB_API_KEY=$(get_env ghe-access-token) # Check if needed here
####

### Used for Security Services Workspace in their run-unit-tests.sh ###
export GENCTL_IAM_REST_SERVER_API_KEY=$(get_env genctl-iam-rest-server-api-key)

env_props_secure=(
    ### Used in check secrets, validate client API version, build, unit test, K3 tests ###
    "GIT_PRIVATE_KEY:ghe-private-key"

    ### Used in scan go ast, unit tests, K3 tests ###
    "CC_ARTIFACTORY_READER:clgitchk-artifactory-username"
    "CC_ARTIFACTORY_READER_APIKEY:clgitchk-artifactory-token"

    ### Used in build, unit tests, K3 tests ###
    "GHE_RO_TOKEN:clconc-ghe-ro-token"

    ### Used in build, unit tests ###
    "GHE_USERNAME:clconc-ghe-username"

    ### Used in anti-patterns, check secrets  ###
    "VAULT_GIT_CONFIG_USER_EMAIL:vault-git-config-user-email"
    "VAULT_GIT_CONFIG_USERNAME:vault-git-config-username"

    ### Used in validate global keys, check secrets ###
    "IBMCLOUD_KEY:clconc-Balaji-ibmcloud-key"
    "DAL_VAULT_KEY:clconc-vault-dal-qz1-genctl-deploy-key"

    ### Used in build ###
    "ARTIFACTORY_USER:wcp-genctl-docker-local-artifactory-username"    
    # ARTIFACTORY_API_KEY:wcp-genctl-docker-local-artifactory-token --> OLD as per  https://github.ibm.com/genctl-cicd/genctl-ci/pull/3350
    
    # --> New as per https://github.ibm.com/genctl-cicd/genctl-ci/pull/3350
    "CC_ARTIF_ACCESS_TOKEN:wcp-genctl-docker-local-artifactory-token"
    "GPG_SIGNING_KEY:gpg-signing-key" 
    "GPG_SIGNING_PW:gpg-signing-pw"

    # DOCKER_TOKEN= ?? - TODO: Add secrets ?
    # DOCKER_USERNAME= ?? - TODO: Add secrets ?

    ### Used in K3 tests ###
    "STORAGE_FYRE_KEY:storage-fyre-key" 
    "TERRAFORM_API_KEY:k3s_terraform_api_key"

    ### Used in upload to COS ###
    "COS_SERVICE_CREDENTIALS:vault-ibm-cos-creds"

    #### !!! CHECK IF NEEDED
    "GITHUB_API_KEY:ghe-access-token"    

    ### Used for Security Services Workspace in their run-unit-tests.sh ###
    "GENCTL_IAM_REST_SERVER_API_KEY:genctl-iam-rest-server-api-key"

)

env_props_text=()

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"