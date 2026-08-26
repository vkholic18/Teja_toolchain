#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Shared setup script for QZ2 worker subpipeline steps
# Sets up vault access and fetches kubeconfig for the target mzone

setup_qz2_kubeconfig() {
    echo "=========================================="
    echo "Setting up QZ2 Kubeconfig"
    echo "=========================================="

    # Get MZONE_NAME from environment (set by set_env as qz2-mzone-name)
    export MZONE_NAME=$(get_env qz2-mzone-name)
    
    if [ -z "${MZONE_NAME}" ]; then
      echo "ERROR: MZONE_NAME environment variable is not set"
      echo "Tried to get from: qz2-mzone-name"
      exit 1
    fi

    echo "Using MZONE_NAME: ${MZONE_NAME}"

    # Derive TEKTON_WORKER from MZONE_NAME
    REGIONDIGIT=${MZONE_NAME#*[[:digit:]]}  # Remove everything up to and including first digit
    REGIONDIGIT=${REGIONDIGIT:0:1}          # Take only the first character (2nd digit)

    # Map region digit 1 to 0 (dal11 -> dal10)
    [ "${REGIONDIGIT}" == "1" ] && REGIONDIGIT="0"

    echo "Extracted region digit: ${REGIONDIGIT} from mzone: ${MZONE_NAME}"

    export TEKTON_WORKER="qz2-tekton-worker-trigger-dal1${REGIONDIGIT}"
    echo "Derived TEKTON_WORKER: ${TEKTON_WORKER}"

    # Get Vault IP from Tekton worker
    case "${TEKTON_WORKER}" in
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

    # Get secrets from environment
    export DAL_VAULT_KEY=$(get_secret clconc-vault-dal-qz1-genctl-deploy-key)

    # Set Vault configuration
    export VAULT_CACERT="${PATH_TO_GENCTL_CI}/certificates/vault-dal-intermediary-ca.pem"
    export VAULT_NAMESPACE="nextgen"
    export VAULT_KEY="${DAL_VAULT_KEY}"
    export VAULT_ADDR="https://${VAULT_IP}:8200"

    # Create secure directory structure
    rm -rf .ngsec
    mkdir -p .ngsec/tmpsec
    cp ${VAULT_CACERT} .ngsec/vault-intermediary_ca.crt
    export VAULT_TOKEN_PATH=.ngsec/tmpsec/token
    export VAULT_TOKEN_FILE=.ngsec/tmpsec/token

    # Fetch Vault token
    set +x
    curl --retry 5 \
        -H "X-Vault-Namespace: ${VAULT_NAMESPACE}" \
        --cacert .ngsec/vault-intermediary_ca.crt \
        --data "${VAULT_KEY}" \
        --url ${VAULT_ADDR}/v1/auth/approle/login \
        -s | jq -r .auth.client_token > .ngsec/tmpsec/token

    chmod 600 .ngsec/tmpsec/token

    if [ -s .ngsec/tmpsec/token ]; then
        echo "Successfully retrieved Vault token"
        export VAULT_TOKEN=$(cat .ngsec/tmpsec/token)
    else
        echo "✗ Error: Unable to get vault token"
        set -x
        return 1
    fi
    set -x

    # Fetch kubeconfig from Vault
    KUBECONFIG_VOLUME_DIR="${WORKSPACE}/mzone-configs/${MZONE_NAME}"
    mkdir -p "${KUBECONFIG_VOLUME_DIR}"
    export KUBECONFIG_FILE="${KUBECONFIG_VOLUME_DIR}/${MZONE_NAME}.conf"

    vault kv get -namespace=${VAULT_NAMESPACE} -format=yaml -field=data kube/${MZONE_NAME}/admin.conf > "${KUBECONFIG_FILE}"
    chmod 600 "${KUBECONFIG_FILE}"

    if [ -s "${KUBECONFIG_FILE}" ]; then
        echo "Successfully retrieved kubeconfig from Vault"
        echo "  Kubeconfig file: ${KUBECONFIG_FILE}"
        export KUBECONFIG="${KUBECONFIG_FILE}"
    else
        echo "✗ Error: Unable to retrieve kubeconfig from Vault"
        return 1
    fi

    echo "=========================================="
    echo "QZ2 Kubeconfig Setup Complete"
    echo "=========================================="
}

# Made with Bob