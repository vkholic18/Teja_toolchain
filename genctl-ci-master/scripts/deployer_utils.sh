#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

function setup_ssh_to_deployer() {
    # Setup the environment to perform commands in the deployer through SSH
    # After calling this function, we can make commands in the deployer in the form of:

    # ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "ls -l"

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced

    # Expected parameters:

    # $1 --> The mzone name
    # $2 --> The bastion user name
    # $3 --> The bastion private key
    # $4 --> The bastion private ECDSA key
    # $5 --> The bastion private RSA key

    # Put some friendly names
    MZONE_NAME=$1
    BASTION_USERNAME=$2
    BASTION_PRIVATE_KEY=$3
    BASTION_PRIVATE_KEY_ECDSA=$4
    BASTION_PRIVATE_KEY_RSA=$5

    if [[ -z "$MZONE_NAME" ]]; then
            echo "Failed to obtain an mzone, quitting..."
            exit 1
    fi
    echo MZONE_NAME=${MZONE_NAME}

    # Second digit of mzone name tells us where the mzone is and thus what jumphost to use
    REGIONDIGIT=${MZONE_NAME#*[[:digit:]]}
    REGIONDIGIT=${REGIONDIGIT:0:1}

    declare -ar VALID_REGIONS=( 1 2 3 4 )
    if [[ ! "${VALID_REGIONS[@]}" =~ "${REGIONDIGIT}" ]]; then
        echo "Unsupported mzone: ${MZONE_NAME} (region ${REGIONDIGIT})"
        exit 1
    fi

    set +x
    declare -r bastion_priv_key="/tmp/priv_key"
    declare -r bastion_priv_key_ecdsa="/tmp/priv_key_ecdsa"
    declare -r bastion_priv_key_rsa="/tmp/priv_key_rsa"
    echo "${BASTION_PRIVATE_KEY}" > ${bastion_priv_key}
    echo "${BASTION_PRIVATE_KEY_ECDSA}" > ${bastion_priv_key_ecdsa}
    echo "${BASTION_PRIVATE_KEY_RSA}" > ${bastion_priv_key_rsa}
    chmod 600 ${bastion_priv_key} ${bastion_priv_key_ecdsa} ${bastion_priv_key_rsa}
    set -x
    get_deployer_conn_path ssh_bastion ssh_deployer ${BASTION_USERNAME} ${bastion_priv_key} ${bastion_priv_key_ecdsa} ${bastion_priv_key_rsa} ${REGIONDIGIT}

    # ensure failure on non-zero is not masked
    # courtesy of Tal why we are forcing set -e
    # https://unix.stackexchange.com/questions/383541/how-to-save-restore-all-shell-options-including-errexit
    set -e

    rm ${bastion_priv_key}
    rm ${bastion_priv_key_ecdsa}
    rm ${bastion_priv_key_rsa}
    export BASTION=${ssh_bastion}
    export DEPLOY_SERVER=${ssh_deployer}

    # check and dont go any further if we could not locate a working pair
    if [[ -z ${BASTION} || -z ${DEPLOY_SERVER} ]]; then
        echo "unable to locate a working bastion/deployer"
        exit 1
    fi

    export DEPLOY_SERVER_TARGET="${BASTION_USERNAME}@${DEPLOY_SERVER}"
    export SSH_CONFIG_PARAMS="-o ServerAliveInterval=15"

    if [[ -n "$BASTION" ]]; then
        export SSH_CONFIG_PARAMS+=" -J ${BASTION_USERNAME}@${BASTION}"
    fi

    echo DEPLOY_SERVER_TARGET="${DEPLOY_SERVER_TARGET}"
    echo SSH_CONFIG_PARAMS="${SSH_CONFIG_PARAMS}"

    eval "$(ssh-agent -s)"
    ssh-add - <<< "${BASTION_PRIVATE_KEY}"
    ssh-add - <<< "${BASTION_PRIVATE_KEY_ECDSA}"
    ssh-add - <<< "${BASTION_PRIVATE_KEY_RSA}"

}

#Setup the environment to perform commands in the deployer through SSH without using Bastion. 
#This function is getting used by OnePipeline where we don't need bastion jumphost to connect to the deployer
function setup_ssh_to_deployer_one_pipeline() {
    # Setup the environment to perform commands in the deployer through SSH
    # After calling this function, we can make commands in the deployer in the form of:

    # ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "ls -l"

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced

    # Expected parameters:

    # $1 --> The mzone name
    # $2 --> The deployer user name
    # $3 --> The deployer private key
    # $4 --> The deployer private ECDSA key
    # $5 --> The deployer private RSA key

    # Put some friendly names
    MZONE_NAME=$1
    DEPLOYER_USERNAME=$2
    DEPLOYER_PRIVATE_KEY=$3
    DEPLOYER_PRIVATE_KEY_ECDSA=$4
    DEPLOYER_PRIVATE_KEY_RSA=$5

    if [[ -z "$MZONE_NAME" ]]; then
            echo "Failed to obtain an mzone, quitting..."
            exit 1
    fi
    echo MZONE_NAME=${MZONE_NAME}

    # Second digit of mzone name tells us where the mzone is and thus what deployer to use
    REGIONDIGIT=${MZONE_NAME#*[[:digit:]]}
    REGIONDIGIT=${REGIONDIGIT:0:1}

    declare -ar VALID_REGIONS=( 1 2 3 4 )
    if [[ ! "${VALID_REGIONS[@]}" =~ "${REGIONDIGIT}" ]]; then
        echo "Unsupported mzone: ${MZONE_NAME} (region ${REGIONDIGIT})"
        exit 1
    fi

    set +x
    declare -r deployer_priv_key="/tmp/priv_key"
    declare -r deployer_priv_key_ecdsa="/tmp/priv_key_ecdsa"
    declare -r deployer_priv_key_rsa="/tmp/priv_key_rsa"
    echo "${DEPLOYER_PRIVATE_KEY}" > ${deployer_priv_key}
    echo "${DEPLOYER_PRIVATE_KEY_ECDSA}" > ${deployer_priv_key_ecdsa}
    echo "${DEPLOYER_PRIVATE_KEY_RSA}" > ${deployer_priv_key_rsa}
    chmod 600 ${deployer_priv_key} ${deployer_priv_key_ecdsa} ${deployer_priv_key_rsa}
    set -x
    get_deployer_conn_path_one_pipeline ssh_deployer ${DEPLOYER_USERNAME} ${deployer_priv_key} ${deployer_priv_key_ecdsa} ${deployer_priv_key_rsa} ${REGIONDIGIT}

    # ensure failure on non-zero is not masked
    # courtesy of Tal why we are forcing set -e
    # https://unix.stackexchange.com/questions/383541/how-to-save-restore-all-shell-options-including-errexit
    set -e

    rm ${deployer_priv_key}
    rm ${deployer_priv_key_ecdsa}
    rm ${deployer_priv_key_rsa}
    
    export DEPLOY_SERVER=${ssh_deployer}

    # check and dont go any further if we could not locate a working deployer
    if [[ -z ${DEPLOY_SERVER} ]]; then
        echo "unable to locate a working deployer"
        exit 1
    fi

    export DEPLOY_SERVER_TARGET="${DEPLOYER_USERNAME}@${DEPLOY_SERVER}"
    export SSH_CONFIG_PARAMS="-o ServerAliveInterval=15"    

    echo DEPLOY_SERVER_TARGET="${DEPLOY_SERVER_TARGET}"
    echo SSH_CONFIG_PARAMS="${SSH_CONFIG_PARAMS}"

    eval "$(ssh-agent -s)"
    ssh-add - <<< "${DEPLOYER_PRIVATE_KEY}"
    ssh-add - <<< "${DEPLOYER_PRIVATE_KEY_ECDSA}"
    ssh-add - <<< "${DEPLOYER_PRIVATE_KEY_RSA}"

}

function pull_image_and_copy_to_deployer() {
    # Logins into a docker repo, pulls an image, copies it to the deployer, and loads it on it
    # In addition allows to retag the image if required

    # After this function runs, we should be able to use the image in the deployer

    # Prerequisites (They are not actively checked)
    # docker installed and running
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set

    # Expected parameters:

    # $1 --> URL to the docker repo
    # $2,$3 --> Username and password for authentication against $1
    # $4 --> Image path for performing pull (Relative to $1) (Ex: kube/kube-define-release:5.1.0_20220117T214810Z_485e0e9)
    # $5 --> true or false (Indicates if need to retag)
    # $6 --> New tag (Full format including the repo) - If $5 is false then should be "None" (And we don't use it)
    # $7 --> Filename of the image (The name that is used to save it as a "file" before copying it)
    # $8 --> Path in DEPLOY_SERVER_TARGET where the image will be stored

    # Put some friendly names
    DOCKER_URL=$1
    DOCKER_USER=$2;DOCKER_PASS=$3
    IMAGE_PATH=$4; FULL_IMAGE_PATH=${DOCKER_URL}/${IMAGE_PATH}; TAG_TO_SAVE=${FULL_IMAGE_PATH}
    RETAG_FLAG=$5
    NEW_TAG=$6
    IMAGE_FILENAME=$7
    PATH_IN_TARGET=$8

    # First login

    # docker login to staging registry so that we can pull images
    set +x  # so we do not log the password
    echo "docker logging in to ${DOCKER_URL}"
    echo ${DOCKER_PASS} | docker login ${DOCKER_URL} -u ${DOCKER_USER} --password-stdin
    set -x

    # Pull and copy the image we are testing to deploy server
    docker pull ${FULL_IMAGE_PATH}

    # If needed retag
    if [ "${RETAG_FLAG}" == "true" ]
    then
        # retag as if it came from the official repo due to DDT limitation that artifrepo can only be
        # specified at the component level, not the package level
        docker tag ${FULL_IMAGE_PATH} ${NEW_TAG}
        TAG_TO_SAVE=${NEW_TAG}
    elif [ "${RETAG_FLAG}" == "false" ]
    then
        echo "Won't make any retag"
    else
        echo "Error: Unknown retag option"
        exit 1
    fi


    # Save
    docker save ${TAG_TO_SAVE} > ${IMAGE_FILENAME}.img

    # Work with the remote: First copy, then load and then delete
    rsync -aq -e "ssh ${SSH_CONFIG_PARAMS}" ${IMAGE_FILENAME}.img ${DEPLOY_SERVER_TARGET}:${PATH_IN_TARGET}/
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "cat ${PATH_IN_TARGET}/${IMAGE_FILENAME}.img | docker load"
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "rm ${PATH_IN_TARGET}/${IMAGE_FILENAME}.img"

}
function check_image_exists_in_deployer() {
    # Checks if a docker image already exists in DEPLOY_SERVER_TARGET

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set

    # Expected parameters:

    # $1 --> URL of the docker image (Ex: docker-na-public.artifactory.swg-devops.com/wcp-genctl-docker-local)
    # $2 --> Image path (Ex: genctl/golang-ci)
    # $3 --> Image tag (Ex: 20220113203138-amd64)

    # Put some friendly names
    IMAGE_URL=$1;IMAGE_PATH=$2;IMAGE_TAG=$3

    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "docker images | grep ${IMAGE_URL}/${IMAGE_PATH} | grep ${IMAGE_TAG}"
}
function export_vault_vars(){
    # Given an mzone name and the path to the platform inventory repo, parses and export some useful variables

    # Prerequisites (They are not actively checked)
    # yq

    # Expected parameters:

    # $1 --> Mzone name
    # $2 --> Path to platform inventory repo

    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_PLATFORM_INVENTORY_REPO=$2


    MZONE_INV_FILE=${PATH_TO_PLATFORM_INVENTORY_REPO}/region/${MZONE_NAME}.yml
    echo mzone configuration file MZONE_INV_FILE=${MZONE_INV_FILE}

    UNDERCLOUD=`yq -r ".undercloud" ${MZONE_INV_FILE}`
    UNDERCLOUD_FILE=${PATH_TO_PLATFORM_INVENTORY_REPO}/region/undercloud/${UNDERCLOUD}.yml
    export VAULT_IP=`yq -r ".services.vault.services_ip" ${UNDERCLOUD_FILE}`
    echo VAULT_IP=${VAULT_IP}
    export VAULT_PREFIX=`yq -r ".services.vault.prefix" ${UNDERCLOUD_FILE}`
    echo VAULT_PREFIX=${VAULT_PREFIX}

}

function generate_ngsec_and_copy_to_deployer() {
    # Generates an .ngsec directory and copies it into the deployer
    # The .ngesc directory contains:
    # A vault token (In a file token under /tmpsec)

    # Optionally:  Certificate and vault.env file

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set

    # Expected parameters:

    # $1 --> Vault IP
    # $2 --> Vault Key
    # $3 --> Vault Namespace
    # $4 --> Vault cert
    # $5 --> Vault prefix
    # $6 -->  Path in DEPLOY_SERVER_TARGET where the .ngsec will be stored
    # $7 --> Boolean; if true the ngsec directory will have only the token, if false it will have the token + certificate and vault.env file

    # Put some friendly names
    VAULT_IP=$1;VAULT_KEY=$2;VAULT_NAMESPACE=$3;VAULT_CACERT=$4;VAULT_PREFIX=$5
    PATH_IN_TARGET=$6
    ONLY_TOKEN=$7

    # Generate a time-limited vault token for DDT deploy
    rm -rf .ngsec
    mkdir -p .ngsec/tmpsec
    ssh -f -o ExitOnForwardFailure=yes ${SSH_CONFIG_PARAMS} -L 8200:${VAULT_IP}:8200 ${DEPLOY_SERVER_TARGET} sleep 10
    set +x  # so we do not log the vault key
    echo "${VAULT_KEY}" | curl --retry 5 -H "X-Vault-Namespace: ${VAULT_NAMESPACE}" --cacert $VAULT_CACERT --data @- --url https://127.0.0.1:8200/v1/auth/approle/login -s | jq -r .auth.client_token > .ngsec/tmpsec/token; chmod 600 .ngsec/tmpsec/token
    set -x
    if [ -s .ngsec/tmpsec/token ]; then
        echo "Got vault token"
    else
        echo "Unable to get vault token"
        exit 1
    fi

    # If needed retag
    if [ "${ONLY_TOKEN}" == "true" ]
    then
        echo ".ngsec folder will contain only the token"
    elif [ "${ONLY_TOKEN}" == "false" ]
    then
        echo ".ngesc folder will contain token + certificate + vault.env file"
        cp ${VAULT_CACERT} .ngsec/vault-intermediary_ca.crt

        # Setup vault env file
        touch .ngsec/vault.env
        echo "export VAULT_TOKEN_PATH=${PATH_IN_TARGET}/.ngsec/tmpsec/token" >> .ngsec/vault.env
        echo "VAULT_CACERT=${PATH_IN_TARGET}/.ngsec/vault-intermediary_ca.crt" >> .ngsec/vault.env
        echo "export VAULT_ADDR=\"https://${VAULT_IP}:8200\"" >> .ngsec/vault.env
        echo "VAULT_NAMESPACE=${VAULT_NAMESPACE}" >> .ngsec/vault.env
        echo "VAULT_PREFIX=${VAULT_PREFIX}" >> .ngsec/vault.env
    else
       "Error: Unknown ONLY_TOKEN option"
       exit 1
    fi

    # Copy .ngsec to deploy server
    rsync -aq --delete -e "ssh ${SSH_CONFIG_PARAMS}" ./.ngsec/ ${DEPLOY_SERVER_TARGET}:${PATH_IN_TARGET}/.ngsec
}

function fetch_kubeconfig_from_vault_to_deployer(){
    # This function uses vault CLI to retrieve the kubeconfig and put it on the designated folder
    # All this happens in the deployer (DEPLOY_SERVER_TARGET)

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set
    # In the DEPLOY_SERVER_TARGET we have ngsec folder including certificate and vault.env file (Which can be achieved by using function generate_ngsec_and_copy_to_deployer)

    # Expected parameters:

    # $1 --> The Mzone name
    # $2 --> The path to the ngsec folder
    # $3 --> Vault namespace
    # $4 --> The path where the kubernetes configuration will be stored (in DEPLOY_SERVER_TARGET)

    MZONE_NAME=$1
    PATH_TO_NGSEC=$2
    VAULT_NAMESPACE=$3
    KUBECONFIG_FILENAME_PATH=$4

    # Don't log
    set +x

    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} ". ${PATH_TO_NGSEC}/vault.env && export VAULT_TOKEN=\"\$(cat \${VAULT_TOKEN_PATH})\" && vault kv get -namespace=${VAULT_NAMESPACE} -format=yaml -field=data kube/${MZONE_NAME}/admin.conf > ${KUBECONFIG_FILENAME_PATH}"
}

function create_workdir_in_deployer(){
    # This function creates a directory in the deployer
    # The directory is used later in processes like copying docker images/retrieving kubeconfig
    # The name of the directory is /home/<the bastion username>/<the mzone we are working against>
    # This is also exported as an environment variable called MZONE_DIR

    # The directory has a directory under it called repos, used for putting there repositories

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set

    # Expected parameters:

    # $1 --> The Mzone name
    # $2 --> Bastion Username

    # Put some friendly names
    MZONE_NAME=$1;BAST_USER=$2

    # Important: We export it to be available in other functions
    export MZONE_DIR=/home/${BAST_USER}/${MZONE_NAME}
    REPO_DIR=${MZONE_DIR}/repos

    # Actual creation
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "mkdir -p ${REPO_DIR}"
}

function setup_deployer_for_ci_work(){
    # This function prepares the deployer for running CI stuff on it
    # What we do is:

    # 1. We copy to the working directory in the deployer the genctl-ci-repo
    # 2. Since we want to try to not disturb the deployer itself, we run stuff on a container (Deployers have docker)
    #    therefore, in this function we verify that the image in which we want to run exists in the deployer and if not, we get it
    #
    #   Note that getting the image is NOT done in the deployer, but we get the image outside of it, copy the image with rsync and then load it (That last step is done in the deployer)

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set
    # The working directory in the deployer was created and we have MZONE_DIR var with the proper value

    # Expected parameters:

    # $1 --> Path to genctl-ci-repo (Without / as the end )
    # $2 --> Artifactory URL
    # $3 --> Artifactory username
    # $4 --> Artifactory password
    # $5 --> Img to run path
    # $6 --> Img to run tag

    # Put some friendly names
    PATH_TO_GENCTL_CI=$1
    ART_URL=$2;ART_USER=$3;ART_PASS=$4
    IMG_TO_RUN_PATH=$5;IMG_TO_RUN_TAG=$6

    #Check is target is valid
    if [[ ! ${MZONE_DIR} =~ ^/home/clconc/.+ ]]; then
        echo "Target dir ${MZONE_DIR} not valid"
        exit 1
    fi

    # Delete .git directory and copy the genctl-ci-repo to the deployer (Including the directory itself)
    rm -rf ${PATH_TO_GENCTL_CI}/.git
    rsync --delete -aq -e "ssh ${SSH_CONFIG_PARAMS}" ${PATH_TO_GENCTL_CI} ${DEPLOY_SERVER_TARGET}:${MZONE_DIR}/repos


    # To simplify, concatenate some vars to have the full image name
    IMG_TO_RUN="${ART_URL}/${IMG_TO_RUN_PATH}:${IMG_TO_RUN_TAG}"

    # Verify if the image exists in the deployer (We need +e flag in order to always achieve the line where we save the $?)
    set +e
    check_image_exists_in_deployer ${ART_URL} ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
    result_image_exists_in_deployer=$?
    set -e

    # If the image exists no need to download it and we are all ready to use it, if it does not exist, need to download it and copy it to the deployer
    if [ ${result_image_exists_in_deployer} -eq 0 ]
    then
        echo "Image ${IMG_TO_RUN} already exists in deployer ${DEPLOY_SERVER_TARGET}"
    else
        echo "Image ${IMG_TO_RUN} does not exist in deployer ${DEPLOY_SERVER_TARGET}, will need to pull it and copy it to the deployer"
        set +x
        pull_image_and_copy_to_deployer ${ART_URL} \
        ${ART_USER} ${ART_PASS} "${IMG_TO_RUN_PATH}:${IMG_TO_RUN_TAG}" \
        "false" "None" "temp_image" ${MZONE_DIR}
    fi
}

function setup_deployer_for_work_against_mzone(){
    # This function prepares the deployer for working against an mzone

    # What we do is:

    # 1. Export some vault related vars
    # 2. Generate a .ngsec folder and copy it to the deployer (Is used for working with vault)
    # 3. Fetch from vault the Kubeconfig

    # Once we run this function, we should be able to do the following:

    # 1. export KUBECONFIG=${MZONE_DIR}/${MZONE_NAME}.conf
    # 2. kubectl get nodes

    # And this should return the nodes on the cluster

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set
    # The working directory in the deployer was created and we have MZONE_DIR var with the proper value

    # Expected parameters:

    # $1 --> Mzone name
    # $2 --> Path to genctl-ci-repo (Without / as the end )
    # $3 --> Path to platform inventory repo
    # $4 --> Dal vault key

    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_GENCTL_CI=$2
    PATH_TO_PI=$3
    DAL_VAULT_KEY=$4

    export VAULT_CACERT="${PATH_TO_GENCTL_CI}/certificates/vault-dal-intermediary-ca.pem"
    export VAULT_NAMESPACE="nextgen"

    set +x
    export VAULT_KEY="${DAL_VAULT_KEY}"
    set -x

    # Export vault related vars
    export_vault_vars ${MZONE_NAME} ${PATH_TO_PI}

    # Generate .ngsec and copy to deployer
    set +x
    generate_ngsec_and_copy_to_deployer ${VAULT_IP} "${VAULT_KEY}" ${VAULT_NAMESPACE} "${VAULT_CACERT}" ${VAULT_PREFIX} ${MZONE_DIR} "false"
    set -x

    # Fetch from vault kubeconfig and copy it to deployer
    set +x
    fetch_kubeconfig_from_vault_to_deployer ${MZONE_NAME} "${MZONE_DIR}/.ngsec" ${VAULT_NAMESPACE} "${MZONE_DIR}/${MZONE_NAME}.conf"
    set -x
}
