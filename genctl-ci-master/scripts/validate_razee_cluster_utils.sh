#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

function validate_razee_clusters() {
    # Validates razee cluster (Given a list of clusters)

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set

    # Expected parameters:

    # Shared
    # $1 --> The cluster list (Comma separated, for example: rias-ng-us-south-dal12-dev91,mzone7196)
    # $2 --> Path to genctl-ci-repo (Without / as the end )

    # Rias
    # $3 --> The IBM CLOUD KEY

    # Genctl
    # $4 --> Bastion Username
    # $5 --> Bastion key
    # $6 --> Bastion ECDSA key
    # $7 --> Bastion RSA key
    # $8 --> Dal vault key
    # $9 --> Path to platform inventory repo
    # $10 --> Artifactory URL
    # $11 --> Artifactory username
    # $12 --> Artifactory password
    # $13 --> Img to run path
    # $14 --> Img to run tag

    # Put some friendly names
    CLUSTERS_LIST=$1
    PATH_TO_GENCTL_CI=$2
    IBM_CLOUD_KEY=$3
    B_U=$4;BASTION_KEY=$5;BASTION_KEY_ECDSA=$6;BASTION_KEY_RSA=$7
    DAL_VAULT_KEY=$8
    PATH_TO_PI=$9
    ART_URL=${10};ART_USER=${11};ART_PASS=${12}
    IMG_TO_RUN_PATH=${13};IMG_TO_RUN_TAG=${14}

    # Set a variable that reflects if the scripts that we need to source for working with genctl were already sourced
    # In other words, if we already did a run in a genctl cluster
    export sourced_genctl_help_scripts="false"

    # Iterate
    for rule_tag in $(echo ${CLUSTERS_LIST} | tr "," "\n")
    do
        # First check if there is rule tag at all
        if [[ -z "${rule_tag}" ]]; then
            echo The rule tag does not exist or empty. Continue ...
            continue
        fi

        set +x
        validate_razee_cluster "${rule_tag}" ${PATH_TO_GENCTL_CI} \
        "${IBMCLOUD_KEY}" \
        ${B_U} "${BASTION_KEY}" "${BASTION_KEY_ECDSA}" "${BASTION_KEY_RSA}" \
        "${DAL_VAULT_KEY}" ${PATH_TO_PI} \
        ${ART_URL} ${ART_USER} ${ART_PASS}      \
        ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
        set -x
    done
}

function validate_razee_cluster(){
    # Validates razee cluster (Including readiness)

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set

    # Expected parameters:

    # Shared
    # $1 --> The cluster list (Comma separated, for example: rias-ng-us-south-dal12-dev91,mzone7196)
    # $2 --> Path to genctl-ci-repo (Without / as the end )

    # Rias
    # $3 --> The IBM CLOUD KEY

    # Genctl
    # $4 --> Bastion Username
    # $5 --> Bastion key
    # $6 --> Bastion ECDSA key
    # $7 --> Bastion RSA key
    # $8 --> Dal vault key
    # $9 --> Path to platform inventory repo
    # $10 --> Artifactory URL
    # $11 --> Artifactory username
    # $12 --> Artifactory password
    # $13 --> Img to run path
    # $14 --> Img to run tag

    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_GENCTL_CI=$2

    echo "Will validate razee cluster for ${MZONE_NAME}"

    # Then check if genctl or rias
    if [[ ${MZONE_NAME} == mzone* ]]; then

        if [[ "${USE_QZ2_WORKER}" == true ]]; then
            echo "Will be carried out in a subpipeline"
        else
            # Get additional genctl parameters
            B_U=$4;BASTION_KEY=$5;BASTION_KEY_ECDSA=$6;BASTION_KEY_RSA=$7
            DAL_VAULT_KEY=$8
            PATH_TO_PI=$9
            ART_URL=${10};ART_USER=${11};ART_PASS=${12}
            IMG_TO_RUN_PATH=${13};IMG_TO_RUN_TAG=${14}

            echo "${MZONE_NAME} is a genctl cluster"
            # If they haven't been sourced yet, source some scripts needed for working with deployer

            if [ ${sourced_genctl_help_scripts} == "false" ]
            then
                echo "Will source some scripts that we need for working with genctl cluster"
                . ${PATH_TO_GENCTL_CI}/scripts/ssh_utils.sh
                . ${PATH_TO_GENCTL_CI}/scripts/deployer_utils.sh
                export sourced_genctl_help_scripts="true"

                # Setup to work with the deployer
                #If we are in OnePipeline, we use a slightly different setup_ssh_to_deployer function that does not requires/uses bastion; 
                #however the keys are same for bastion and deployer, and therefore we use them indistinctively
                set +x
                if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then                
                    setup_ssh_to_deployer_one_pipeline ${MZONE_NAME} ${B_U} "${BASTION_KEY}" "${BASTION_KEY_ECDSA}" "${BASTION_KEY_RSA}"
                else
                    setup_ssh_to_deployer ${MZONE_NAME} ${B_U} "${BASTION_KEY}" "${BASTION_KEY_ECDSA}" "${BASTION_KEY_RSA}"
                fi            
                set -x
            fi
            
            #This script will establish a first-time connection and will also attempt to reconnect to the deployer if the initial connection fails due to a remote connection issue.

            
            set +x
            validate_razee_cluster_genctl ${MZONE_NAME} ${PATH_TO_GENCTL_CI} ${B_U} \
            "${DAL_VAULT_KEY}" ${PATH_TO_PI}    \
            ${ART_URL} ${ART_USER} ${ART_PASS}  \
            ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}

            echo "Will validate pod readiness for genctl cluster ${MZONE_NAME}"
            set +x # so we do not log the key
            validate_pods_cluster_readiness_genctl ${MZONE_NAME} ${PATH_TO_GENCTL_CI} ${B_U} \
            "${DAL_VAULT_KEY}" ${PATH_TO_PI} \
            ${ART_URL} ${ART_USER} ${ART_PASS}      \
            ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
            set -x
        fi

    elif [[ ${MZONE_NAME} == rias* ]]; then
        # Get additional rias parameters
        IBM_CLOUD_KEY=$3

        echo "${MZONE_NAME} is a rias cluster"

        set +x # so we do not log the key
        validate_razee_cluster_rias ${MZONE_NAME} "${IBM_CLOUD_KEY}" ${PATH_TO_GENCTL_CI}

        echo "Will validate pod readiness for rias cluster ${MZONE_NAME}"
        set +x # so we do not log the key
        validate_pods_cluster_readiness_rias ${MZONE_NAME} "${IBMCLOUD_KEY}" ${PATH_TO_GENCTL_CI}
        set -x
    else
        echo "${MZONE_NAME} does not match neither genctl nor rias, Exiting..."
        exit 1
    fi
}

function validate_razee_cluster_genctl() {
    # Validates genctl

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set

    # Expected parameters:

    # $1 --> The Mzone name
    # $2 --> Path to genctl-ci-repo (Without / as the end )
    # $3 --> Bastion Username (Used for creating a folder in the deployer)
    # $4 --> Dal vault key
    # $5 --> Path to platform inventory repo
    # $6 --> Artifactory URL
    # $7 --> Artifactory username
    # $8 --> Artifactory password
    # $9 --> Img to run path
    # $10 --> Img to run tag

    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_GENCTL_CI=$2
    B_U=$3
    DAL_VAULT_KEY=$4
    PATH_TO_PI=$5
    ART_URL=$6;ART_USER=$7;ART_PASS=$8
    IMG_TO_RUN_PATH=$9;IMG_TO_RUN_TAG=${10}

    # Create the working directory in the deployer
    create_workdir_in_deployer ${MZONE_NAME} ${B_U}

    # Setup that allows us to run code in the deployer inside a docker container
    set +x
    setup_deployer_for_ci_work ${PATH_TO_GENCTL_CI} ${ART_URL} ${ART_USER} ${ART_PASS} ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
    set -x

    # Setup that allows us to run kubectl commands against genctl cluster
    set +x
    setup_deployer_for_work_against_mzone ${MZONE_NAME} ${PATH_TO_GENCTL_CI} ${PATH_TO_PI} "${DAL_VAULT_KEY}"
    set -x

    # We need to extract these base names because in concourse the end paths are different
    # i.e genctl-ci-repo vs one-pipeline-config-repo
    PATH_ON_DEPLOYER_GENCTL_CI=$(basename "$PATH_TO_GENCTL_CI")

    export COMMAND_INSIDE_CONTAINER="
    set -e
    export KUBECONFIG=${MZONE_DIR}/${MZONE_NAME}.conf
    . ${MZONE_DIR}/repos/${PATH_ON_DEPLOYER_GENCTL_CI}/scripts/validate_razee_cluster_utils.sh
    check_readiness_and_lock_status ${MZONE_DIR}/repos/${PATH_ON_DEPLOYER_GENCTL_CI} genctl
    check_crds_genctl
    "

    source ${PATH_TO_GENCTL_CI}/scripts/reconnecting_to_deployer.sh

    set +x
    connect ${MZONE_NAME} ${IMG_TO_RUN} ${MZONE_DIR}
    set -x
}

function validate_razee_cluster_rias() {
    # Validates rias and rias-etcd

    # Expected parameters:

    # $1 --> The cluster to check
    # $2 --> The IBM CLOUD KEY
    # $3 --> Path to genctl-ci-repo

    # Put some friendly names
    CLUSTER_TO_CHECK=$1
    IBM_CLOUD_KEY=$2
    PATH_TO_GENCTL_CI=$3

    set +x
    # Login to ibmcloud_rias using function defined in ibmcloud_utils.sh
    ibmcloud_login "${IBM_CLOUD_KEY}"
    get_iks_cluster_config ${CLUSTER_TO_CHECK}
    set -x
    set -e
    # Check for 7183 pre-int rias-ng-us-south-dal-dev10-etcd
    if [[ ${CLUSTER_TO_CHECK} == "rias-ng-us-south-dal-dev10-etcd" ]]; then
        check_readiness_and_lock_status ${PATH_TO_GENCTL_CI} "rias-etcd"
        check_readiness_and_lock_status ${PATH_TO_GENCTL_CI} "rias"
    elif [[ ${CLUSTER_TO_CHECK} == *etcd ]]; then
        check_readiness_and_lock_status ${PATH_TO_GENCTL_CI} "rias-etcd"
    else
        check_readiness_and_lock_status ${PATH_TO_GENCTL_CI} "rias"
    fi

    check_crds
}

function validate_pods_cluster_readiness_genctl() {
    # Validates genctl

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set

    # Expected parametrias_post_deploy_readinessers:

    # $1 --> The Mzone name
    # $2 --> Path to genctl-ci-repo (Without / as the end )
    # $3 --> Bastion Username (Used for creating a folder in the deployer)
    # $4 --> Dal vault key
    # $5 --> Path to platform inventory repo
    # $6 --> Artifactory URL
    # $7 --> Artifactory username
    # $8 --> Artifactory password
    # $9 --> Img to run path
    # $10 --> Img to run tag

    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_GENCTL_CI=$2
    B_U=$3
    DAL_VAULT_KEY=$4
    PATH_TO_PI=$5
    ART_URL=$6;ART_USER=$7;ART_PASS=$8
    IMG_TO_RUN_PATH=$9;IMG_TO_RUN_TAG=${10}

    # Create the working directory in the deployer
    create_workdir_in_deployer ${MZONE_NAME} ${B_U}

    # Setup that allows us to run code in the deployer inside a docker container
    set +x
    setup_deployer_for_ci_work ${PATH_TO_GENCTL_CI} ${ART_URL} ${ART_USER} ${ART_PASS} ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
    set -x

    # Setup that allows us to run kubectl commands against genctl cluster
    set +x
    setup_deployer_for_work_against_mzone ${MZONE_NAME} ${PATH_TO_GENCTL_CI} ${PATH_TO_PI} "${DAL_VAULT_KEY}"
    set -x

    # We need to extract these base names because in concourse the end paths are different
    # i.e genctl-ci-repo vs one-pipeline-config-repo
    PATH_ON_DEPLOYER_GENCTL_CI=$(basename "$PATH_TO_GENCTL_CI")

    export COMMAND_INSIDE_CONTAINER="
    set -e
    export KUBECONFIG=${MZONE_DIR}/${MZONE_NAME}.conf
    . ${MZONE_DIR}/repos/${PATH_ON_DEPLOYER_GENCTL_CI}/scripts/validate_razee_cluster_utils.sh
    genctl_post_deploy_readiness
    "
    source ${PATH_TO_GENCTL_CI}/scripts/reconnecting_to_deployer.sh
    
    set +x
    connect ${MZONE_NAME} ${IMG_TO_RUN} ${MZONE_DIR}
    set -x
}

function validate_pods_cluster_readiness_goku() {
    # Validates genctl using goku

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set
    # work image has been copied to the deployer
    # Expected parameters:

    # $1 --> MDS directory path
    # $2 --> The component being deployed
    # $3 --> Path to genctl ci repo
    # $4 --> KUBRCONFIG file path
    # $5 --> Path to the mounted repo for the mds image
    # $6 --> DAL vault key
    # $7 --> Path to platform inventory
    # $8 --> Artifactory URL
    # $9 --> Artifactory user
    # $10--> Artifactory password

    MDS_DIR_PATH=$1
    COMPONENT=$2
    PATH_TO_GENCTL_CI=$3
    KUBECONFIG_PATH=$4
    MOUNT_DIR=$5
    DAL_VAULT_KEY=$6
    PATH_TO_PI=$7
    ART_URL=$8;ART_USER=$9;ART_PASS=${10}

    # Setup that allows us to run kubectl commands against genctl cluster
    set +x
    if [[ $COMPONENT == "genctl" ]]; then
        setup_deployer_for_work_against_mzone ${MZONE_NAME} ${PATH_TO_GENCTL_CI} ${PATH_TO_PI} "${DAL_VAULT_KEY}"
    fi
    set -x
    . ${MDS_DIR_PATH}/.env
    export COMMAND_INSIDE_CONTAINER="
    set -e
    export KUBECONFIG=${KUBECONFIG_PATH}
    goku readiness -r pods
    "
    source ${PATH_TO_GENCTL_CI}/scripts/reconnecting_to_deployer.sh
    IMG_TO_RUN=${MDS_IMAGE_PATH}:${MDS_IMAGE_VERSION}

    set +x
    connect ${MZONE_NAME} ${IMG_TO_RUN} ${MOUNT_DIR}
    set -x

}

function validate_pods_cluster_readiness_rias() {
    # Validates rias and rias-etcd

    # Expected parameters:

    # $1 --> The cluster to check
    # $2 --> The IBM CLOUD KEY
    # $3 --> Path to genctl-ci-repo

    # Put some friendly names
    CLUSTER_TO_CHECK=$1
    IBM_CLOUD_KEY=$2
    PATH_TO_GENCTL_CI=$3

    set +x
    # Login to ibmcloud using function defined in ibmcloud_utils.sh
    ibmcloud_login "${IBM_CLOUD_KEY}"
    get_iks_cluster_config ${CLUSTER_TO_CHECK}
    set -x

    rias_post_deploy_readiness
}


### SHARED FUNCTIONS ###
# With the proper setup, these functions can be run in both situations:

# 1. In Concourse (when working against rias) or in a container
# 2. In a container inside the deployer (When working against genctl)

function check_readiness_and_lock_status(){

    PATH_TO_GENCTL_CI=$1
    CLUSTER_TYPE=$2

    echo "running MTP readiness checks..."

    python3 -u ${PATH_TO_GENCTL_CI}/scripts/razee_readiness/razee_mtp_readiness.py ${CLUSTER_TYPE}

    #Check for razee lock status
    python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/razee_check_cluster/requirements.txt
    python3 -u ${PATH_TO_GENCTL_CI}/scripts/razee_check_cluster/check_lock_status.py


}
function check_crds(){
    # for rias-/rias-etcd
    LABELS=$(kubectl api-resources --verbs=list -o name | paste -s -d, - | xargs kubectl get --show-kind --field-selector=metadata.name!=rias-ffs-ld,metadata.name!=rias-etcd-ffs-ld --ignore-not-found -l deploy.razee.io/debug=true -A)
    # if there are no labels -> good to go
    if [[ -n $LABELS ]]
    then
        echo $LABELS
        echo "Validation failed: Kube kinds have debug labels 'deploy.razee.io/debug=true'"
        exit 1
    fi
}

function check_crds_genctl(){
    # for genctl, --field-selector can not be used to omit labels from certain resources as for two of the k8s resources, these selectors are not available.
    # Hence, the labels are being handled by processing the output.
    LABELS=$(kubectl api-resources --verbs=list -o name | paste -s -d, - | xargs kubectl get --show-kind --ignore-not-found -l deploy.razee.io/debug=true -A)
    OUTPUT=$(echo "${LABELS}" | awk '{for (i=1; i<=NF; i++) {printf "%s ", $i; if (i%3==0) printf "\n"}}')
    COUNT=0
    if [ -z "$OUTPUT" ]; then
        echo "Proceeding..."
    else
        while IFS= read -r line; do
            if [[ "$line" =~ "NAMESPACE NAME AGE" || "$line" =~ "genctl featureflagsetld.deploy.razee.io/genctl-ffs-ld" ]]; then   #ignore debug label on the ffsld
                continue
            fi
            COUNT=$(( COUNT + 1 ))
        done <<< "$OUTPUT"
        if [ $COUNT -ge 1 ]; then
            display_debug_labels "${LABELS}"
            exit 1
        else
            echo "Validation successful: Kube kinds do not have debug labels"
        fi
    fi
}

function display_debug_labels(){
    echo "Validation failed: Kube kinds have debug labels 'deploy.razee.io/debug=true'"
    LABELS=$1
    echo "$LABELS" | awk '
    {
        for (i = 1; i <= NF; i++) {
            if ($i == "NAMESPACE") {
                if (header != "" && header != "NAMESPACE NAME AGE" && content !~ /featureflagsetld.deploy.razee.io/) {
                    print header "\n" content "\n";
                }
                header = $i;
                content = "";
            } else if ($i == "AGE") {
                header = header " " temp " " $i;
                temp = "";
            } else {
                if (header ~ /AGE$/) {
                    content = (content == "" ? $i : content " " $i);
                } else {
                    temp = (temp == "" ? $i : temp " " $i);
                }
            }
        }
    }
    END { if (header != "" && header != "NAMESPACE NAME AGE" && content !~ /featureflagsetld.deploy.razee.io/) print header "\n" content; }'
}

genctl_post_deploy_readiness(){
    local count
    local passready=false
    local readyrecheck=0
    local READINESS_RETRIES=140
    local wait_to_steady=5
    local exit_code

    echo "Begin pod readiness loop."
    CLUSTER_CONTEXT=$(kubectl config current-context)
    echo CLUSTER_CONTEXT: $CLUSTER_CONTEXT

    if [[ -z "${CLUSTER_CONTEXT}" ]]; then
        echo "Failed to obtain cluster context for $1 Exiting ..."
        exit 1
    fi

    # Check if goku is installed
    if goku --help &>/dev/null; then
        echo goku deploy check
        goku readiness -r="pods" --logs
        exit_code=$?
        return $exit_code
    else
        set +e
        for ((count=1; count<READINESS_RETRIES; count++)); do
            passready=false
            not_ready_status=$(kubectl get pods --all-namespaces -o json \
                | jq -r '
                    .items[]
                        | select(
                            (.status.phase != "Succeeded")
                            and (.status.phase == "Failed" or ([ .status.conditions[] | select(.type == "Ready" and .status == "False") ] | length ) == 1)
                            and (.metadata.name | contains("kerberos-kdc-slave") | not)
                            and (.metadata.annotations."cicd/healthcheck" != "skip")
                        )
                        |   .metadata.namespace + "\t"
                        + .metadata.name + "\t"
                        + ([.status.containerStatuses[]? | select(.state == true)] | length | tostring) + "/" + ([.spec.containers[]] | length | tostring) + "\t"
                        + (if .status.reason? then .status.reason else .status.phase end) + "\t"
                        + ([.status.containerStatuses[]?.restartCount] | max | tostring) + "\t"
                        + ((((now)-(.metadata.creationTimestamp|fromdate))/60)|floor|tostring) + "m\t"
                        + (if .status.conditions? then .status.conditions[]? | select(.type == "Ready") .message else .status.message end)
                '
            )

            [[ $not_ready_status ]] && echo -e "NAMESPACE\tNAME\tREADY\tSTATUS\tRESTARTS\tAGE\tREASON\n${not_ready_status}" | column -ts $'\t' || passready=true

            # The kubectl get po is a point in time check.  Make sure it is providing stable pod status.
            if [[ $passready == true ]]; then
                let "readyrecheck++"
                if [[ $readyrecheck -gt $wait_to_steady ]]; then
                echo "break readiness because: readyrecheck: $readyrecheck"
                break
                fi
            else
                readyrecheck=0
            fi

            echo -e "\n=========================== $(($READINESS_RETRIES-$count)) ===================================\n"
            sleep 10
        done
        set -e

        echo "--------Pods status after readiness check ---------"
        kubectl get pod -A

        if [ "$passready" = false ]; then
            FAILED_PODS=$(echo -e "$not_ready_status" | awk '{ print $2 }')
            echo "failed pods: ${FAILED_PODS}"
            set +e
            for pod in ${FAILED_PODS}; do
                pod_namespace=$( echo -e "$not_ready_status" | grep ${pod}  | awk '{ print $1 }')
                echo "kubectl logs for pod: ${pod} in namespace ${pod_namespace}"
                kubectl -n ${pod_namespace} logs ${pod} --all-containers=true
                echo "kubectl describe for pod: ${pod}"
                kubectl -n ${pod_namespace} describe pod ${pod}
                echo  "========================================================================="
            done
            set -e
            echo "genctl failed readiness checks"
            return 1
        else
            echo "Readiness check PASSED"
        fi
        return 0
    fi
}

function rias_post_deploy_readiness() {
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
        failing_pods=$(kubectl get pod -A --no-headers | grep -vi 'Evicted\|Completed' | awk -F' *|/' '($3 != $4 && $2 !~ /kerberos/) || ($5 !="Running")' | awk -F' *|/' '($1 != "ibm-services-system")' | awk -F' *|/' '($1 != "ibm-system")')
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
    kubectl get pod -A
    if [[ "${passready}" == false ]]; then
        echo "Rias failed readiness checks"
        set +e  # we should still continue if any of this debug info collection fails
        FAILED_PODS=$(kubectl get pod -A --no-headers | grep -vi 'Evicted\|Completed' | awk -F' *|/' '($3 != $4 && $2 !~ /kerberos/) || ($5 !="Running")' | awk -F' *|/' '($1 != "ibm-services-system")' | awk -F' *|/' '($1 != "ibm-system")' | awk '{ print $2 }')
        echo "failed pods: ${FAILED_PODS}"
        for pod in ${FAILED_PODS}; do
             pod_namespace=$(kubectl get po --all-namespaces | grep ${pod}   | awk '{ print $1 }')
             echo "kubectl logs for pod: ${pod} (namespace ${pod_namespace})"
             kubectl -n ${pod_namespace} logs ${pod} --all-containers=true
             echo "kubectl describe for pod: ${pod} (namespace ${pod_namespace})"
             kubectl -n ${pod_namespace} describe pod ${pod}
        done
        post_deploy_razee_logs
        exit 1
    else
        echo "Readiness checks PASSED"
    fi
    set -x
}

function post_deploy_razee_logs() {
    set +x  # just to make this much easier on the eyes
    echo "=========rias remote resources list========="
    echo "kubectl -n rias get FeatureFlagSetLD/rias-ffs-ld -o json | jq -r '.data' "
    kubectl -n rias get FeatureFlagSetLD/rias-ffs-ld -o json | jq -r '.data'
    set -x
}
