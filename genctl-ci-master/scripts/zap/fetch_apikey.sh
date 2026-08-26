#!/bin/bash
#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Script: fetch_apikey_sm.sh
# Purpose: Connect to IBM Secrets Manager (account: Cldgen139) via the IBM Cloud CLI
#          and fetch the value of the secret identified by $APIKEY_ALIAS.
#
# The IBM Cloud API key is read from the pipeline environment property:
#   secret-manager-api-key-csi
# ---------------------------------------------------------------------------

set -euo pipefail
# ---------------------------------------------------------------------------
# Inputs — injected by the IBM Cloud Toolchain pipeline
# ---------------------------------------------------------------------------

# API key stored in the pipeline env property: secret-manager-api-key-csi
IBM_CLOUD_APIKEY="${SECRET_MANAGER_KEY_CSI:?secret-manager-api-key-csi env property is required}"

# Full URL of the Secrets Manager instance (public endpoint, no trailing path).
# Private endpoint (contains ".private.") is NOT reachable from the toolchain runner.
# Format: https://<instance-guid>.<region>.secrets-manager.appdomain.cloud
SM_INSTANCE_URL=$(get_secret cldgen139-sm-instance-url)

# ---------------------------------------------------------------------------
# Helper: timestamped log
# ---------------------------------------------------------------------------
log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

# ---------------------------------------------------------------------------
# 1. Log in to IBM Cloud (account: Cldgen139)
# ---------------------------------------------------------------------------
log "Logging in to IBM Cloud (account: Cldgen139)..."
ibmcloud login \
    --apikey "${IBM_CLOUD_APIKEY}" \
    --no-region

# ---------------------------------------------------------------------------
# 2. Ensure the secrets-manager plugin is installed
# ---------------------------------------------------------------------------
log "Checking for secrets-manager plugin..."
if ibmcloud plugin list 2>/dev/null | grep -q "secrets-manager"; then
    log "secrets-manager plugin is already installed."
else
    log "secrets-manager plugin not found — installing..."
    ibmcloud plugin install secrets-manager -f -r "IBM Cloud"
    log "secrets-manager plugin installed successfully."
fi

# ---------------------------------------------------------------------------
# 3. Point the CLI at the Secrets Manager instance
# ---------------------------------------------------------------------------
log "Setting Secrets Manager service URL: ${SM_INSTANCE_URL}"
ibmcloud secrets-manager config set service-url "${SM_INSTANCE_URL}"

# ---------------------------------------------------------------------------
# 4. Resolve the secret ID by matching the middle segment of the secret name.
#    Secret name format: "<anything>.<APIKEY_ALIAS>.<anything>"
#    e.g. "staging.cicd-mz2309.credentials"
#    The prefix and suffix are unknown, so match by ".<APIKEY_ALIAS>." anywhere
#    in the name using jq's contains() filter.
#
#    IBM Secrets Manager paginates at 200 secrets per page (default limit).
#    This loop walks every page using --limit / --offset until the secret is
#    found or all pages are exhausted.
# ---------------------------------------------------------------------------
log "Resolving secret ID — searching for secret containing '.${APIKEY_ALIAS}.' in its name..."

PAGE_LIMIT=200
OFFSET=0
SECRET_ID=""
SECRETS_CHECKED=0
PAGES_SCANNED=0
ALL_PAGES_SCANNED=false
TOTAL_COUNT=0   # total secrets in the instance, reported by the first API response

while true; do
    PAGE_JSON=$(ibmcloud secrets-manager secrets \
        --limit "${PAGE_LIMIT}" \
        --offset "${OFFSET}" \
        --output json)

    # Capture the instance-wide total_count from the first page response
    if [[ "${PAGES_SCANNED}" -eq 0 ]]; then
        TOTAL_COUNT=$(echo "${PAGE_JSON}" | jq '.total_count // 0')
        TOTAL_PAGES=$(( (TOTAL_COUNT + PAGE_LIMIT - 1) / PAGE_LIMIT ))
    fi

    PAGE_COUNT=$(echo "${PAGE_JSON}" | \
        jq '(.secrets // .resources // .[]) | length')

    SECRETS_CHECKED=$(( SECRETS_CHECKED + PAGE_COUNT ))
    PAGES_SCANNED=$(( PAGES_SCANNED + 1 ))

    # Extract list — v2 plugin: .secrets[]  /  v1 plugin: .resources[]
    PAGE_ID=$(echo "${PAGE_JSON}" | \
        jq -r --arg pattern ".${APIKEY_ALIAS}." \
            '(.secrets // .resources // .[])[] | select(.name | contains($pattern)) | .id' \
        2>/dev/null || true)

    if [[ -n "${PAGE_ID}" ]]; then
        SECRET_ID="${PAGE_ID}"
        break
    fi

    if [[ "${PAGE_COUNT}" -lt "${PAGE_LIMIT}" ]]; then
        ALL_PAGES_SCANNED=true
        break
    fi

    OFFSET=$(( OFFSET + PAGE_LIMIT ))
    sleep 1   # brief delay between pages to avoid hitting the 10 req/s rate limit
done

if [[ "${ALL_PAGES_SCANNED}" == "true" ]]; then
    log "Secrets search complete: scanned all ${PAGES_SCANNED} of ${TOTAL_PAGES} page(s), ${SECRETS_CHECKED} of ${TOTAL_COUNT} secret(s) — '${APIKEY_ALIAS}' not found."
else
    log "Secrets search complete: found '${APIKEY_ALIAS}' on page ${PAGES_SCANNED} of ${TOTAL_PAGES} (checked ${SECRETS_CHECKED} of ${TOTAL_COUNT} secret(s) — stopped early because the match was found)."
fi

if [[ -z "${SECRET_ID}" ]]; then
    log "ERROR: No secret whose name contains '.${APIKEY_ALIAS}.' was found in Secrets Manager."
    exit 1
fi
log "Resolved secret ID: ${SECRET_ID}"

# ---------------------------------------------------------------------------
# 5. Fetch the secret value
# ---------------------------------------------------------------------------
log "Fetching secret value for '${APIKEY_ALIAS}'..."
SECRET_JSON=$(ibmcloud secrets-manager secret \
    --id "${SECRET_ID}" \
    --output json)

# Secret type is "kv" — the API key is at .data.apikey
DYNAMIC_SCAN_ACCESS_API_KEY=$(echo "${SECRET_JSON}" | \
    jq -r '.data.apikey')

if [[ -z "${DYNAMIC_SCAN_ACCESS_API_KEY}" || "${DYNAMIC_SCAN_ACCESS_API_KEY}" == "null" ]]; then
    log "ERROR: Could not extract payload for secret '${APIKEY_ALIAS}'."
    exit 1
fi

log "Successfully fetched secret '${APIKEY_ALIAS}'."