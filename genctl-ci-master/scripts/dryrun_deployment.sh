#!/bin/bash


build_root="${PWD}"
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
GENCTL_MANIFEST_RELEASE_DIR="/tmp/genctl-release-work"
RIAS_MANIFEST_RELEASE_DIR="/tmp/rias-release-work"
RIAS_ETCD_MANIFEST_RELEASE_DIR="/tmp/rias-etcd-release-work"
DEFAULT_RIAS_GLOBAL_FILE="rias-ng-us-south-dal-dev25-etcd.json"
DEFAULT_RIAS_ETCD_GLOBAL_FILE="rias-ng-us-south-dal-dev25-etcd.json"
DEFAULT_GENCTL_GLOBAL_FILE="mzone2309-globals.json"
IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev25-etcd"

apply_manifests() {
    # test manifests with kubectl apply dryrun
    #check that the directory with the deployment files is not empty
    if [ "$(ls -A $1/aorta-manifests-filtered)" ]; then
        ls -la $1/aorta-manifests-filtered
        for file in "$1"/aorta-manifests-filtered/*; do
            set +e
            echo "Template manifest file $file found for $COMPONENT"
            kubectl apply --validate=true --dry-run=true --filename=$file
            result=$?
            echo $result
            set -e
            if [[ ${result} == 0 ]]; then
                echo "Deployment manifest $file successfully evaluated"
            else
                echo "Failed to evaluate deployment manifest file $file"
                cat ${file}
                exit ${result}
            fi
        done
    else
        echo "$1/aorta-manifests-filtered is empty, nothing to process, continue ...,"
    fi

}

if [[ ${DRY_RUN_DEPLOYMENT_ENABLED} == "false" ]]; then
  echo "Dry run deployment test is disabled. Exiting ..."
  exit 0
fi

# Setup pip
mkdir -p ~/.pip
echo [global] > ~/.pip/pip.conf
set +x  # so we don't log the password
echo index-url = https://${WCP_ARTIFACTORY_USERNAME}:${CC_ARTIF_ACCESS_TOKEN}@na.artifactory.swg-devops.com/artifactory/api/pypi/hyc-nextgen-pypi-virtual/simple >> ~/.pip/pip.conf
set -x
#install nextgen-service-deployer
python -m pip install ${NEXTGEN_SERVICE_DEPLOYER}==${NEXTGEN_SERVICE_DEPLOYER_VER}


set +x  # so we don't log the password
mkdir ${HOME}/.kube/
echo -e "${K8_CI_CLUSTER1_CONFIG}" > ${HOME}/.kube/config1
echo -e "${K8_CI_CLUSTER2_CONFIG}" > ${HOME}/.kube/config2
set -x

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

cd ${build_root}/workspace/
component_hash_new=$(git rev-parse --verify HEAD)
echo new components git ref: $component_hash_new
if [ -f "./.git/resource/url" ]; then
    # New git PR puller
    pr_url=$(cat .git/resource/url)
else
    # Assume old git PR puller
    pr_url=$(git config --get pullrequest.url)
fi
echo new components pr url: $pr_url
cd ${build_root}

# test genctl component
set +e
python3 -m pip install -r genctl-ci-repo/scripts/dryrun_deploy_requirements.txt
python3 genctl-ci-repo/scripts/exist_in_orda_inventory_json.py ${COMPONENT} genctl-release-repo/component-input/components.json
result=$?
echo $result
set -e

if [[ ${result} == 0 ]]; then
    echo "component ${COMPONENT} is a GENCTL component."
    pushd genctl-release-repo
    make mostlyclean
    make distclean
    make release-tarball
    popd
    ### replace hash and url in the inventory.json file
    if [[ -f genctl-release-repo/build/inventory.json ]]; then
        url=
        if [ -n "$pr_url" ]; then
            url=$(genctl-ci-repo/scripts/git_url_to_clone_address.py ${pr_url})
        fi
        genctl-ci-repo/scripts/update_inventory_json.py $COMPONENT $component_hash_new "${url}" genctl-release-repo/build/inventory.json genctl-release-repo/inventory.json
        cat genctl-release-repo/inventory.json
    else
        echo "Failed to find a genctl-release/build/inventory.json file, quitting..."
        exit 1
    fi
    pushd genctl-release-repo
    make distclean
    make release-tarball INVENTORY_PATH=./inventory.json
    nextgen-deploy --data_path_root=${GENCTL_MANIFEST_RELEASE_DIR} manifests render -t $(ls -t ./dist/*.tar.gz | head -n1) \
                   -i ./build/inventory.json --globals_file=${build_root}/genctl-globals-repo/${DEFAULT_GENCTL_GLOBAL_FILE}
    popd
    #filter manifest files to the ${GENCTL_MANIFEST_RELEASE_DIR}/aorta-manifests-filtered
    python3 genctl-ci-repo/scripts/filter_manifest_files.py ${COMPONENT} genctl-release-repo/component-input/components.json ${GENCTL_MANIFEST_RELEASE_DIR}/aorta-manifests ${GENCTL_MANIFEST_RELEASE_DIR}/aorta-manifests-filtered

    apply_manifests ${GENCTL_MANIFEST_RELEASE_DIR}
fi

# test rias-release component
set +e
python3 genctl-ci-repo/scripts/exist_in_inventory_json.py ${COMPONENT} rias-release/component-input/inventory.json
rias_shared_result=$?
echo $rias_shared_result
set -e

if [[ ${rias_shared_result} == 0 ]]; then
    echo "component ${COMPONENT} is RIAS component."
    ### replace hash and url in the inventory.json file
    if [[ -f rias-release/component-input/inventory.json ]]; then
        url=
        if [ -n "$pr_url" ]; then
            url=$(genctl-ci-repo/scripts/git_url_to_clone_address.py ${pr_url})
        fi
        genctl-ci-repo/scripts/update_inventory_json.py $COMPONENT $component_hash_new "${url}" rias-release/component-input/inventory.json inventory.json
        cp inventory.json rias-release/component-input/inventory.json
        cat rias-release/component-input/inventory.json
    else
        echo "Failed to find a rias-release/component-input/inventory.json file, quitting..."
        exit 1
    fi
    pushd rias-release
    make mostlyclean
    make distclean
    make clean release-tarball
    nextgen-deploy --data_path_root=${RIAS_MANIFEST_RELEASE_DIR} manifests render --release_tarball=$(ls -t ./dist/*.tar.gz | head -n1) \
                   --globals_file=${build_root}/rias-globals-repo/cicd/${DEFAULT_RIAS_GLOBAL_FILE}
    popd

    #filter manifest files to the ${RIAS_MANIFEST_RELEASE_DIR}/aorta-manifests-filtered
    python3 genctl-ci-repo/scripts/filter_manifest_files.py ${COMPONENT} rias-release/component-input/components.json ${RIAS_MANIFEST_RELEASE_DIR}/aorta-manifests ${RIAS_MANIFEST_RELEASE_DIR}/aorta-manifests-filtered

    apply_manifests ${RIAS_MANIFEST_RELEASE_DIR}
fi

# test rias-etcd-release component
set +e
python3 genctl-ci-repo/scripts/exist_in_inventory_json.py ${COMPONENT} rias-etcd-release/component-input/inventory.json
rias_etcd_shared_result=$?
echo rias_etcd_shared_result
set -e
if [[ ${rias_etcd_shared_result} == 0 ]]; then
    echo "component ${COMPONENT} is RIAS-ETCD component."
    ### replace hash and url in the inventory.json file
    if [[ -f rias-etcd-release/component-input/inventory.json ]]; then
        url=
        if [ -n "$pr_url" ]; then
            url=$(genctl-ci-repo/scripts/git_url_to_clone_address.py ${pr_url})
        fi
        genctl-ci-repo/scripts/update_inventory_json.py $COMPONENT $component_hash_new "${url}" rias-etcd-release/component-input/inventory.json inventory.json
        cp inventory.json rias-etcd-release/component-input/inventory.json
        cat rias-etcd-release/component-input/inventory.json
    else
        echo "Failed to find a rias-etcd-release/component-input/inventory.json file, quitting..."
        exit 1
    fi
    pushd rias-etcd-release
    make mostlyclean
    make distclean
    make clean release-tarball
    nextgen-deploy --data_path_root=${RIAS_ETCD_MANIFEST_RELEASE_DIR} manifests render --release_tarball=$(ls -t ./dist/*.tar.gz | head -n1) \
                   --globals_file=${build_root}/rias-etcd-release/component-input/env-globals/${DEFAULT_RIAS_ETCD_GLOBAL_FILE}
    popd
    #filter manifest files to the ${RIAS_MANIFEST_RELEASE_DIR}/aorta-manifests-filtered
    python3 genctl-ci-repo/scripts/filter_manifest_files.py ${COMPONENT} rias-etcd-release/component-input/components.json ${RIAS_ETCD_MANIFEST_RELEASE_DIR}/aorta-manifests ${RIAS_ETCD_MANIFEST_RELEASE_DIR}/aorta-manifests-filtered

    apply_manifests ${RIAS_ETCD_MANIFEST_RELEASE_DIR}
fi
