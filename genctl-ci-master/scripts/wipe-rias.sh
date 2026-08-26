#!/usr/bin/env bash

# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2019, 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -u

NOTFORREALZIESK='' # add 'echo' to dry run

MATCH_INCL='coredns|riaa?s|genctl|helm|jaeger|sysdig|etcd|logdna'
MATCH_EXCL_NS='^(ibm.*|kube.*|default.*|tigera-operator|calico-*)'
MATCH_EXCL='^(system:|ibm)'

# Check GNU grep is in the environment
grepversion=$(grep --version)
if [[ "$grepversion" != *"GNU"* ]]; then
    echo "$0 requires GNU grep.  'grep --version' responds: $grepversion"
    exit 1
fi

trap ctrl_c SIGINT

function ctrl_c() {
    echo "Trapped SIGINT ... exiting"
    exit 1
}

function failsafe_cleanup() {

    set +e

    kinds=$(kubectl api-resources --verbs=list --namespaced -o name | paste -s -d, -)
    echo "remaining resources:"
    echo "---------------------"
    for ns in $(kubectl get ns --no-headers | awk '$1!~/^(kube*|ibm*|tigera-operator|calico-*)/ {print $1}'); do
        kubectl get ${kinds} --ignore-not-found -n $ns --no-headers -o custom-columns=Kind:.kind,Namespace:.metadata.namespace,Name:.metadata.name,Finalizers:.metadata.finalizers
    done

    rem_rias_not_namespaced clusterroles
    rem_rias_not_namespaced clusterrolebindings

    # ordering may affect results
    # e.g. remove a daemonset before the pods it would otherwise recreate
    rem_rias_namespaced MustacheTemplate
    rem_rias_namespaced deployment
    rem_rias_namespaced daemonset
    rem_rias_namespaced statefulset
    rem_rias_namespaced replicaset
    rem_rias_namespaced pod
    rem_rias_namespaced service
    rem_rias_namespaced job
    rem_rias_namespaced cronjob
    rem_rias_namespaced secret
    rem_rias_namespaced serviceaccount
    rem_rias_namespaced pvc

    rem_if_exists default daemonset logdna-agent
    rem_if_exists default secret logdna-agent
    rem_if_exists default secret regcred

    # Add an explicit removal of the rias FeatureFlagSetLD prior to the namespace being deleted.
    rem_if_exists rias ffsld rias-ffs-ld

    # at this point, it should just be the namespace objects themselves, so delete them
    kubectl get ns | awk 'NR>1 && $1!~/^(kube*|default|ibm*|tigera-operator|calico-*|razee)/ {print $1}' | xargs -r -- ${NOTFORREALZIESK} kubectl delete ns --wait=false

    kubectl get crds --no-headers | awk '$1~/(deploy.razee.io)/ {print $1}' | xargs -r -- ${NOTFORREALZIESK} kubectl delete crds --wait=false
    ${NOTFORREALZIESK} kubectl delete ns razee --wait=false
}

function rem_rias_not_namespaced() {
    ##
    # remove rias specific non-namespaced resources by kind (e.g. ClusterRole)
    # 1.) get non-namespaced resources of specified kind
    # 2.) only the 1st column in the output (the name)
    # 3.) exclude output that matches MATCH_EXCL
    # 4.) include resources that match MATCH_INCL
    # 5.) for each line in the output, delete the resource
    ##

    local kind=$1; shift
    echo "deleting non-namespaced ${kind}"
    kubectl get "${kind}" --no-headers | awk '{print $1}' | grep -vE "${MATCH_EXCL}" | grep -E "${MATCH_INCL}" | xargs -r -- ${NOTFORREALZIESK} kubectl delete "${kind}" --wait=false
}

function rem_rias_namespaced() {
    ##
    # remove rias specific namespaced resources by kind
    # 1.) get resources of specified kind in all namespaces
    # 2.) only the 1st/2nd columns in the output (namespace and name)
    # 3.) exclude output that matches MATCH_EXCL_NS
    # 4.) include resources that match MATCH_INCL
    # 5.) for each line in the output, delete the resource
    ##

    local kind=$1; shift
    echo "deleting namespaced ${kind}"
    kubectl get "${kind}" -A --no-headers | awk '{print $1" "$2}' | grep -vE "${MATCH_EXCL_NS}" | grep -E "${MATCH_INCL}" | xargs -P10 -n2 -r -- bash -c ${NOTFORREALZIESK}' kubectl delete '"${kind}"' -n $0 $1 --wait=false'
}

function rem_if_exists() {
    ##
    # remove resources by namespace/type/resource-name
    # 1.) get all $type resources in the $ns namespace
    # 2.) only the 1st column in the output
    # 3.) include resources (matching type/namespace) that matches $name
    # 4.) for each line in the output, delete the resource
    ##

    local ns=$1; shift
    local kind=$1; shift
    local regex=$1; shift
    echo "deleting ${kind} in ${ns} matching ${regex}"
    kubectl get "${kind}" -n "${ns}" --ignore-not-found --no-headers | awk '{print $1}' | grep -E "${regex}" | xargs -r -- ${NOTFORREALZIESK} kubectl delete "${kind}" -n "${ns}" --wait=false
}


# delete etcd.database.coreos.com CRDs to prevent stuck backup-operator-periodic finalizers on EtcdBackups
echo "Deleting EtcdBackups..."
kubectl get EtcdBackup -A --no-headers | awk '{print $1" "$2}' | grep -vE "${MATCH_EXCL_NS}" | grep -E "${MATCH_INCL}" | xargs -P10 -n2 -r -- bash -c ${NOTFORREALZIESK}' kubectl delete EtcdBackup -n $0 $1 --timeout=120s'

# delete non-IKS namespaces, except razee which we will cleanup last so the razee controllers can remove finalizers as things are deleted
echo "Deleting rias namespaces..."
kubectl get ns --no-headers | awk '$1!~/^(kube*|ibm*|default|tigera-operator|calico-*|razee)/ {print $1}' | xargs -r -- ${NOTFORREALZIESK} kubectl delete ns --timeout=120s

stuck_ns=$(kubectl get ns --no-headers | awk '$1!~/^(kube*|ibm*|default|tigera-operator|calico-*|razee)/ {print $1}')
if [[ "" != "${stuck_ns}" ]]; then
    kinds=$(kubectl api-resources --verbs=list --namespaced -o name | paste -s -d, -)
    for ns in ${stuck_ns}; do
        kubectl get ${kinds} --ignore-not-found -n $ns --no-headers -o custom-columns=Namespace:.metadata.namespace,Kind:.kind,Name:.metadata.name,Finalizers:.metadata.finalizers | while read s; do
            read ns kind name finalizers <<< ${s}
            if [[ "${finalizers}" != "<none>" ]]; then
                echo "Removing ${finalizers} finalizers from ${kind} ${name} in ${ns}"
                ${NOTFORREALZIESK} kubectl patch -n $ns $kind $name -p '{"metadata":{"finalizers":null}}' --type=merge
            fi
        done
    done
fi

# cleanup the default namespace (do not delete the namespace itself)
echo "Cleaning default namespace..."
rem_if_exists default mtp logdna
rem_if_exists default rrs3 logdna
rem_if_exists default rr logdna
rem_if_exists default daemonset logdna
rem_if_exists default cm logdna
rem_if_exists default serviceaccount logdna
rem_if_exists default networkpolicy logdna
rem_if_exists default secret activity-tracker
rem_if_exists default secret logdna
rem_if_exists default secret regcred

# delete rias CRDs
echo "Deleting rias CRDs..."
kubectl get crds --no-headers | awk '$1~/(rias.ibm.com|etcd.database.coreos.com)/ {print $1}' | xargs -r -- ${NOTFORREALZIESK} kubectl delete crds --wait=false

# cleanup cluster-wide resources
echo "Deleting cluster-wide resources..."
rem_rias_not_namespaced clusterroles
rem_rias_not_namespaced clusterrolebindings
# TODO: add others, e.g. PodSecurityPolicy

# delete razee CRDs
echo "Deleting razee CRDs..."
kubectl get crds --no-headers | awk '$1~/(deploy.razee.io)/ {print $1}' | xargs -r -- ${NOTFORREALZIESK} kubectl delete crds --wait=false

# delete razee namespace
echo "Deleting razee namespace..."
${NOTFORREALZIESK} kubectl delete ns razee --timeout=120s

# confirm that deleted namespaces are gone
stuck_ns=$(kubectl get ns --no-headers | awk '$1!~/^(kube*|ibm*|default|tigera-operator|calico-*)/ {print $1}')
if [[ "" != "${stuck_ns}" ]]; then
    echo "ERROR: failed to cleanup:"
    kinds=$(kubectl api-resources --verbs=list --namespaced -o name | paste -s -d, -)
    kubectl get ${kinds} --ignore-not-found -n $ns --no-headers -o custom-columns=Namespace:.metadata.namespace,Kind:.kind,Name:.metadata.name,Finalizers:.metadata.finalizers
    echo

    echo "Running failsafe cleanup..."
    failsafe_cleanup
fi

# delete any failed pods, e.g. evicted, so they can respawn if needed
echo "Deleting failed pods..."
${NOTFORREALZIESK} kubectl delete po -A --field-selector=status.phase==Failed --wait=false
