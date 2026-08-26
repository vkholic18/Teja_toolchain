#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script handles reconnecting COS remote resources for qz2 worker subpipeline
# It removes the razee debug label to allow the remote resource controller to manage the ffsld

set -e
set +x

echo "=========================================="
echo "QZ2 Reconnect COS Remote Resource"
echo "=========================================="

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source shared kubeconfig setup
source ${PATH_TO_PIPELINE}/steps/qz2-setup-kubeconfig.sh

# Setup kubeconfig
setup_qz2_kubeconfig

echo "Testing kubectl access..."
kubectl get pods -n razee

echo "Removing debug label to reconnect COS remote resource..."
echo "Target MZONE: ${MZONE_NAME}"

# Remove the debug label from genctl namespace to allow remote resource controller to manage the ffsld
set +x
echo 'kubectl label ffsld -n genctl genctl-ffs-ld deploy.razee.io/debug-'
kubectl label ffsld -n genctl genctl-ffs-ld deploy.razee.io/debug-
set -x

echo "Waiting for remote resource controller to sync..."
sleep 15

echo "Label removal complete"

echo "=========================================="
echo "QZ2 Reconnect COS Remote Resource Complete"
echo "=========================================="

# Made with Bob