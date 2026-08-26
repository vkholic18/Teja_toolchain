#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================
set -euo pipefail

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

NAMESPACE="${NAMESPACE:-$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)}"
PIPELINE_RUN_NAME="${PIPELINE_RUN_NAME:?PIPELINE_RUN_NAME not set}"

# List of kube contexts for private CI clusters
CI_CLUSTERS=(
  "cfurn1dl0diob85a3nl0"
  "cianr93w0sjo00sko3k0"
)

# Source the ibmcloud_utils.sh
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

# Login to ibmcloud using function defined in ibmcloud_utils.sh
ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}" "us-south"

FOUND_CLUSTER_ID=""
FOUND_CLUSTER_CONTEXT=""

for CLUSTER_ID in "${CI_CLUSTERS[@]}"; do
    echo "Checking namespace '${NAMESPACE}' on cluster '${CLUSTER_ID}'..."

    # Fetch kubeconfig via existing function
    if ! get_iks_cluster_config "${CLUSTER_ID}"; then
        echo "Unable to configure cluster '${CLUSTER_ID}', skipping..."
        continue
    fi

    CURRENT_CONTEXT=$(kubectl config current-context)

    if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
        echo "Namespace found on cluster '${CLUSTER_ID}' (context: ${CURRENT_CONTEXT})"
        FOUND_CLUSTER_ID="${CLUSTER_ID}"
        FOUND_CLUSTER_CONTEXT="${CURRENT_CONTEXT}"
        break
    else
        echo "Namespace not found on cluster '${CLUSTER_ID}'"
    fi
done

#############################################
# Final decision
#############################################
if [[ -z "${FOUND_CLUSTER_ID}" ]]; then
    echo "Pipeline namespace '${NAMESPACE}' was NOT found on any private CI cluster."
    echo "This pipeline is likely running on public or other private workers."
    echo "Logs cannot be fetched via Kubernetes API for further analysis."
    exit 0
fi

echo "Proceeding with log analysis on private CI cluster '${FOUND_CLUSTER_ID}'"
echo "Using kubectl context '${FOUND_CLUSTER_CONTEXT}'"

TMP_DIR="${CI_TEMP_DIR}/log_analyse"
mkdir -p "${TMP_DIR}"

pushd "${TMP_DIR}"

OUTPUT_FILE="failed-task-logs.txt"
MAX_LINES_PER_CONTAINER=300

> "$OUTPUT_FILE"

echo "Collecting failed task logs for PipelineRun: $PIPELINE_RUN_NAME"
echo "Namespace: $NAMESPACE"
echo "----------------------------------------" >> "$OUTPUT_FILE"

# Get all pods for this PipelineRun
PODS=$(kubectl get pods -n "$NAMESPACE" \
  -l tekton.dev/pipelineRun="$PIPELINE_RUN_NAME" \
  -o jsonpath='{.items[*].metadata.name}')

if [[ -z "$PODS" ]]; then
  echo "No pods found for PipelineRun"
  exit 0
fi

for POD in $PODS; do
  echo "Checking pod: $POD"

  # Get failed containers in this pod
  FAILED_CONTAINERS=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json | \
    jq -r '
      .status.containerStatuses[]
      | select(.state.terminated != null)
      | select(.state.terminated.exitCode != 0)
      | .name
    ')

  if [[ -z "$FAILED_CONTAINERS" ]]; then
    continue
  fi

  echo "" >> "$OUTPUT_FILE"
  echo "Failed Task Pod: $POD" >> "$OUTPUT_FILE"
  echo "----------------------------------------" >> "$OUTPUT_FILE"

  for CONTAINER in $FAILED_CONTAINERS; do
    echo "Container: $CONTAINER" >> "$OUTPUT_FILE"
    echo "----------------------------------------" >> "$OUTPUT_FILE"

    kubectl logs "$POD" -n "$NAMESPACE" -c "$CONTAINER" \
      --tail="$MAX_LINES_PER_CONTAINER" >> "$OUTPUT_FILE" || true

    echo "" >> "$OUTPUT_FILE"
  done
done

echo "Failed task logs written to $OUTPUT_FILE"

sed -i -E 's/(token|password|apikey)=\S+/REDACTED/g' failed-task-logs.txt

# Set Bob credentials
export BOBSHELL_API_KEY=$(get_env bob_api_key)
export BOBSHELL_BASE_URL="https://prod.ibm-bob-staging.cloud.ibm.com"

# Color codes
BOLD="\033[1m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
RESET="\033[0m"

BOB_OUTPUT=$(cat ${PATH_TO_GENCTL_CI}/scripts/log_analysis/prompt.txt | bob --accept-license --auth-method api-key --chat-mode advanced | sed -n '/---output---/,/---output---/p' | sed '1d;$d')

echo ""
echo -e "${CYAN}========================================${RESET}"
echo -e "${BOLD}${CYAN}        CI Failure Analysis Report${RESET}"
echo -e "${CYAN}========================================${RESET}"
echo -e "${YELLOW}${BOB_OUTPUT}${RESET}"
echo -e "${GREEN}========================================${RESET}"
echo -e "${BOLD}${GREEN}           End of Analysis${RESET}"
echo -e "${GREEN}========================================${RESET}"
echo ""

popd
