#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

function scale_ffsetld() {
    # $1 --> FF set LD pod replicas
    FF_SETLD_REPLICAS=$1

    set +x  # just to make this much easier on the eyes
    echo "=========scaling the ffsld controller========="
    echo "kubectl scale deploy -n razee featureflagsetld-controller --replicas=${FF_SETLD_REPLICAS}"
    kubectl scale deploy -n razee featureflagsetld-controller --replicas=${FF_SETLD_REPLICAS}
    sleep 15
    kubectl get pods -n razee
    set -x
}

function scale_ffsetld_razee_cluster_rias() {
    # scale ffsetld in rias

    # Expected parameters:

    # $1 --> The cluster to check
    # $2 --> The IBM CLOUD KEY
    # $3 --> Path to genctl-ci-repo
    # $4 --> FF set LD pod replicas

    # Put some friendly names
    CLUSTER_TO_CHECK=$1
    IBM_CLOUD_KEY=$2
    PATH_TO_GENCTL_CI=$3
    FF_SETLD_REPLICAS=$4

    set +x
    # Login to ibmcloud using function defined in ibmcloud_utils.sh
    ibmcloud_login "${IBM_CLOUD_KEY}"
    get_iks_cluster_config ${CLUSTER_TO_CHECK}
    set -x

    scale_ffsetld ${FF_SETLD_REPLICAS}
}

function scale_ffsetld_razee_cluster_genctl() {
    # scale ffsetld in genctl
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
    # $11 --> FF set LD pod replicas


    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_GENCTL_CI=$2
    B_U=$3
    DAL_VAULT_KEY=$4
    PATH_TO_PI=$5
    ART_URL=$6;ART_USER=$7;ART_PASS=$8
    IMG_TO_RUN_PATH=$9;IMG_TO_RUN_TAG=${10}
    FF_SETLD_REPLICAS=${11}

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

    COMMAND_INSIDE_CONTAINER="
    set -e
    export KUBECONFIG=${MZONE_DIR}/${MZONE_NAME}.conf
    . ${MZONE_DIR}/repos/${PATH_ON_DEPLOYER_GENCTL_CI}/scripts/scale_ffsetld_razee_cluster.sh
    scale_ffsetld ${FF_SETLD_REPLICAS}
    "

    set +x
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "
    docker run --rm --name=scale_ffsetld_razee_cluster_${MZONE_NAME}_\$(date -u +%s) --network host -v ${MZONE_DIR}:${MZONE_DIR} ${IMG_TO_RUN} /bin/bash -c \" ${COMMAND_INSIDE_CONTAINER}  \"
    "
    set -x
}

function scale_ffsetld_razee_cluster(){
    # Validates razee cluster (Including readiness)
    # Expected parameters:

    # Shared
    # $1 --> The cluster list (Comma separated, for example: rias-ng-us-south-dal12-dev91,mzone7196)
    # $2 --> Path to genctl-ci-repo (Without / as the end )
    # $3 --> Number of FF set LD pod replicas

    # Rias
    # $4 --> The IBM CLOUD KEY

    # Genctl
    # $5 --> Bastion Username
    # $6 --> Bastion key
    # $7 --> Bastion ECDSA key
    # $8 --> Bastion RSA key
    # $7 --> Dal vault key
    # $8 --> Path to platform inventory repo
    # $9 --> Artifactory URL
    # $10 --> Artifactory username
    # $11 --> Artifactory password
    # $12 --> Img to run path
    # $13 --> Img to run tag

    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_GENCTL_CI=$2
    FF_SETLD_REPLICAS=$3

    echo "Will scale the ffsld controller for ${MZONE_NAME}"

    # Then check if genctl or rias
    if [[ ${MZONE_NAME} == mzone* ]]; then
        # Get additional genctl parameters
        B_U=$5;BASTION_KEY=$6;BASTION_KEY_ECDSA=$7;BASTION_KEY_RSA=$8
        DAL_VAULT_KEY=$9
        PATH_TO_PI=${10}
        ART_URL=${11};ART_USER=${12};ART_PASS=${13}
        IMG_TO_RUN_PATH=${14};IMG_TO_RUN_TAG=${15}

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

        set +x
        scale_ffsetld_razee_cluster_genctl ${MZONE_NAME} ${PATH_TO_GENCTL_CI} ${B_U} \
        "${DAL_VAULT_KEY}" ${PATH_TO_PI}    \
        ${ART_URL} ${ART_USER} ${ART_PASS}  \
        ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG} ${FF_SETLD_REPLICAS}

        set -x

    elif [[ ${MZONE_NAME} == rias* ]]; then
        # Get additional rias parameters
        IBM_CLOUD_KEY=$4

        echo "${MZONE_NAME} is a rias cluster"

        set +x # so we do not log the key
        scale_ffsetld_razee_cluster_rias ${MZONE_NAME} "${IBM_CLOUD_KEY}" ${PATH_TO_GENCTL_CI} ${FF_SETLD_REPLICAS}

        set -x
    else
        echo "${MZONE_NAME} does not match neither genctl nor rias, Exiting..."
        exit 1
    fi
}

function scale_ffsetld_razee_cluster_promotion(){
    # Scale ffsld controller for promotion pipeline (supports QZ2 workers)
    # Expected parameters:

    # Shared
    # $1 --> The cluster list (Comma separated, for example: rias-ng-us-south-dal12-dev91,mzone7196)
    # $2 --> Path to genctl-ci-repo (Without / as the end )
    # $3 --> Number of FF set LD pod replicas

    # Rias
    # $4 --> The IBM CLOUD KEY

    # Genctl
    # $5 --> Bastion Username
    # $6 --> Bastion key
    # $7 --> Bastion ECDSA key
    # $8 --> Bastion RSA key
    # $7 --> Dal vault key
    # $8 --> Path to platform inventory repo
    # $9 --> Artifactory URL
    # $10 --> Artifactory username
    # $11 --> Artifactory password
    # $12 --> Img to run path
    # $13 --> Img to run tag

    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_GENCTL_CI=$2
    FF_SETLD_REPLICAS=$3

    echo "Will scale the ffsld controller for ${MZONE_NAME}"

    # Then check if genctl or rias
    if [[ ${MZONE_NAME} == mzone* ]]; then
        if [[ "${USE_QZ2_WORKER}" == true ]]; then
            echo "found genctl component, will proceed with the validations through a subpipeline"

            REGIONDIGIT=${MZONE_NAME#*[[:digit:]]}  # Remove everything up to and including first digit
            REGIONDIGIT=${REGIONDIGIT:0:1}          # Take only the first character (2nd digit)

            echo "Extracted region digit: ${REGIONDIGIT} from mzone: ${MZONE_NAME}"

            export WORKER_ID="qz2-tekton-worker-trigger-dal1${REGIONDIGIT}"

            echo "Selected worker: ${WORKER_ID}"

            #temp fix until the issue is resolved
            export WORKSPACE=/workspace/app

            # Set environment variables required by the subpipeline
            set_env qz2-mzone-name "${MZONE_NAME}"
            set_env qz2-worker-id "${WORKER_ID}"
            set_env launch-darkly-feature-flag "${LAUNCH_DARKLY_FEATURE_FLAG:-}"

            # Trigger qz2-cluster-validations subpipeline
            ${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_v11_brt.sh "qz2-cluster-validations" ${WORKER_ID} "false" "onepipeline/pipelines/cd/templatized/promotion/pr_master/.pipeline-config.yaml" "${MZONE_NAME}" "${LAUNCH_DARKLY_FEATURE_FLAG}"

        else
            echo "Use older process for the validations"
            # Get additional genctl parameters
            B_U=$5;BASTION_KEY=$6;BASTION_KEY_ECDSA=$7;BASTION_KEY_RSA=$8
            DAL_VAULT_KEY=$9
            PATH_TO_PI=${10}
            ART_URL=${11};ART_USER=${12};ART_PASS=${13}
            IMG_TO_RUN_PATH=${14};IMG_TO_RUN_TAG=${15}

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

            set +x
            scale_ffsetld_razee_cluster_genctl ${MZONE_NAME} ${PATH_TO_GENCTL_CI} ${B_U} \
            "${DAL_VAULT_KEY}" ${PATH_TO_PI}    \
            ${ART_URL} ${ART_USER} ${ART_PASS}  \
            ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG} ${FF_SETLD_REPLICAS}

            set -x
        fi

    elif [[ ${MZONE_NAME} == rias* ]]; then
        # Get additional rias parameters
        IBM_CLOUD_KEY=$4

        echo "${MZONE_NAME} is a rias cluster"

        set +x # so we do not log the key
        scale_ffsetld_razee_cluster_rias ${MZONE_NAME} "${IBM_CLOUD_KEY}" ${PATH_TO_GENCTL_CI} ${FF_SETLD_REPLICAS}

        set -x
    else
        echo "${MZONE_NAME} does not match neither genctl nor rias, Exiting..."
        exit 1
    fi
}

function scale_ffsetld_razee_clusters() {
    # scaling the ffsld controller
    # Expected parameters:

    # Shared
    # $1 --> The cluster list (Comma separated, for example: rias-ng-us-south-dal12-dev91,mzone7196)
    # $2 --> Path to genctl-ci-repo (Without / as the end )
    # $3 --> Number of FF set LD pod replicas

    # Rias
    # $4 --> The IBM CLOUD KEY

    # Genctl
    # $5 --> Bastion Username
    # $6 --> Bastion key
    # $7 --> Bastion ECDSA key
    # $8 --> Bastion RSA key
    # $7 --> Dal vault key
    # $8 --> Path to platform inventory repo
    # $9 --> Artifactory URL
    # $10 --> Artifactory username
    # $11 --> Artifactory password
    # $12 --> Img to run path
    # $13 --> Img to run tag

    # Put some friendly names
    CLUSTERS_LIST=$1
    PATH_TO_GENCTL_CI=$2
    FF_SETLD_REPLICAS=$3
    IBM_CLOUD_KEY=$4
    B_U=$5;BASTION_KEY=$6;BASTION_KEY_ECDSA=$7;BASTION_KEY_RSA=$8
    DAL_VAULT_KEY=$9
    PATH_TO_PI=${10}
    ART_URL=${11};ART_USER=${12};ART_PASS=${13}
    IMG_TO_RUN_PATH=${14};IMG_TO_RUN_TAG=${15}


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
        scale_ffsetld_razee_cluster "${rule_tag}" ${PATH_TO_GENCTL_CI} ${FF_SETLD_REPLICAS} \
        "${IBM_CLOUD_KEY}" \
        ${B_U} "${BASTION_KEY}" "${BASTION_KEY_ECDSA}" "${BASTION_KEY_RSA}" \
        "${DAL_VAULT_KEY}" ${PATH_TO_PI} \
        ${ART_URL} ${ART_USER} ${ART_PASS}      \
        ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
        set -x
    done
}

function add_label_and_apply_patch() {
    RIAS_DESIRED_FFSLD=$1
    RIAS_ETCD_DESIRED_FFSLD=$2
    CLUSTER_TO_CHECK=$3
    set +x  # just to make this much easier on the eyes
    echo "=========so that the remote resource controller will not clobber the ffsld ========="
    echo 'kubectl label ffsld -n rias rias-ffs-ld deploy.razee.io/debug="true" --overwrite'
    kubectl label ffsld -n rias rias-ffs-ld deploy.razee.io/debug="true" --overwrite
    kubectl patch featureflagsetld rias-ffs-ld -n rias --type=merge -p "${RIAS_DESIRED_FFSLD}"
    if [[ ${CLUSTER_TO_CHECK} == *etcd ]]; then
        echo 'kubectl label ffsld -n rias-etcd rias-etcd-ffs-ld deploy.razee.io/debug="true" --overwrite'
        kubectl label ffsld -n rias-etcd rias-etcd-ffs-ld deploy.razee.io/debug="true" --overwrite
        kubectl patch featureflagsetld rias-etcd-ffs-ld -n rias-etcd --type=merge -p "${RIAS_ETCD_DESIRED_FFSLD}"
    fi
    kubectl get pods -n razee
    set -x
}


function disconnect_cos_remote_resource_rias_and_apply_patch() {
    # scale ffsetld in rias

    # Expected parameters:

    # $1 --> The cluster to check
    # $2 --> The IBM CLOUD KEY
    # $3 --> Path to genctl-ci-repo
    # $4 --> rias desired ffsld
    # $5 --> rias-etcd desired ffsld

    # Put some friendly names
    CLUSTER_TO_CHECK=$1
    IBM_CLOUD_KEY=$2
    PATH_TO_GENCTL_CI=$3
    RIAS_DESIRED_FFSLD=$4
    RIAS_ETCD_DESIRED_FFSLD=$5

    set +x
    # Login to ibmcloud using function defined in ibmcloud_utils.sh
    ibmcloud_login "${IBM_CLOUD_KEY}"
    get_iks_cluster_config ${CLUSTER_TO_CHECK}
    set -x

    add_label_and_apply_patch "${RIAS_DESIRED_FFSLD}" "${RIAS_ETCD_DESIRED_FFSLD}" "${CLUSTER_TO_CHECK}"
}

function disconnect_cos_remote_resource_genctl_and_apply_patch() {
    # scale ffsetld in genctl
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
    # $11 --> desired ffsld config for genctl

    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_GENCTL_CI=$2
    B_U=$3
    DAL_VAULT_KEY=$4
    PATH_TO_PI=$5
    ART_URL=$6;ART_USER=$7;ART_PASS=$8
    IMG_TO_RUN_PATH=$9;IMG_TO_RUN_TAG=${10}
    GENCTL_FFSLD_FILE_PATH=${11}

    # generate desired ffsld in the form of json from the ffsld yaml file
    yq '.data' ${GENCTL_FFSLD_FILE_PATH} | jq '{data: .}' > genctl_desired_ffsld.json

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

    # Copy desired_deployments to deployer
    rsync -aq --delete -e "ssh ${SSH_CONFIG_PARAMS}" ./genctl_desired_ffsld.json ${DEPLOY_SERVER_TARGET}:${MZONE_DIR}/genctl_desired_ffsld.json

    # command to run in a container
    COMMAND_INSIDE_CONTAINER="
    set -e
    export KUBECONFIG=${MZONE_DIR}/${MZONE_NAME}.conf
    kubectl label ffsld -n genctl genctl-ffs-ld deploy.razee.io/debug="true" --overwrite
    kubectl patch featureflagsetld genctl-ffs-ld -n genctl --type=merge --patch-file ${MZONE_DIR}/genctl_desired_ffsld.json
    sleep 15
    "

    set +x
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "
    docker run --rm --name=scale_ffsetld_razee_cluster_${MZONE_NAME}_\$(date -u +%s) --network host -v ${MZONE_DIR}:${MZONE_DIR} ${IMG_TO_RUN} /bin/bash -c \" ${COMMAND_INSIDE_CONTAINER}  \"
    "
    set -x
}




function disconnect_cos_remote_resource_and_apply_patch(){
    # Validates razee cluster (Including readiness)
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
    IBM_CLOUD_KEY=$3

    echo "disconnect cos remote resource and apply patch ${MZONE_NAME}"

    # Then check if genctl or rias
    if [[ ${MZONE_NAME} == mzone* ]]; then
    
        if [[ "${USE_QZ2_WORKER}" == true ]]; then
            echo "found genctl component, will proceed with the validations through a subpipeline"

            # Source a script that help us to validate existence and retrieve values from pipeline.yaml
            . ${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/verify_workspace_pipeline_yaml.sh ${PATH_TO_WORKSPACE_REPO} false

            FEATURE_FLAG=$(check_pipeline_key ".deployment" "feature_flag" "${PIPELINE_YAML_FILE_LOCATION}" true)

            REGIONDIGIT=${MZONE_NAME#*[[:digit:]]}  # Remove everything up to and including first digit
            REGIONDIGIT=${REGIONDIGIT:0:1}          # Take only the first character (2nd digit)

            [ "${REGIONDIGIT}" == "1" ] && REGIONDIGIT="0"

            echo "Extracted region digit: ${REGIONDIGIT} from mzone: ${MZONE_NAME}"

            export WORKER_ID="qz2-tekton-worker-trigger-dal1${REGIONDIGIT}"

            echo "Selected worker: ${WORKER_ID}"

            #temp fix until the issue is resolved
            export WORKSPACE=/workspace/app            
            
            ${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_v11_brt.sh "qz2-cluster-validations" ${WORKER_ID} "false" "onepipeline/pipelines/templatized/razee/pr_and_ci_master_v11/.pipeline-config-subpipeline-configurations.yaml" ${MZONE_NAME} ${FEATURE_FLAG}            
        else
            echo "Use older process for the validations"
            # Get additional genctl parameters
            B_U=$4;BASTION_KEY=$5;BASTION_KEY_ECDSA=$6;BASTION_KEY_RSA=$7
            DAL_VAULT_KEY=$8
            PATH_TO_PI=${9}
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

            export GENCTL_FFSLD_FILE_PATH=${PATH_TO_WORKSPACE_REPO}/FFSLD_ARTIFACTS/ffsld/genctl/${MZONE_NAME}/featureflagsetld.yaml

            set +x
            disconnect_cos_remote_resource_genctl_and_apply_patch ${MZONE_NAME} ${PATH_TO_GENCTL_CI} ${B_U} \
            "${DAL_VAULT_KEY}" ${PATH_TO_PI}    \
            ${ART_URL} ${ART_USER} ${ART_PASS}  \
            ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG} "${GENCTL_FFSLD_FILE_PATH}"
            sleep 150
            set -x

        fi

    elif [[ ${MZONE_NAME} == rias* ]]; then
        # Get additional rias parameters
        IBM_CLOUD_KEY=$3

        echo "${MZONE_NAME} is a rias cluster"

        set +x # so we do not log the key
        export RIAS_FFSLD_FILE_PATH=${PATH_TO_WORKSPACE_REPO}/FFSLD_ARTIFACTS/ffsld/rias/${MZONE_NAME}/featureflagsetld.yaml
        export RIAS_ETCD_FFSLD_FILE_PATH=${PATH_TO_WORKSPACE_REPO}/FFSLD_ARTIFACTS/ffsld/rias-etcd/${MZONE_NAME}/featureflagsetld.yaml

        # generate desired ffsld in the form of json
        RIAS_DESIRED_FFSLD=$(yq '.data' ${RIAS_FFSLD_FILE_PATH} | jq '{data: .}')
        RIAS_ETCD_DESIRED_FFSLD=$(yq '.data' ${RIAS_ETCD_FFSLD_FILE_PATH} | jq '{data: .}')

        disconnect_cos_remote_resource_rias_and_apply_patch ${MZONE_NAME} "${IBM_CLOUD_KEY}" ${PATH_TO_GENCTL_CI} "${RIAS_DESIRED_FFSLD}" "${RIAS_ETCD_DESIRED_FFSLD}"
        sleep 150
        set -x
    else
        echo "${MZONE_NAME} does not match neither genctl nor rias, Exiting..."
        exit 1
    fi
}

function disconnect_cos_remote_resources_and_apply_patch() {
    # scaling the ffsld controller
    # Expected parameters:

    # Shared
    # $1 --> The cluster list (Comma separated, for example: rias-ng-us-south-dal12-dev91,mzone7196)
    # $2 --> Path to genctl-ci-repo (Without / as the end )

    # Rias
    # $4 --> The IBM CLOUD KEY

    # Genctl
    # $5 --> Bastion Username
    # $6 --> Bastion key
    # $7 --> Bastion ECDSA key
    # $8 --> Bastion RSA key
    # $7 --> Dal vault key
    # $8 --> Path to platform inventory repo
    # $9 --> Artifactory URL
    # $10 --> Artifactory username
    # $11 --> Artifactory password
    # $12 --> Img to run path
    # $13 --> Img to run tag

    # Put some friendly names
    CLUSTERS_LIST=$1
    PATH_TO_GENCTL_CI=$2
    IBM_CLOUD_KEY=$3
    B_U=$4;BASTION_KEY=$5;BASTION_KEY_ECDSA=$6;BASTION_KEY_RSA=$7
    DAL_VAULT_KEY=$8
    PATH_TO_PI=${9}
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
        disconnect_cos_remote_resource_and_apply_patch "${rule_tag}" ${PATH_TO_GENCTL_CI} \
        "${IBM_CLOUD_KEY}" \
        ${B_U} "${BASTION_KEY}" "${BASTION_KEY_ECDSA}" "${BASTION_KEY_RSA}" \
        "${DAL_VAULT_KEY}" ${PATH_TO_PI} \
        ${ART_URL} ${ART_USER} ${ART_PASS} \
        ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG} \
        set -x
    done
}

function add_label_only() {
    CLUSTER_TO_CHECK=$1
    SINGLE_RIAS_CLUSTER_RULE=$2

    set +x  # just to make this much easier on the eyes
    echo "=========so that the remote resource controller will not clobber the ffsld ========="
    if [[ ${SINGLE_RIAS_CLUSTER_RULE} == "True" ]]; then
        # for single cluster env add label to rias and rias-etcd
        echo 'kubectl label ffsld -n rias-etcd rias-etcd-ffs-ld deploy.razee.io/debug="true"'
        kubectl label ffsld -n rias-etcd rias-etcd-ffs-ld deploy.razee.io/debug="true"

        echo 'kubectl label ffsld -n rias rias-ffs-ld deploy.razee.io/debug="true"'
        kubectl label ffsld -n rias rias-ffs-ld deploy.razee.io/debug="true"
    else
        if [[ ${CLUSTER_TO_CHECK} == *etcd ]]; then
            echo 'kubectl label ffsld -n rias-etcd rias-etcd-ffs-ld deploy.razee.io/debug="true"'
            kubectl label ffsld -n rias-etcd rias-etcd-ffs-ld deploy.razee.io/debug="true"
        else
            echo 'kubectl label ffsld -n rias rias-ffs-ld deploy.razee.io/debug="true"'
            kubectl label ffsld -n rias rias-ffs-ld deploy.razee.io/debug="true"
        fi
    fi
    kubectl get pods -n razee
    set -x
}

function disconnect_cos_remote_resource_rias() {
    # scale ffsetld in rias

    # Expected parameters:

    # $1 --> The cluster to check
    # $2 --> The IBM CLOUD KEY
    # $3 --> Path to genctl-ci-repo

    # Put some friendly names
    CLUSTER_TO_CHECK=$1
    IBM_CLOUD_KEY=$2
    PATH_TO_GENCTL_CI=$3
    SINGLE_RIAS_CLUSTER_RULE=$4

    set +x
    # Login to ibmcloud using function defined in ibmcloud_utils.sh
    ibmcloud_login "${IBM_CLOUD_KEY}"
    get_iks_cluster_config ${CLUSTER_TO_CHECK}
    set -x

    add_label_only "${CLUSTER_TO_CHECK}" ${SINGLE_RIAS_CLUSTER_RULE}
}

function disconnect_cos_remote_resource_genctl() {
    # scale ffsetld in genctl
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

    # command to run in a container
    COMMAND_INSIDE_CONTAINER="
    set -e
    export KUBECONFIG=${MZONE_DIR}/${MZONE_NAME}.conf
    kubectl label ffsld -n genctl genctl-ffs-ld deploy.razee.io/debug="true"
    sleep 15
    "

    set +x
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "
    docker run --rm --name=scale_ffsetld_razee_cluster_${MZONE_NAME}_\$(date -u +%s) --network host -v ${MZONE_DIR}:${MZONE_DIR} ${IMG_TO_RUN} /bin/bash -c \" ${COMMAND_INSIDE_CONTAINER}  \"
    "
    set -x
}

function disconnect_cos_remote_resource(){
    # Validates razee cluster (Including readiness)
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
    # $15 --> single rias cluster rule

    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_GENCTL_CI=$2
    IBM_CLOUD_KEY=$3

    echo "disconnect cos remote resource ${MZONE_NAME}"

    # Then check if genctl or rias
    if [[ ${MZONE_NAME} == mzone* ]]; then
        # Get additional genctl parameters
        B_U=$4;BASTION_KEY=$5;BASTION_KEY_ECDSA=$6;BASTION_KEY_RSA=$7
        DAL_VAULT_KEY=$8
        PATH_TO_PI=${9}
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

        set +x
        disconnect_cos_remote_resource_genctl ${MZONE_NAME} ${PATH_TO_GENCTL_CI} ${B_U} \
        "${DAL_VAULT_KEY}" ${PATH_TO_PI}    \
        ${ART_URL} ${ART_USER} ${ART_PASS}  \
        ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
        set -x

    elif [[ ${MZONE_NAME} == rias* ]]; then
        # Get additional rias parameters
        IBM_CLOUD_KEY=$3
        SINGLE_RIAS_CLUSTER_RULE=${15}

        echo "${MZONE_NAME} is a rias cluster"

        disconnect_cos_remote_resource_rias ${MZONE_NAME} "${IBM_CLOUD_KEY}" ${PATH_TO_GENCTL_CI} ${SINGLE_RIAS_CLUSTER_RULE}

        set -x
    else
        echo "${MZONE_NAME} does not match neither genctl nor rias, Exiting..."
        exit 1
    fi
}

function disconnect_cos_remote_resource_promotion(){
    # Disconnect COS remote resource for promotion pipeline (supports QZ2 workers)
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
    # $15 --> single rias cluster rule

    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_GENCTL_CI=$2
    IBM_CLOUD_KEY=$3

    echo "disconnect cos remote resource ${MZONE_NAME}"

    # Then check if genctl or rias
    if [[ ${MZONE_NAME} == mzone* ]]; then
        if [[ "${USE_QZ2_WORKER}" == "true" ]]; then
            echo "found genctl component, will proceed with the validations through a subpipeline"
            # Extract region digit from mzone name (e.g., mzone711 -> 1, mzone721 -> 2)
            # Pattern: mzone7XY where X is the region digit (position 6, 0-indexed)
            REGIONDIGIT=${MZONE_NAME:6:1}

            echo "Extracted region digit: ${REGIONDIGIT} from mzone: ${MZONE_NAME}"

            # Map region digit to dal zone: 1→dal10, 2→dal12, 3→dal13, 4→dal14
            case "${REGIONDIGIT}" in
                1) DAL_ZONE="dal10" ;;
                2) DAL_ZONE="dal12" ;;
                3) DAL_ZONE="dal13" ;;
                4) DAL_ZONE="dal14" ;;
                *) echo "ERROR: Unknown region digit ${REGIONDIGIT}"; exit 1 ;;
            esac

            export WORKER_ID="qz2-tekton-worker-trigger-${DAL_ZONE}"

            echo "Selected worker: ${WORKER_ID}"

            #temp fix until the issue is resolved
            export WORKSPACE=/workspace/app

            # Set environment variables required by the subpipeline
            set_env qz2-mzone-name "${MZONE_NAME}"
            set_env qz2-worker-id "${WORKER_ID}"
            set_env launch-darkly-feature-flag "${LAUNCH_DARKLY_FEATURE_FLAG:-}"

            # Trigger qz2-disconnect-cos-remote-resource subpipeline first to disconnect COS on QZ2 worker
            ${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_v11_brt.sh "qz2-disconnect-cos-remote-resource" ${WORKER_ID} "false" "onepipeline/pipelines/cd/templatized/promotion/pr_master/.pipeline-config.yaml" "${MZONE_NAME}" "${LAUNCH_DARKLY_FEATURE_FLAG}"

        else
            # Get additional genctl parameters
            B_U=$4;BASTION_KEY=$5;BASTION_KEY_ECDSA=$6;BASTION_KEY_RSA=$7
            DAL_VAULT_KEY=$8
            PATH_TO_PI=${9}
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

            set +x
            disconnect_cos_remote_resource_genctl ${MZONE_NAME} ${PATH_TO_GENCTL_CI} ${B_U} \
            "${DAL_VAULT_KEY}" ${PATH_TO_PI}    \
            ${ART_URL} ${ART_USER} ${ART_PASS}  \
            ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
            set -x
        fi

    elif [[ ${MZONE_NAME} == rias* ]]; then
        # Get additional rias parameters
        IBM_CLOUD_KEY=$3
        SINGLE_RIAS_CLUSTER_RULE=${15}

        echo "${MZONE_NAME} is a rias cluster"

        disconnect_cos_remote_resource_rias ${MZONE_NAME} "${IBM_CLOUD_KEY}" ${PATH_TO_GENCTL_CI} ${SINGLE_RIAS_CLUSTER_RULE}

        set -x
    else
        echo "${MZONE_NAME} does not match neither genctl nor rias, Exiting..."
        exit 1
    fi
}


function disconnect_cos_remote_resources() {
    # scaling the ffsld controller
    # Expected parameters:

    # Shared
    # $1 --> The cluster list (Comma separated, for example: rias-ng-us-south-dal12-dev91,mzone7196)
    # $2 --> Path to genctl-ci-repo (Without / as the end )

    # Rias
    # $4 --> The IBM CLOUD KEY

    # Genctl
    # $5 --> Bastion Username
    # $6 --> Bastion key
    # $7 --> Bastion ECDSA key
    # $8 --> Bastion RSA key
    # $7 --> Dal vault key
    # $8 --> Path to platform inventory repo
    # $9 --> Artifactory URL
    # $10 --> Artifactory username
    # $11 --> Artifactory password
    # $12 --> Img to run path
    # $13 --> Img to run tag

    # Put some friendly names
    CLUSTERS_LIST=$1
    PATH_TO_GENCTL_CI=$2
    IBM_CLOUD_KEY=$3
    B_U=$4;BASTION_KEY=$5;BASTION_KEY_ECDSA=$6;BASTION_KEY_RSA=$7
    DAL_VAULT_KEY=$8
    PATH_TO_PI=${9}
    ART_URL=${10};ART_USER=${11};ART_PASS=${12}
    IMG_TO_RUN_PATH=${13};IMG_TO_RUN_TAG=${14};SINGLE_RIAS_CLUSTER_RULE=${15}


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
        disconnect_cos_remote_resource "${rule_tag}" ${PATH_TO_GENCTL_CI} \
        "${IBM_CLOUD_KEY}" \
        ${B_U} "${BASTION_KEY}" "${BASTION_KEY_ECDSA}" "${BASTION_KEY_RSA}" \
        "${DAL_VAULT_KEY}" ${PATH_TO_PI} \
        ${ART_URL} ${ART_USER} ${ART_PASS} \
        ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG} ${SINGLE_RIAS_CLUSTER_RULE} \
        set -x
    done
}

