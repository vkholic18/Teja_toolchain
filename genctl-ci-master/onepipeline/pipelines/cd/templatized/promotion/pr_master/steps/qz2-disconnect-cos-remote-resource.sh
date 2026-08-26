#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script handles disconnecting COS remote resources for qz2 worker subpipeline validations
# It adds the razee debug label to prevent the remote resource controller from managing the ffsld

set -e
set +x

echo "=========================================="
echo "QZ2 Disconnect COS Remote Resource"
echo "=========================================="

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source shared kubeconfig setup
source ${PATH_TO_PIPELINE}/steps/qz2-setup-kubeconfig.sh

# Setup kubeconfig
setup_qz2_kubeconfig

echo "Executing disconnect commands..."
echo "Target MZONE: ${MZONE_NAME}"

echo 'Testing kubectl access...'
kubectl get pods -n razee

echo "Adding debug label to disconnect COS remote resource..."
# Add the debug label to genctl namespace to prevent remote resource controller from managing the ffsld
set +x
echo 'kubectl label ffsld -n genctl genctl-ffs-ld deploy.razee.io/debug="true" --overwrite'
kubectl label ffsld -n genctl genctl-ffs-ld deploy.razee.io/debug="true" --overwrite
set -x

echo "Label addition complete"

echo "=========================================="
echo "QZ2 Disconnect COS Remote Resource Complete"
echo "=========================================="

# Made with Bob