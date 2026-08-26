#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2019
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

set -eux

# Declare the function

RIAS_ETCD_RELEASE_TAG=`yq -r '.version."rias-etcd-release"' $PATH_TO_VETTED_VERSIONS_REPO/${GENCTL_VETTED_VERSIONS}`
echo RIAS_ETCD_RELEASE_TAG: ${RIAS_ETCD_RELEASE_TAG} from vetted-versions-repo/${GENCTL_VETTED_VERSIONS}
RIAS_RELEASE_TAG=`yq -r '.version."rias-release"' $PATH_TO_VETTED_VERSIONS_REPO/${GENCTL_VETTED_VERSIONS}`
echo RIAS_RELEASE_TAG: ${RIAS_RELEASE_TAG} from vetted-versions-repo/${GENCTL_VETTED_VERSIONS}

function deploy_bundle() {
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "docker run --rm \
        --name=${IBMCLOUD_IKS_CLUSTER_NAME}-$(date -u +%s) \
        --network host \
        --env-file ${RIAS_CLUSTER_DIR}/.ngsec/vault.env \
        --volume ${RIAS_CLUSTER_DIR}/.ngsec:/tmp/.ngsec:ro \
        --volume ${RIAS_CLUSTER_DIR}/kubeconfig.yaml:/root/.kube/config:ro \
        --env KUBECONFIG=/root/.kube/config \
        --volume ${RIAS_CLUSTER_DIR}/${1}-globals.json:/root/globals.json:ro \
        --env GLOBALS_PATH=/root/globals.json \
        $2"
}

function post_deploy_readiness() {
    orig_opts=$-
    set +x  # just to make this much easier on the eyes
    local count
    local passready=false
    local readyrecheck=0
    echo
    echo "Begin pod readiness loop. Two consecutive/successful polls = ready"
    for count in {1..120}; do
        passready=false
        # Skip checking the ready status for kerberos pods per CLD-79428
        # Find non-kerberos pods which are not ready or any pods (including kerberos) which are not running
        # $2 = Pod name, $3 = Number of ready containers in a pod, $4 = Total number of containers in a pod, $5 = Pod status
        failing_pods=$(ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "KUBECONFIG=${RIAS_CLUSTER_DIR}/kubeconfig.yaml kubectl get pod -A --no-headers | grep -vi 'Evicted\|Completed'" | awk -F' *|/' '($3 != $4 && $2 !~ /kerberos/ || ($5 !="Running")' | awk -F' *|/' '($1 != "ibm-services-system")' | awk -F' *|/' '($1 != "ibm-system")')
        [[ -z "$failing_pods" ]] && passready=true || echo "$failing_pods"

        if [[ "${passready}" == true ]]; then
            let "readyrecheck++" || true  # || true so that set -e will not stop us
            if [[ $readyrecheck -gt 1 ]]; then
                # got passready twice in a row
                break
            fi
        else
            readyrecheck=0
        fi
        echo -e "\n=========================== $((120-$count)) ====================================\n"
        sleep 10
    done
    echo "--------Pods status after readiness check ---------"
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "KUBECONFIG=${RIAS_CLUSTER_DIR}/kubeconfig.yaml kubectl get pod -A "
    if [[ "${passready}" == false ]]; then
        echo "Rias failed readiness checks"
        set +e  # we should still continue if any of this debug info collection fails
        FAILED_PODS=$(ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "KUBECONFIG=${RIAS_CLUSTER_DIR}/kubeconfig.yaml kubectl get pod -A --no-headers | grep -vi 'Evicted\|Completed'" | awk -F' *|/' '($3 != $4 && $2 !~ /kerberos/ || ($5 !="Running")' | awk -F' *|/' '($1 != "ibm-services-system")' | awk -F' *|/' '($1 != "ibm-system")'  | awk '{ print $2 }')
        echo "failed pods: ${FAILED_PODS}"
        for pod in ${FAILED_PODS}; do
             pod_namespace=$(ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "KUBECONFIG=${RIAS_CLUSTER_DIR}/kubeconfig.yaml kubectl get po --all-namespaces | grep ${pod} "  | awk '{ print $1 }')
             echo "kubectl logs for pod: ${pod} (namespace ${pod_namespace})"
             ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "KUBECONFIG=${RIAS_CLUSTER_DIR}/kubeconfig.yaml kubectl -n ${pod_namespace} logs ${pod} --all-containers=true"
             echo "kubectl describe for pod: ${pod} (namespace ${pod_namespace})"
             ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "KUBECONFIG=${RIAS_CLUSTER_DIR}/kubeconfig.yaml kubectl -n ${pod_namespace} describe pod ${pod}"
        done
        post_deploy_razee_logs
        exit 1
    else
        echo "Readiness checks PASSED"
    fi
    set -${orig_opts}
}

function post_deploy_razee_logs() {
    orig_opts=$-
    set +x  # just to make this much easier on the eyes
    echo "=========rias remote resources list========="
    echo "kubectl -n rias get FeatureFlagSetLD/rias-ffs-ld -o json | jq -r '.data' "
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "KUBECONFIG=${RIAS_CLUSTER_DIR}/kubeconfig.yaml kubectl -n rias get FeatureFlagSetLD/rias-ffs-ld -o json | jq -r '.data' "
    set -${orig_opts}
}

function login_to_staging_artifactory() {
    # docker login to staging registry so that we can pull images
    set +x  # so we do not log the password
    echo "docker logging in to ${ARTIFACTORY_DOCKER_STAGING_URL}"
    echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_STAGING_URL} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
    set -x
}

case "$MZONE_NAME" in
mzone7215)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev05-etcd"
    ;;
mzone7286)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev06-etcd"
    ;;
mzone7287)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev07-etcd"
    ;;
mzone7288)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev08-etcd"
    ;;
mzone7301)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev24-etcd"
    ;;
mzone7302)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev25-etcd"
    ;;
*)
    echo "${MZONE_NAME} is not supported for rias deploys"
    exit 1
    ;;
esac
export LAUNCH_DARKLY_RULE_TAG=${IBMCLOUD_IKS_CLUSTER_NAME}
echo "LAUNCH_DARKLY_RULE_TAG=${LAUNCH_DARKLY_RULE_TAG}"

# Prepare an empty directory on the deploy server where we can put things
RIAS_CLUSTER_DIR=/home/${BASTION_USERNAME}/${IBMCLOUD_IKS_CLUSTER_NAME}
ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "rm -rf ${RIAS_CLUSTER_DIR}"
ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "mkdir -p ${RIAS_CLUSTER_DIR}"

# Copy globals json to deploy server
rsync -aq -e "ssh ${SSH_CONFIG_PARAMS}" $PATH_TO_RIAS_ETCD_RELEASE_REPO/component-input/env-globals/${IBMCLOUD_IKS_CLUSTER_NAME}.json ${DEPLOY_SERVER_TARGET}:${RIAS_CLUSTER_DIR}/rias-etcd-release-globals.json
rsync -aq -e "ssh ${SSH_CONFIG_PARAMS}" $PATH_TO_RIAS_GLOBALS_REPO/cicd/${IBMCLOUD_IKS_CLUSTER_NAME}.json ${DEPLOY_SERVER_TARGET}:${RIAS_CLUSTER_DIR}/rias-release-globals.json

# Support deploying both known-good and staging bundles
RIAS_ETCD_RELEASE_REG_URL=${ARTIFACTORY_DOCKER_PROD_URL}
RIAS_RELEASE_REG_URL=${ARTIFACTORY_DOCKER_PROD_URL}

#if component type is genctl check if it is a shared component with rias release
# if so override RIAS_ETCD_RELEASE_TAG from vetted version and use custom rias release bundle built for this component

if [[ ${RIAS_DEPLOY_COMPONENT_TYPE:-} == 'genctl' && ! -z ${WORKSPACE_REPO_NAME:-} && ${HOTFIX} == 'false' ]]; then
      # check if the genctl component is a shared rias component
      set +e
      python3 $PATH_TO_GENCTL_CI/scripts/exist_in_inventory_json.py ${WORKSPACE_REPO_NAME} $PATH_TO_RIAS_RELEASE_REPO/component-input/inventory.json
      result=$?
      echo $result
      set -e
      if [[ ${result} == 0 ]]; then
        echo "component ${WORKSPACE_REPO_NAME} is a shared with rias-release component."
        RIAS_RELEASE_REG_URL=${ARTIFACTORY_DOCKER_STAGING_URL}
        RIAS_RELEASE_TAG=${COMPONENT_HASH}
        login_to_staging_artifactory
      fi

      # check if the genctl component is a shared rias-etcd component
      set +e
      python3 $PATH_TO_GENCTL_CI/scripts/exist_in_inventory_json.py ${WORKSPACE_REPO_NAME} $PATH_TO_RIAS_ETCD_RELEASE_REPO/component-input/inventory.json
      result=$?
      echo $result
      set -e
      if [[ ${result} == 0 ]]; then
        echo "component ${WORKSPACE_REPO_NAME} is a shared with rias-etcd-release component."
        RIAS_ETCD_RELEASE_REG_URL=${ARTIFACTORY_DOCKER_STAGING_URL}
        RIAS_ETCD_RELEASE_TAG=${COMPONENT_HASH}
        login_to_staging_artifactory
      fi
fi

#if rias component always override RIAS_RELEASE_TAG / RIAS_ETCD_RELEASE_TAG from vetted version and use custom rias release bundle built for this component
if [[ ${RIAS_DEPLOY_COMPONENT_TYPE:-} == 'rias' ]]; then
    # setup to pull a new image we are testing from staging
    if [ ${PACKAGE} == 'rias-etcd-release' ]; then
        RIAS_ETCD_RELEASE_REG_URL=${ARTIFACTORY_DOCKER_STAGING_URL}
        RIAS_ETCD_RELEASE_TAG=${COMPONENT_HASH}
    elif [ ${PACKAGE} == 'rias-release' ]; then
        RIAS_RELEASE_REG_URL=${ARTIFACTORY_DOCKER_STAGING_URL}
        RIAS_RELEASE_TAG=${COMPONENT_HASH}
    else
        echo "${PACKAGE} is not a recognized RIAS release bundle"
        exit 1
    fi
    login_to_staging_artifactory
fi

# docker login to prod registry so that we can pull images
set +x  # so we do not log the password
echo "docker logging in to ${ARTIFACTORY_DOCKER_PROD_URL}"
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_PROD_URL} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
set -x

# Pull and copy rias-etcd-release image to deploy server
RIAS_ETCD_RELEASE_IMAGE=${RIAS_ETCD_RELEASE_REG_URL}/rias/rias-etcd-release:${RIAS_ETCD_RELEASE_TAG}
docker pull ${RIAS_ETCD_RELEASE_IMAGE}
docker save ${RIAS_ETCD_RELEASE_IMAGE} > rias-etcd-release-${RIAS_ETCD_RELEASE_TAG}.img
rsync -aq -e "ssh ${SSH_CONFIG_PARAMS}" rias-etcd-release-${RIAS_ETCD_RELEASE_TAG}.img ${DEPLOY_SERVER_TARGET}:${RIAS_CLUSTER_DIR}/
ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "cat ${RIAS_CLUSTER_DIR}/rias-etcd-release-${RIAS_ETCD_RELEASE_TAG}.img | docker load"

# Pull and copy rias-release image to deploy server
RIAS_RELEASE_IMAGE=${RIAS_RELEASE_REG_URL}/rias/rias-release:${RIAS_RELEASE_TAG}
docker pull ${RIAS_RELEASE_IMAGE}
docker save ${RIAS_RELEASE_IMAGE} > rias-release-${RIAS_RELEASE_TAG}.img
rsync -aq -e "ssh ${SSH_CONFIG_PARAMS}" rias-release-${RIAS_RELEASE_TAG}.img ${DEPLOY_SERVER_TARGET}:${RIAS_CLUSTER_DIR}/
ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "cat ${RIAS_CLUSTER_DIR}/rias-release-${RIAS_RELEASE_TAG}.img | docker load"

# Source the ibmcloud_utils.sh
source $PATH_TO_GENCTL_CI/scripts/ibmcloud_utils.sh

set +x
# Login to ibmcloud using function defined in ibmcloud_utils.sh
ibmcloud_login "${IBMCLOUD_KEY}"
get_iks_cluster_config ${IBMCLOUD_IKS_CLUSTER_NAME}
set -x

kubectl config view --flatten > kubeconfig.yaml
chmod 600 kubeconfig.yaml

# Copy kube config to deploy server
rsync -aq -e "ssh ${SSH_CONFIG_PARAMS}" kubeconfig.yaml ${DEPLOY_SERVER_TARGET}:${RIAS_CLUSTER_DIR}/

# Generate a time-limited vault token for RIAS deploy
rm -rf .ngsec
mkdir -p .ngsec/tmpsec
ssh -f -o ExitOnForwardFailure=yes ${SSH_CONFIG_PARAMS} -L 8200:${VAULT_IP}:8200 ${DEPLOY_SERVER_TARGET} sleep 10
set +x  # so we do not log the vault key
echo "${VAULT_KEY}" | curl -H "X-Vault-Namespace: ${VAULT_NAMESPACE}" --cacert ${VAULT_CACERT} --data @- --url https://127.0.0.1:8200/v1/auth/approle/login -s | jq -r .auth.client_token > .ngsec/tmpsec/token; chmod 600 .ngsec/tmpsec/token
set -x
if [ -s .ngsec/tmpsec/token ]; then
    echo "Got vault token"
else
    echo "Unable to get vault token"
    exit 1
fi

# Add vault CA certificate to the .ngsec directory
cp ${VAULT_CACERT} .ngsec/vault-intermediary_ca.crt

# Setup vault env file
cat << EOF > .ngsec/vault.env
VAULT_TOKEN_PATH=/tmp/.ngsec/tmpsec/token
VAULT_CACERT=/tmp/.ngsec/vault-intermediary_ca.crt
VAULT_ADDR=https://${VAULT_IP}:8200
VAULT_NAMESPACE=${VAULT_NAMESPACE}
VAULT_PREFIX=${VAULT_PREFIX}
EOF

##################
# Checks that there is an IP Address instead of "pending" for nginx's load balancer (due to a bug in Kubernetes versions prior to 1.16)
mzone_matched=true # Variable used to protect the script from encountering an error
set +e
kubectl get svc -n riaascore | grep -i nginx
set -e
#################

# Copy vault token, CA cert, and env file to deploy server
rsync -aq -e "ssh ${SSH_CONFIG_PARAMS}" ./.ngsec/ ${DEPLOY_SERVER_TARGET}:${RIAS_CLUSTER_DIR}/.ngsec

# Cleanup previous deploys from IKS cluster
rsync -aq -e "ssh ${SSH_CONFIG_PARAMS}" $PATH_TO_GENCTL_CI/scripts/wipe-rias.sh ${DEPLOY_SERVER_TARGET}:${RIAS_CLUSTER_DIR}/
ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "KUBECONFIG=${RIAS_CLUSTER_DIR}/kubeconfig.yaml ${RIAS_CLUSTER_DIR}/wipe-rias.sh"

# Deploy rias-etcd-release
deploy_bundle rias-etcd-release ${RIAS_ETCD_RELEASE_IMAGE}
post_deploy_readiness

# Deploy rias-release
deploy_bundle rias-release ${RIAS_RELEASE_IMAGE}
# run readiness mtp check if razee is configured to be deploy on rias-release
if [[ $(jq -c '[ .[] | select( .manifest_template_path | contains("rias-inception.yaml")) ]' $PATH_TO_RIAS_RELEASE_REPO/component-input/components.json ) != '[]' ]]; then
    echo "rias-inception is defined on the rias-release components, running MTP readiness checks..."
    python3 $PATH_TO_GENCTL_CI/scripts/razee_readiness/razee_mtp_readiness.py rias
fi

post_deploy_readiness
post_deploy_razee_logs

# remove the kube config (contains secrets)
ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "rm ${RIAS_CLUSTER_DIR}/kubeconfig.yaml"

# remove the vault token
ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "rm -rf ${RIAS_CLUSTER_DIR}/.ngsec"
