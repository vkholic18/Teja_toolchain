#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# The validation of featureflag consists of retrieving from Launch Darkly, retrieving from the relevant cluster and compare
# Is important to note that since we can't reach LD from the deployer, we do the following:
# We retrieve information from LD (A script is executed in concourse) and save it so we can copy it to the deployer
# Once we have the LD information in the deployer, we can reach the cluster from the deployer and compare

function validate_featureflags_from_cluster_list() {
    # Validates feature flags (Given a list of clusters)

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set

    # Expected parameters:

    # Shared
    # $1 --> The cluster list (Comma separated, for example: rias-ng-us-south-dal12-dev91,mzone7196)
    # $2 --> Path to genctl-ci-repo (Without / as the end )
    # $3 --> The launch darkly feature flag
    # $4 --> The launch darkly environment
    # $5 --> Git token
    # $6 --> Fail if error

    # Rias
    # $7 --> The IBM CLOUD KEY

    # Genctl
    # $8 --> Bastion Username
    # $9 --> Bastion key
    # $10 --> Bastion ECDSA key
    # $11 --> Bastion RSA key
    # $10 --> Dal vault key
    # $11 --> Path to platform inventory repo
    # $12 --> Artifactory URL
    # $13 --> Artifactory username
    # $14 --> Artifactory password
    # $15 --> Img to run path
    # $16 --> Img to run tag

    # Put some friendly names
    CLUSTERS_LIST=$1
    PATH_TO_GENCTL_CI=$2
    LAUNCH_DARKLY_FEATURE_FLAG=$3;LAUNCH_DARKLY_ENVIRONMENT=$4
    GIT_TOKEN=$5
    FAIL_IF_ERROR=$6

    IBM_CLOUD_KEY=$7
    B_U=$8;BASTION_KEY=$9;BASTION_KEY_ECDSA=${10};BASTION_KEY_RSA=${11}
    DAL_VAULT_KEY=${12}
    PATH_TO_PLATFORM_INVENTORY_REPO=${13}
    ART_URL=${14};ART_USER=${15};ART_PASS=${16}
    IMG_TO_RUN_PATH=${17};IMG_TO_RUN_TAG=${18}


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
        validate_featureflags "${rule_tag}" ${PATH_TO_GENCTL_CI} \
        ${LAUNCH_DARKLY_FEATURE_FLAG} ${LAUNCH_DARKLY_ENVIRONMENT} "${GIT_TOKEN}" ${FAIL_IF_ERROR} \
        "${IBMCLOUD_KEY}" \
        ${B_U} "${BASTION_KEY}" "${BASTION_KEY_ECDSA}" "${BASTION_KEY_RSA}" \
        "${DAL_VAULT_KEY}" ${PATH_TO_PLATFORM_INVENTORY_REPO} \
        ${ART_URL} ${ART_USER} ${ART_PASS}      \
        ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG} \
        set -x
    done
}

function validate_featureflags_for_cos_ffsld_and_cluster() {
    # Validates feature flags (Given a list of clusters)

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set

    # Expected parameters:

    # Shared
    # $1 --> The cluster list (Comma separated, for example: rias-ng-us-south-dal12-dev91,mzone7196)
    # $2 --> Path to genctl-ci-repo (Without / as the end )
    # $3 --> Git token
    # $4 --> Fail if error

    # Rias
    # $5 --> The IBM CLOUD KEY

    # Genctl
    # $6 --> Bastion Username
    # $7 --> Bastion key
    # $8 --> Bastion ECDSA key
    # $9 --> Bastion RSA key
    # $10 --> Dal vault key
    # $11 --> Path to platform inventory repo
    # $12 --> Artifactory URL
    # $13 --> Artifactory username
    # $14 --> Artifactory password
    # $15 --> Img to run path
    # $16 --> Img to run tag

    # Put some friendly names
    CLUSTERS_LIST=$1
    PATH_TO_GENCTL_CI=$2
    GIT_TOKEN=$3
    FAIL_IF_ERROR=$4
    IBM_CLOUD_KEY=$5
    B_U=$6;BASTION_KEY=$7;BASTION_KEY_ECDSA=${8};BASTION_KEY_RSA=${9}
    DAL_VAULT_KEY=${10}
    PATH_TO_PLATFORM_INVENTORY_REPO=${11}
    ART_URL=${12};ART_USER=${13};ART_PASS=${14}
    IMG_TO_RUN_PATH=${15};IMG_TO_RUN_TAG=${16}


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
        validate_featureflags_cos_ffsld "${rule_tag}" ${PATH_TO_GENCTL_CI} \
        "${GIT_TOKEN}" ${FAIL_IF_ERROR} \
        "${IBMCLOUD_KEY}" \
        ${B_U} "${BASTION_KEY}" "${BASTION_KEY_ECDSA}" "${BASTION_KEY_RSA}" \
        "${DAL_VAULT_KEY}" ${PATH_TO_PLATFORM_INVENTORY_REPO} \
        ${ART_URL} ${ART_USER} ${ART_PASS}      \
        ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
        set -x
    done
}

function validate_featureflags(){
    # Validates feature flags

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set


    # Expected parameters:

    # Shared
    # $1 --> The cluster name
    # $2 --> Path to genctl-ci-repo (Without / as the end )
    # $3 --> The launch darkly feature flag
    # $4 --> The launch darkly environment
    # $5 --> Git token
    # $6 --> Fail if error

    # Rias
    # $7 --> The IBM CLOUD KEY

    # Genctl
    # $8 --> Bastion Username
    # $9 --> Bastion key
    # $10 --> Bastion ECDSA key
    # $11 --> Bastion RSA key
    # $12 --> Dal vault key
    # $13 --> Path to platform inventory repo
    # $14 --> Artifactory URL
    # $15 --> Artifactory username
    # $16 --> Artifactory password
    # $17 --> Img to run path
    # $18 --> Img to run tag


    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_GENCTL_CI=$2
    LAUNCH_DARKLY_FEATURE_FLAG=$3;LAUNCH_DARKLY_ENVIRONMENT=$4
    GIT_TOKEN=$5
    FAIL_IF_ERROR=$6

    echo "Will validate feature flags for ${MZONE_NAME}"

    # Then check if genctl or rias
    if [[ ${MZONE_NAME} == mzone* ]]; then
        # Get additional genctl parameters
        B_U=$8;BASTION_KEY=$9;BASTION_KEY_ECDSA=${10};BASTION_KEY_RSA=${11}
        DAL_VAULT_KEY=${12}
        PATH_TO_PI=${13}
        ART_URL=${14};ART_USER=${15};ART_PASS=${16}
        IMG_TO_RUN_PATH=${17};IMG_TO_RUN_TAG=${18}

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
        validate_featureflag_genctl ${MZONE_NAME} ${PATH_TO_GENCTL_CI} \
        ${LAUNCH_DARKLY_FEATURE_FLAG} ${LAUNCH_DARKLY_ENVIRONMENT} "${GIT_TOKEN}" ${FAIL_IF_ERROR} \
        ${BASTION_USERNAME} \
        "${DAL_VAULT_KEY}" ${PATH_TO_PI} \
        ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN}      \
        ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
        set -x

    elif [[ ${MZONE_NAME} == rias* ]]; then
        # Get additional rias parameters
        IBM_CLOUD_KEY=$7

        echo "${MZONE_NAME} is a rias cluster"

        set +x # so we do not log the key
        validate_featureflag_rias ${MZONE_NAME} ${PATH_TO_GENCTL_CI} \
        ${LAUNCH_DARKLY_FEATURE_FLAG} ${LAUNCH_DARKLY_ENVIRONMENT} "${GIT_TOKEN}" ${FAIL_IF_ERROR} \
        "${IBMCLOUD_KEY}"
        set -x
    else
        echo "${MZONE_NAME} does not match neither genctl nor rias, Exiting..."
        exit 1
    fi
}

function validate_featureflags_cos_ffsld(){
    # Validates feature flags

    # Prerequisites (They are not actively checked)
    # ssh_utils was sourced and SSH_CONFIG_PARAMS and DEPLOY_SERVER_TARGET vars are properly set


    # Expected parameters:

    # Shared
    # $1 --> The cluster name
    # $2 --> Path to genctl-ci-repo (Without / as the end )
    # $3 --> Git token
    # $4 --> Fail if error

    # Rias
    # $5 --> The IBM CLOUD KEY

    # Genctl
    # $6 --> Bastion Username
    # $7 --> Bastion key
    # $8 --> Bastion ECDSA key
    # $9 --> Bastion RSA key
    # $10 --> Dal vault key
    # $11 --> Path to platform inventory repo
    # $12 --> Artifactory URL
    # $13 --> Artifactory username
    # $14 --> Artifactory password
    # $15 --> Img to run path
    # $16 --> Img to run tag

    # Put some friendly names
    MZONE_NAME=$1
    PATH_TO_GENCTL_CI=$2
    GIT_TOKEN=$3
    FAIL_IF_ERROR=$4

    echo "Will validate feature flags for ${MZONE_NAME}"

    # Then check if genctl or rias
    if [[ ${MZONE_NAME} == mzone* ]]; then

        if [[ $USE_QZ2_WORKER == true ]]; then
           echo "Will be carried out in a subpipeline"
        else
            # Get additional genctl parameters
            B_U=$6;BASTION_KEY=$7;BASTION_KEY_ECDSA=${8};BASTION_KEY_RSA=${9}
            DAL_VAULT_KEY=${10}
            PATH_TO_PI=${11}
            ART_URL=${12};ART_USER=${13};ART_PASS=${14}
            IMG_TO_RUN_PATH=${15};IMG_TO_RUN_TAG=${16}

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
            validate_featureflag_genctl_cos_ffsld ${MZONE_NAME} ${PATH_TO_GENCTL_CI} \
            "${GIT_TOKEN}" ${FAIL_IF_ERROR} \
            ${BASTION_USERNAME} \
            "${DAL_VAULT_KEY}" ${PATH_TO_PI} \
            ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN}\
            ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
            set -x
        fi

    elif [[ ${MZONE_NAME} == rias* ]]; then
        # Get additional rias parameters
        IBM_CLOUD_KEY=$7

        echo "${MZONE_NAME} is a rias cluster"

        set +x # so we do not log the key
        validate_featureflag_rias_cos_ffsld ${MZONE_NAME} ${PATH_TO_GENCTL_CI} \
        "${GIT_TOKEN}" ${FAIL_IF_ERROR} \
        "${IBMCLOUD_KEY}"
        set -x
    else
        echo "${MZONE_NAME} does not match neither genctl nor rias, Exiting..."
        exit 1
    fi
}

function validate_featureflag_genctl() {
    # Validate featureflags for genctl
    # As described above, this executes a python script in Concourse, and also code in the deployer

    # Expected parameters:

    # First parameter are "shared" between genctl and rias

    # $1 --> The cluster to check
    # $2 --> Path to genctl-ci-repo
    # $3 --> The launch darkly feature flag
    # $4 --> The launch darkly environment
    # $5 --> Git token
    # $6 --> Fail if error

    # Genctl specific (Related to working through the deployer/running in a docker image on the deployer)

    # $7 --> Bastion Username (Used for creating a folder in the deployer)
    # $8 --> Dal vault key
    # $9 --> Path to platform inventory repo
    # $10 --> Artifactory URL
    # $11 --> Artifactory username
    # $12 --> Artifactory password
    # $13 --> Img to run path
    # $14 --> Img to run tag

    # Put some friendly names
    CLUSTER_TO_CHECK=$1
    PATH_TO_GENCTL_CI=$2
    LAUNCH_DARKLY_FEATURE_FLAG=$3;LAUNCH_DARKLY_ENVIRONMENT=$4
    GIT_TOKEN=$5
    FAIL_IF_ERROR=$6
    B_U=$7
    DAL_VAULT_KEY=$8
    PATH_TO_PLATFORM_INVENTORY_REPO=$9
    ART_URL=${10};ART_USER=${11};ART_PASS=${12}
    IMG_TO_RUN_PATH=${13};IMG_TO_RUN_TAG=${14}


    # Set the path to the featureflags folder since is used
    PATH_TO_FEATURE_FLAGS_DIR="${PATH_TO_GENCTL_CI}/scripts/featureflags"

    set +x
    featureflag_status ${CLUSTER_TO_CHECK} ${PATH_TO_FEATURE_FLAGS_DIR} ${LAUNCH_DARKLY_FEATURE_FLAG} ${LAUNCH_DARKLY_ENVIRONMENT} "${GIT_TOKEN}"
    set -x

    # This is executed in Concourse and not in the deployer (The loop is a "retry" mechanism, since LD has sometimes timeout)
    for i in {1..5}; do
        python3 ${PATH_TO_GENCTL_CI}/scripts/featureflags/featureflags.py ${LAUNCH_DARKLY_FEATURE_FLAG} get_desired_deployments_file ${LAUNCH_DARKLY_ENVIRONMENT} ${CLUSTER_TO_CHECK} && break || sleep 1
    done

    MZONE_NAME=${CLUSTER_TO_CHECK}

    # Create the working directory in the deployer
    create_workdir_in_deployer ${MZONE_NAME} ${B_U}

    # Setup that allows us to run code in the deployer inside a docker container
    set +x
    setup_deployer_for_ci_work ${PATH_TO_GENCTL_CI} ${ART_URL} ${ART_USER} ${ART_PASS} ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
    set -x

    # Setup that allows us to run kubectl commands against genctl cluster
    set +x
    setup_deployer_for_work_against_mzone ${MZONE_NAME} ${PATH_TO_GENCTL_CI} ${PATH_TO_PLATFORM_INVENTORY_REPO} "${DAL_VAULT_KEY}"
    set -x

    # Copy desired_deployments to deployer
    rsync -aq --delete -e "ssh ${SSH_CONFIG_PARAMS}" ./desired_deployment_versions.json ${DEPLOY_SERVER_TARGET}:${MZONE_DIR}/desired_deployment_versions.json
    
    # We need to extract these base names because in concourse the end paths are different
    # i.e genctl-ci-repo vs one-pipeline-config-repo
    PATH_ON_DEPLOYER_GENCTL_CI=$(basename "$PATH_TO_GENCTL_CI")

    COMMAND_INSIDE_CONTAINER="
    if [ ${FAIL_IF_ERROR} == \"true\" ]
    then
        set -e
    fi
    export KUBECONFIG=${MZONE_DIR}/${MZONE_NAME}.conf
    . ${MZONE_DIR}/repos/${PATH_ON_DEPLOYER_GENCTL_CI}/scripts/validate_featureflag_utils.sh
    python3 -m pip install -q -r ${MZONE_DIR}/repos/${PATH_ON_DEPLOYER_GENCTL_CI}/scripts/featureflags/requirements.txt
    python3 ${MZONE_DIR}/repos/${PATH_ON_DEPLOYER_GENCTL_CI}/scripts/featureflags/featureflags.py ${LAUNCH_DARKLY_FEATURE_FLAG} validate_promotion_by_ld_with_file ${MZONE_DIR}/desired_deployment_versions.json genctl
    validate_promotion_file ${CLUSTER_TO_CHECK} ${LAUNCH_DARKLY_FEATURE_FLAG} ./validate_promotion.txt ${FAIL_IF_ERROR}
    "

    set +x
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "
    docker run --rm --name=validate_featureflag_${MZONE_NAME}_\$(date -u +%s) --network host -v ${MZONE_DIR}:${MZONE_DIR} ${IMG_TO_RUN} /bin/bash -c \" ${COMMAND_INSIDE_CONTAINER}  \"
    "
    set -x

}

function validate_featureflag_genctl_cos_ffsld() {
    # Validate featureflags for genctl
    # As described above, this executes a python script in Concourse, and also code in the deployer

    # Expected parameters:

    # First parameter are "shared" between genctl and rias

    # $1 --> The cluster to check
    # $2 --> Path to genctl-ci-repo
    # $3 --> Git token
    # $4 --> Fail if error

    # Genctl specific (Related to working through the deployer/running in a docker image on the deployer)

    # $5 --> Bastion Username (Used for creating a folder in the deployer)
    # $6 --> Dal vault key
    # $7 --> Path to platform inventory repo
    # $8 --> Artifactory URL
    # $9 --> Artifactory username
    # $10 --> Artifactory password
    # $11 --> Img to run path
    # $12 --> Img to run tag


    # Put some friendly names
    CLUSTER_TO_CHECK=$1
    PATH_TO_GENCTL_CI=$2
    GIT_TOKEN=$3
    FAIL_IF_ERROR=$4
    B_U=$5
    DAL_VAULT_KEY=$6
    PATH_TO_PLATFORM_INVENTORY_REPO=$7
    ART_URL=${8};ART_USER=${9};ART_PASS=${10}
    IMG_TO_RUN_PATH=${11};IMG_TO_RUN_TAG=${12}

    # Set the path to the featureflags folder since is used
    PATH_TO_FEATURE_FLAGS_DIR="${PATH_TO_GENCTL_CI}/scripts/featureflags"

    export GENCTL_FFSLD_FILE_PATH=${PATH_TO_WORKSPACE_REPO}/FFSLD_ARTIFACTS/ffsld/genctl/${CLUSTER_TO_CHECK}/featureflagsetld.yaml

    python3 ${PATH_TO_GENCTL_CI}/scripts/convert_ffsld_yaml_to_json.py -f ${GENCTL_FFSLD_FILE_PATH}
    FEATURE_FLAG_TAG=$(jq -r ".\"${LAUNCH_DARKLY_FEATURE_FLAG}\"" desired_deployment_versions.json)

    set +x
    featureflag_status_cos_ffsld ${CLUSTER_TO_CHECK} ${PATH_TO_FEATURE_FLAGS_DIR} ${LAUNCH_DARKLY_FEATURE_FLAG} "${FEATURE_FLAG_TAG}" "${GIT_TOKEN}" "${ORG_AND_REPO}"
    set -x

    MZONE_NAME=${CLUSTER_TO_CHECK}

    # Create the working directory in the deployer
    create_workdir_in_deployer ${MZONE_NAME} ${B_U}

    # Setup that allows us to run code in the deployer inside a docker container
    set +x
    setup_deployer_for_ci_work ${PATH_TO_GENCTL_CI} ${ART_URL} ${ART_USER} ${ART_PASS} ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
    set -x

    # Setup that allows us to run kubectl commands against genctl cluster
    set +x
    setup_deployer_for_work_against_mzone ${MZONE_NAME} ${PATH_TO_GENCTL_CI} ${PATH_TO_PLATFORM_INVENTORY_REPO} "${DAL_VAULT_KEY}"
    set -x

    # Copy desired_deployments to deployer
    rsync -aq --delete -e "ssh ${SSH_CONFIG_PARAMS}" ./desired_deployment_versions.json ${DEPLOY_SERVER_TARGET}:${MZONE_DIR}/desired_deployment_versions.json

    # We need to extract these base names because in concourse the end paths are different
    # i.e genctl-ci-repo vs one-pipeline-config-repo
    PATH_ON_DEPLOYER_GENCTL_CI=$(basename "$PATH_TO_GENCTL_CI")

    COMMAND_INSIDE_CONTAINER="
    if [ ${FAIL_IF_ERROR} == \"true\" ]
    then
        set -e
    fi
    export KUBECONFIG=${MZONE_DIR}/${MZONE_NAME}.conf
    . ${MZONE_DIR}/repos/${PATH_ON_DEPLOYER_GENCTL_CI}/scripts/validate_featureflag_utils.sh
    python3 -m pip install -q -r ${MZONE_DIR}/repos/${PATH_ON_DEPLOYER_GENCTL_CI}/scripts/featureflags/requirements.txt
    python3 ${MZONE_DIR}/repos/${PATH_ON_DEPLOYER_GENCTL_CI}/scripts/featureflags/featureflags_cos_ffsld.py ${LAUNCH_DARKLY_FEATURE_FLAG} validate_promotion_by_ld_with_file ${MZONE_DIR}/desired_deployment_versions.json genctl
    validate_promotion_file ${CLUSTER_TO_CHECK} ${LAUNCH_DARKLY_FEATURE_FLAG} ./validate_promotion.txt ${FAIL_IF_ERROR}
    "

    set +x
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "
    docker run --rm --name=validate_featureflag_${MZONE_NAME}_\$(date -u +%s) --network host -v ${MZONE_DIR}:${MZONE_DIR} ${IMG_TO_RUN} /bin/bash -c \" ${COMMAND_INSIDE_CONTAINER}  \"
    "
    set -x

}


function validate_featureflag_rias() {
    # Validates rias

    # Expected parameters:

    # First parameter are "shared" between genctl and rias

    # $1 --> The cluster to check
    # $2 --> Path to genctl-ci-repo
    # $3 --> The launch darkly feature flag
    # $4 --> The launch darkly environment
    # $5 --> Git token
    # $6 --> Fail if error

    # Rias specific

    # $7 --> The IBM CLOUD KEY

    # Put some friendly names
    CLUSTER_TO_CHECK=$1
    PATH_TO_GENCTL_CI=$2
    LAUNCH_DARKLY_FEATURE_FLAG=$3;LAUNCH_DARKLY_ENVIRONMENT=$4
    GIT_TOKEN=$5
    FAIL_IF_ERROR=$6
    IBM_CLOUD_KEY=$7


    # Set the path to the featureflags folder since is used
    PATH_TO_FEATURE_FLAGS_DIR="${PATH_TO_GENCTL_CI}/scripts/featureflags"

    set +x
    featureflag_status ${CLUSTER_TO_CHECK} ${PATH_TO_FEATURE_FLAGS_DIR} ${LAUNCH_DARKLY_FEATURE_FLAG} ${LAUNCH_DARKLY_ENVIRONMENT} "${GIT_TOKEN}"
    set -x

    set +x
    # Login to ibmcloud using function defined in ibmcloud_utils.sh
    ibmcloud_login "${IBM_CLOUD_KEY}"
    get_iks_cluster_config ${CLUSTER_TO_CHECK}
    set -x

    # In contrast to what we do in genctl, for rias, we do the retrieving from LD and retrieve from cluster in one python execution
    for i in {1..5}; do
        python3 ${PATH_TO_FEATURE_FLAGS_DIR}/featureflags.py ${LAUNCH_DARKLY_FEATURE_FLAG} validate_promotion_by_ld ${LAUNCH_DARKLY_ENVIRONMENT} ${CLUSTER_TO_CHECK} "rias" && break || sleep 1
    done

    validate_promotion_file "${CLUSTER_TO_CHECK}" "${LAUNCH_DARKLY_FEATURE_FLAG}" "validate_promotion.txt" ${FAIL_IF_ERROR}

    if [[ ${CLUSTER_TO_CHECK} == *etcd ]]; then
        for i in {1..5}; do
            python3 ${PATH_TO_FEATURE_FLAGS_DIR}/featureflags.py ${LAUNCH_DARKLY_FEATURE_FLAG} validate_promotion_by_ld ${LAUNCH_DARKLY_ENVIRONMENT} ${CLUSTER_TO_CHECK} "rias-etcd" && break || sleep 1
        done

        validate_promotion_file "${CLUSTER_TO_CHECK}" "${LAUNCH_DARKLY_FEATURE_FLAG}" "validate_promotion.txt" ${FAIL_IF_ERROR}
    fi
}


function validate_featureflag_rias_cos_ffsld() {
    # Validates rias

    # Expected parameters:

    # First parameter are "shared" between genctl and rias

    # $1 --> The cluster to check
    # $2 --> Path to genctl-ci-repo
    # $3 --> Git token
    # $4 --> Fail if error

    # Rias specific

    # $5 --> The IBM CLOUD KEY

    # Put some friendly names
    CLUSTER_TO_CHECK=$1
    PATH_TO_GENCTL_CI=$2
    GIT_TOKEN=$3
    FAIL_IF_ERROR=$4
    IBM_CLOUD_KEY=$5


    # Set the path to the featureflags folder since is used
    PATH_TO_FEATURE_FLAGS_DIR="${PATH_TO_GENCTL_CI}/scripts/featureflags"


    # In contrast to what we do in genctl, for rias, we do the retrieving from LD and retrieve from cluster in one python execution
    export RIAS_FFSLD_FILE_PATH=${PATH_TO_WORKSPACE_REPO}/FFSLD_ARTIFACTS/ffsld/rias/${CLUSTER_TO_CHECK}/featureflagsetld.yaml

    python3 ${PATH_TO_GENCTL_CI}/scripts/convert_ffsld_yaml_to_json.py -f ${RIAS_FFSLD_FILE_PATH}
    FEATURE_FLAG_TAG=$(jq -r ".\"${LAUNCH_DARKLY_FEATURE_FLAG}\"" desired_deployment_versions.json)

    set +x
    featureflag_status_cos_ffsld ${CLUSTER_TO_CHECK} ${PATH_TO_FEATURE_FLAGS_DIR} ${LAUNCH_DARKLY_FEATURE_FLAG} "${FEATURE_FLAG_TAG}" "${GIT_TOKEN}" "${ORG_AND_REPO}"
    set -x

    python3 ${PATH_TO_GENCTL_CI}/scripts/featureflags/featureflags_cos_ffsld.py ${LAUNCH_DARKLY_FEATURE_FLAG} validate_promotion_by_ld_with_file ./desired_deployment_versions.json rias
    validate_promotion_file "${CLUSTER_TO_CHECK}" "${LAUNCH_DARKLY_FEATURE_FLAG}" "validate_promotion.txt" ${FAIL_IF_ERROR}


    set +x
    # Login to ibmcloud using function defined in ibmcloud_utils.sh
    ibmcloud_login "${IBM_CLOUD_KEY}"
    get_iks_cluster_config ${CLUSTER_TO_CHECK}
    set -x


    if [[ ${CLUSTER_TO_CHECK} == *etcd ]]; then

        export RIAS_ETCD_FFSLD_FILE_PATH=${PATH_TO_WORKSPACE_REPO}/FFSLD_ARTIFACTS/ffsld/rias-etcd/${CLUSTER_TO_CHECK}/featureflagsetld.yaml        
        python3 ${PATH_TO_GENCTL_CI}/scripts/convert_ffsld_yaml_to_json.py -f ${RIAS_ETCD_FFSLD_FILE_PATH}
        python3 ${PATH_TO_GENCTL_CI}/scripts/featureflags/featureflags_cos_ffsld.py ${LAUNCH_DARKLY_FEATURE_FLAG} validate_promotion_by_ld_with_file ./desired_deployment_versions.json rias-etcd
        validate_promotion_file "${CLUSTER_TO_CHECK}" "${LAUNCH_DARKLY_FEATURE_FLAG}" "validate_promotion.txt" ${FAIL_IF_ERROR}
    fi
}


### SHARED FUNCTIONS ###
# With the proper setup, these functions can be run in both situations:

# 1. In Concourse (when working against rias) or in a container
# 2. In a container inside the deployer (When working against genctl)

function featureflag_status(){
    # Expected parameters:

    # $1 --> The cluster to check
    # $2 --> The path to the feature flags directory
    # $3 --> The launch darkly feature flag
    # $4 --> The launch darkly environment
    # $5 --> Git token

    # Put some friendly names

    CLUSTER_TO_CHECK=$1
    PATH_TO_FEATURE_FLAGS_DIR=$2
    LAUNCH_DARKLY_FEATURE_FLAG=$3
    LAUNCH_DARKLY_ENVIRONMENT=$4
    GIT_TOKEN=$5

    # Install python requirements
    python3 -m pip install -q -r ${PATH_TO_FEATURE_FLAGS_DIR}/requirements.txt

    # get the current active featureflag's default rule
    set +x # so we do not inadvertently log the git token
    export FEATUREFLAG_STATUS=$(python3 ${PATH_TO_FEATURE_FLAGS_DIR}/featureflags.py ${LAUNCH_DARKLY_FEATURE_FLAG} show_active_variation ${LAUNCH_DARKLY_ENVIRONMENT} ${CLUSTER_TO_CHECK} ${GIT_TOKEN} | grep 'SUCCESS')
    set -x
    echo "FEATUREFLAG_STATUS=${FEATUREFLAG_STATUS}"

    if [ -z "${FEATUREFLAG_STATUS}" ]; then
        echo "dev-integration branch HEAD for ${PIPELINE_REPO_NAME} is ahead of the Launch Darkly commit hash being served to your dev region. This can happen when the release step of your dev-integration merge pipeline hasn't ran yet for your branch HEAD commit."
        echo "Wait for your dev-integration merge pipeline to finish and try re-running this job in Concourse. In the future wait until your dev-integration merge pipeline is finished with latest commit, prior to creating a sync to master pull-request."
        if [ ${FAIL_IF_ERROR} == "true" ]
        then
            exit 1
        else
            echo "Validation got error, but since FAIL_IF_ERROR is not true, we are not failing"
        fi
    fi
}

function featureflag_status_cos_ffsld(){
    # Expected parameters:

    # $1 --> The cluster to check
    # $2 --> The path to the feature flags directory
    # $3 --> feature flag
    # $4 --> current variation
    # $5 --> Git token


    # Put some friendly names

    CLUSTER_TO_CHECK=$1
    PATH_TO_FEATURE_FLAGS_DIR=$2
    LAUNCH_DARKLY_FEATURE_FLAG=$3
    FEATURE_FLAG_CURRENT_VARIATION=$4
    GIT_TOKEN=$5
    ORG_AND_REPO=$6

    # Install python requirements
    python3 -m pip install -q -r ${PATH_TO_FEATURE_FLAGS_DIR}/requirements.txt

    # get the current active featureflag's default rule

    if [ -z "${GIT_TOKEN}" ]; then
        echo "Variable is null or empty"
    fi

    set +x # so we do not inadvertently log the git token
    export FEATUREFLAG_STATUS=$(python3 ${PATH_TO_FEATURE_FLAGS_DIR}/featureflags_cos_ffsld.py ${CLUSTER_TO_CHECK} show_active_variation_cos_ffsld ${LAUNCH_DARKLY_FEATURE_FLAG} "${FEATURE_FLAG_CURRENT_VARIATION}" ${GIT_TOKEN} ${ORG_AND_REPO}| grep 'SUCCESS')
    set -x

    echo "FEATUREFLAG_STATUS=${FEATUREFLAG_STATUS}"

    if [ -z "${FEATUREFLAG_STATUS}" ]; then
        echo "dev-integration branch HEAD for ${PIPELINE_REPO_NAME} is ahead of the Launch Darkly commit hash being served to your dev region. This can happen when the release step of your dev-integration merge pipeline hasn't ran yet for your branch HEAD commit."
        echo "Wait for your dev-integration merge pipeline to finish and try re-running this job in Concourse. In the future wait until your dev-integration merge pipeline is finished with latest commit, prior to creating a sync to master pull-request."
        if [ ${FAIL_IF_ERROR} == "true" ]
        then
            exit 1
        else
            echo "Validation got error, but since FAIL_IF_ERROR is not true, we are not failing"
        fi
    fi
}

function validate_promotion_file() {
    # Validates the promotion file that was previously generated

    # Expected parameters:

    # $1 --> The cluster to check (Used only for logging purposes)
    # $2 --> The launch darkly feature flag
    # $3 --> The path to the promotion file

    # Put some friendly names
    CLUSTER_TO_CHECK=$1
    LAUNCH_DARKLY_FEATURE_FLAG=$2
    PATH_TO_PROMOTION_FILE=$3
    FAIL_IF_ERROR=$4
    set +x
    NOT_OKAY_DEPLOYMENTS=$(cat ${PATH_TO_PROMOTION_FILE} | grep NOT-OK || true )
    rc=$?
    echo "RC=$rc"
    echo "cleaning up ${PATH_TO_PROMOTION_FILE} report"
    rm ${PATH_TO_PROMOTION_FILE}
    if [ -z "${NOT_OKAY_DEPLOYMENTS}" ]; then
        echo "tests are ready to run"
    else
        echo "-------------------------------------------------------- NOT_OKAY_DEPLOYMENTS: ------------------------------------------------------"
        echo "     feature-flag                    desired-version                           current-versions                          status      "
        echo "${NOT_OKAY_DEPLOYMENTS}"
        echo "-------------------------------------------------------------------------------------------------------------------------------------"
        echo "Check for errors in your environment. "
        if [ ${FAIL_IF_ERROR} == "true" ]
        then
            exit 1
        else
            echo "Validation got error, but since FAIL_IF_ERROR is not true, we are not failing"
        fi
    fi
    set -x
}
