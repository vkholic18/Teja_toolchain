#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# This script will use the compiler script inside platform-inventory/hack/ci
# and will generate k8s configmaps using the information located in region/undercloud files
# it will then run kubectl apply dry-run against the generated manifest to verify the manifests are
# useable configmaps
# =============================================================================================
root_dir=$(pwd)

if [[ ${DRY_RUN_DEPLOYMENT_ENABLED} == "false" ]]; then
  echo "Dry run deployment test is disabled. Exiting ..."
  exit 0
fi

./genctl-ci-repo/scripts/build_undercloud_cm.sh $root_dir $WORKSPACE $CM_OUTPUT_DIR

# dryrun
set +x  # so we don't log the password
mkdir ${HOME}/.kube/
echo -e "${K8_CI_CLUSTER1_CONFIG}" > ${HOME}/.kube/config1
echo -e "${K8_CI_CLUSTER2_CONFIG}" > ${HOME}/.kube/config2

export KUBECONFIG=${HOME}/.kube/config1
kubectl get no
cluster_connect=$?
echo $cluster_connect
set -e
if [[ ${cluster_connect} == 0 ]]; then
    echo "Succesfully connected to cluster:"
    kubectl cluster-info
else
    export KUBECONFIG=${HOME}/.kube/config2
    kubectl cluster-info
fi

cd $root_dir/$CM_OUTPUT_DIR
ls -la
for file in *undercloud.yml; do
    set +e
    echo "Template manifest file $file found, and being evaluated"
    kubectl apply --validate=true --dry-run=client --filename=$file
    result=$?
    set -e
    if [[ ${result} == 0 ]]; then
        echo "Deployment manifest $file successfully evaluated"
    else
        echo "Failed to evaluate deployment manifest file $file"
        cat ${file}
        exit ${result}
    fi
done
