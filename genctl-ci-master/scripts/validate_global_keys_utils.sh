#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
function validate_global_keys_for_cluster_list() {
    # Validates global keys (Given a list of clusters)

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set

    # Expected parameters:

    # Shared
    # $1 --> The cluster list (Comma separated, for example: rias-ng-us-south-dal12-dev91,mzone7196)
    # $2 --> Path to genctl-ci-repo (Without / as the end )
    # $3 --> Path to the workspace-repo (Without / as the end )

    # Rias
    # $4 --> The IBM CLOUD KEY

    # Genctl
    # $5 --> Bastion Username
    # $6 --> Bastion key
    # $7 --> Bastion ECDSA key
    # $8 --> Bastion RSA key
    # $9 --> Dal vault key
    # $10 --> Path to platform inventory repo
    # $11--> Artifactory URL
    # $12 --> Artifactory username
    # $13 --> Artifactory password
    # $14 --> Img to run path
    # $15 --> Img to run tag

    # Put some friendly names
    CLUSTERS_LIST=$1
    PATH_TO_GENCTL_CI=$2;PATH_TO_WORKSPACE_REPO=$3
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
        validate_global_keys_for_cluster "${rule_tag}" ${PATH_TO_GENCTL_CI} ${PATH_TO_WORKSPACE_REPO} \
        "${IBMCLOUD_KEY}" \
        ${B_U} "${BASTION_KEY}" "${BASTION_KEY_ECDSA}" "${BASTION_KEY_RSA}" \
        "${DAL_VAULT_KEY}" ${PATH_TO_PI} \
        ${ART_URL} ${ART_USER} ${ART_PASS}      \
        ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
        set -x
    done
}
function validate_global_keys_for_cluster(){
    # Validates global keys

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set

    # Expected parameters:

    # Shared
    # $1 --> The cluster list (Comma separated, for example: rias-ng-us-south-dal12-dev91,mzone7196)
    # $2 --> Path to genctl-ci-repo (Without / as the end )
    # $3 --> Path to the workspace-repo (Without / as the end )

    # Rias
    # $4 --> The IBM CLOUD KEY

    # Genctl
    # $5 --> Bastion Username
    # $6 --> Bastion key
    # $7 --> Bastion ECDSA key
    # $8 --> Bastion RSA key
    # $9 --> Dal vault key
    # $10 --> Path to platform inventory repo
    # $11 --> Artifactory URL
    # $12 --> Artifactory username
    # $13 --> Artifactory password
    # $14 --> Img to run path
    # $15 --> Img to run tag

    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_GENCTL_CI=$2;PATH_TO_WORKSPACE_REPO=$3

    echo "Will validate global keys for ${MZONE_NAME}"

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
        validate_global_keys_genctl ${MZONE_NAME} ${PATH_TO_GENCTL_CI} ${PATH_TO_WORKSPACE_REPO} ${B_U} \
        "${DAL_VAULT_KEY}" "${PATH_TO_PI}" \
        ${ART_URL} ${ART_USER} ${ART_PASS}      \
        ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
        set -x

    elif [[ ${MZONE_NAME} == rias* ]]; then
        # Get additional rias parameters
        IBM_CLOUD_KEY=$4

        echo "${MZONE_NAME} is a rias cluster"

        set +x # so we do not log the key
        validate_global_keys_rias ${MZONE_NAME} "${IBM_CLOUD_KEY}" ${PATH_TO_GENCTL_CI} ${PATH_TO_WORKSPACE_REPO}
        set -x
    else
        echo "${MZONE_NAME} does not match neither genctl nor rias, Exiting..."
        exit 1
    fi
}
function validate_global_keys_genctl() {
    # Validates genctl

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set

    # Expected parameters:

    # $1 --> The Mzone name
    # $2 --> Path to genctl-ci-repo (Without / as the end )
    # $3 --> Path to the workspace-repo (Without / as the end )
    # $4 --> Bastion Username (Used for creating a folder in the deployer)
    # $5 --> Dal vault key
    # $6 --> Path to platform inventory repo
    # $7 --> Artifactory URL
    # $8 --> Artifactory username
    # $9 --> Artifactory password
    # $10 --> Img to run path
    # $11 --> Img to run tag

    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_GENCTL_CI=$2;PATH_TO_WORKSPACE_REPO=$3
    B_U=$4
    DAL_VAULT_KEY=$5
    PATH_TO_PI=$6
    ART_URL=$7;ART_USER=$8;ART_PASS=$9
    IMG_TO_RUN_PATH=${10};IMG_TO_RUN_TAG=${11}

    # Create the working directory in the deployer
    create_workdir_in_deployer ${MZONE_NAME} ${B_U}

    # Setup that allows us to run code in the deployer inside a docker container
    set +x
    setup_deployer_for_ci_work ${PATH_TO_GENCTL_CI} ${ART_URL} ${ART_USER} ${ART_PASS} ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
    set -x

    # Copy the workspace to the deployer
    set +x
    rsync -aq --delete -e "ssh ${SSH_CONFIG_PARAMS}" ${PATH_TO_WORKSPACE_REPO} ${DEPLOY_SERVER_TARGET}:${MZONE_DIR}/repos
    set -x

    # Setup that allows us to run kubectl commands against genctl cluster
    set +x
    setup_deployer_for_work_against_mzone ${MZONE_NAME} ${PATH_TO_GENCTL_CI} ${PATH_TO_PI} "${DAL_VAULT_KEY}"
    set -x

    # We need to extract these base names because in concourse the end paths are different
    # i.e genctl-ci-repo vs one-pipeline-config-repo or workspace repo vs keylore
    PATH_ON_DEPLOYER_GENCTL_CI=$(basename "$PATH_TO_GENCTL_CI")
    PATH_ON_DEPLOYER_WORKSPACE=$(basename "$PATH_TO_WORKSPACE_REPO")

    # In order for this fail the pipeline (As it happens in RIAS), we should have set -e flag inside the docker command
    # For now, we don't want this to fail pipeline for genctl
    COMMAND_INSIDE_CONTAINER="
    export KUBECONFIG=${MZONE_DIR}/${MZONE_NAME}.conf
    . ${MZONE_DIR}/repos/${PATH_ON_DEPLOYER_GENCTL_CI}/scripts/validate_global_keys_utils.sh
    validate_global_keys ${MZONE_DIR}/repos/${PATH_ON_DEPLOYER_GENCTL_CI} genctl ${MZONE_DIR}/repos/${PATH_ON_DEPLOYER_WORKSPACE}
    "

    set +x
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "
    docker run --rm --name=validate_global_keys_${MZONE_NAME}_\$(date -u +%s) --network host -v ${MZONE_DIR}:${MZONE_DIR} ${IMG_TO_RUN} /bin/bash -c \" ${COMMAND_INSIDE_CONTAINER}  \"
    "
    set -x
}
function validate_global_keys_rias() {
    # Validates rias

    # Expected parameters:

    # $1 --> The cluster to check
    # $2 --> The IBM CLOUD KEY
    # $3 --> Path to genctl-ci-repo
    # $4 --> Path to workspace repo

    # Put some friendly names
    CLUSTER_TO_CHECK=$1
    IBM_CLOUD_KEY=$2
    PATH_TO_GENCTL_CI=$3
    PATH_TO_WORKSPACE_REPO=$4

    set +x
    # Login to ibmcloud using function defined in ibmcloud_utils.sh
    ibmcloud_login "${IBM_CLOUD_KEY}"
    get_iks_cluster_config ${CLUSTER_TO_CHECK}
    set -x

    validate_global_keys ${PATH_TO_GENCTL_CI} "rias" ${PATH_TO_WORKSPACE_REPO}
}

### SHARED FUNCTIONS ###
# With the proper setup, these functions can be run in both situations:

# 1. In Concourse (when working against rias) or in a container
# 2. In a container inside the deployer (When working against genctl)

function validate_global_keys(){

    PATH_TO_GENCTL_CI=$1
    # This needs to be exported since it is used in the python script
    export CLUSTER_TYPE=$2
    PATH_TO_WORKSPACE_REPO=$3

    python3 -m pip install -q ${PATH_TO_GENCTL_CI}/tools/ci_python_tools
    python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/global_keys_check/requirements.txt

    export ROOT_DIRECTORY_TO_FIND_YAML="${PATH_TO_WORKSPACE_REPO}/hack/deploy/razee"

    python3 ${PATH_TO_GENCTL_CI}/scripts/global_keys_check/global_keys_check.py
}
