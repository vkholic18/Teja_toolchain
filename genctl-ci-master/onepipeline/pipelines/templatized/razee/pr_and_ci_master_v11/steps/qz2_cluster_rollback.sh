#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -e
set +x

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

#source icr related utils
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="razee"

export PIPELINE_TYPE="pr"

# Define the repositories to be cloned
REPOS_TO_CLONE="
PLATFORM_INVENTORY
"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Clone required repos
clone_repos_from_env_vars "${IBM_HTTPS_BASE_URL}" "${WORKSPACE}" "${REPOS_TO_CLONE}" 

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_PLATFORM_INVENTORY_REPO="${WORKSPACE}/${PLATFORM_INVENTORY_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

export MZONE_NAME=$(get_env qz2-mzone-name)
export TEKTON_WORKER=$(get_env qz2-worker-id)
export LAUNCH_DARKLY_FEATURE_FLAG=$(get_env launch-darkly-feature-flag)

echo $MZONE_NAME
echo $TEKTON_WORKER


get_vault_ip_from_tekton_worker() {
    TEKTON_WORKER_FULL="$1"

    echo "Processing worker: ${TEKTON_WORKER_FULL}"

    case "${TEKTON_WORKER_FULL}" in
        qz2-tekton-worker-trigger-dal10)
            export VAULT_IP="10.200.95.45"
            ;;
        qz2-tekton-worker-trigger-dal12)
            export VAULT_IP="10.200.127.45"
            ;;
        qz2-tekton-worker-trigger-dal13)
            export VAULT_IP="10.200.143.45"
            ;;
        qz2-tekton-worker-trigger-dal14)
            export VAULT_IP="10.200.127.45"
            ;;
    esac

    echo "Vault IP set to: ${VAULT_IP}"
}

setup_vault_configuration() {
    echo "Fetching secrets from Vault..."
    echo "MZONE_NAME: ${MZONE_NAME}"
    echo "VAULT_IP: ${VAULT_IP}"

    # Set required paths and variables
    export PATH_TO_PLATFORM_INVENTORY_REPO="${WORKSPACE}/${PLATFORM_INVENTORY_REPO_NAME}"

    # Get secrets from environment
    export DAL_VAULT_KEY=$(get_env clconc-vault-dal-qz1-genctl-deploy-key)

    # Set Vault configuration
    export VAULT_CACERT="${PATH_TO_GENCTL_CI}/certificates/vault-dal-intermediary-ca.pem"
    export VAULT_NAMESPACE="nextgen"
    export VAULT_KEY="${DAL_VAULT_KEY}"
    export VAULT_ADDR="https://${VAULT_IP}:8200"

    echo "Vault configuration complete"
}

create_secure_directory() {
    echo "Creating secure directory structure..."

    # Create secure directory structure
    rm -rf .ngsec
    mkdir -p .ngsec/tmpsec

    # Copy vault certificate
    cp ${VAULT_CACERT} .ngsec/vault-intermediary_ca.crt

    # Set vault paths
    export VAULT_TOKEN_PATH=.ngsec/tmpsec/token
    export VAULT_TOKEN_FILE=.ngsec/tmpsec/token

    echo ".ngsec folder will contain token + certificate + vault.env file"
    echo "Secure directory created"
}

fetch_vault_token() {
    echo "Fetching Vault token..."

    VAULT_CACERT_PATH=.ngsec/vault-intermediary_ca.crt

    # Disable command echoing for security
    set +x

    # Fetch Vault token
    curl --retry 5 \
        -H "X-Vault-Namespace: ${VAULT_NAMESPACE}" \
        --cacert "$VAULT_CACERT_PATH" \
        --data "${VAULT_KEY}" \
        --url ${VAULT_ADDR}/v1/auth/approle/login \
        -s | jq -r .auth.client_token > .ngsec/tmpsec/token

    # Secure the token file
    chmod 600 .ngsec/tmpsec/token

    # Verify token was retrieved
    if [ -s .ngsec/tmpsec/token ]; then
        echo "Successfully retrieved Vault token"
        export VAULT_TOKEN=$(cat .ngsec/tmpsec/token)
        return 0
    else
        echo "Error: Unable to get vault token"
        return 1
    fi
}

fetch_kubeconfig_from_vault() {
    echo "Fetching kubeconfig from Vault..."

    # Save kubeconfig with mzone name
    KUBECONFIG_VOLUME_DIR="${WORKSPACE}/mzone-configs/${MZONE_NAME}"
    mkdir -p "${KUBECONFIG_VOLUME_DIR}"
    KUBECONFIG_FILE="${KUBECONFIG_VOLUME_DIR}/${MZONE_NAME}.conf"

    # Fetch kubeconfig from Vault
    vault kv get -namespace=${VAULT_NAMESPACE} -format=yaml -field=data kube/${MZONE_NAME}/admin.conf > "${KUBECONFIG_FILE}"

    # Secure the kubeconfig file
    chmod 600 "${KUBECONFIG_FILE}"

    echo "Kubeconfig saved to: ${KUBECONFIG_FILE}"

    # Verify kubeconfig was retrieved
    if [ -s "${KUBECONFIG_FILE}" ]; then
        echo "Successfully retrieved kubeconfig from Vault"

        # Print file size
        FILE_SIZE=$(wc -c < "${KUBECONFIG_FILE}")
        echo "Kubeconfig file size: ${FILE_SIZE} bytes"

        # Print first line safely (usually contains apiVersion or similar)
        FIRST_LINE=$(head -n 1 "${KUBECONFIG_FILE}")
        echo "First line: ${FIRST_LINE}"

        # Alternative: Print file info using ls
        echo "File details: $(ls -lh "${KUBECONFIG_FILE}" | awk '{print $5, $9}')"

        # Export for use in other functions
        export KUBECONFIG_FILE
        return 0
    else
        echo "Error: Unable to retrieve kubeconfig from Vault"
        return 1
    fi
}

setup_brt_validation_prerequisites() {
    echo "=========================================="
    echo "Setting up BRT validation prerequisites"
    echo "=========================================="

    # Get Vault IP from Tekton worker
    get_vault_ip_from_tekton_worker "${TEKTON_WORKER}"

    # Vault operations
    setup_vault_configuration
    create_secure_directory
    fetch_vault_token

    # Kubeconfig management
    fetch_kubeconfig_from_vault

    # Test kubectl access
    echo "Testing kubectl access..."
}

reconnect_cos_remote_resource_for_genctl() {
    echo "Executing validation commands directly (containerless)..."

    # Set kubeconfig to use the file we retrieved from Vault
    export KUBECONFIG="${KUBECONFIG_FILE}"

    echo 'kubectl label ffsld -n genctl genctl-ffs-ld deploy.razee.io/debug-'
    kubectl label ffsld -n genctl genctl-ffs-ld deploy.razee.io/debug-

}


#==============================================================================
# MAIN EXECUTION
#==============================================================================

# Setup all prerequisites for BRT validation
setup_brt_validation_prerequisites

# Cluster validation
reconnect_cos_remote_resource_for_genctl

echo "Reconnecting cos remote resource completeled successfully"
