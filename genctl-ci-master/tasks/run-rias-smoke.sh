#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2019-2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# The following environment variables need to be set before executing the script:
#PATH_TO_GENCTL_CI
#PATH_TO_WORKSPACE_REPO
#PATH_TO_VETTED_VERSIONS_REPO
#VETTED_VERSION_REPO_UPDATED  (optional, used in a razee hotfix pipeline)
#PATH_TO_RIAS_GLOBALS_REPO

# ARTIFACTORY_DOCKER_PROD_URL:
# GENCTL_VETTED_VERSIONS:
# VETTED_VERSIONS_DEFAULT: (default: pre-integration.yaml)
# GIT_PRIVATE_KEY: (e.g. ghe-private-key)
# VAULT_GIT_CONFIG_USER_EMAIL:
# VAULT_GIT_CONFIG_USERNAME:
# GLOBAL_TEST_CONFIG: (default: tests/qa/cpap/suites/rias_no_cos.ini)
# GLOBAL_META_PURPOSES: (default: smoke)
# MODE:
# SMOTAINER_INTEGRATION_BRANCH:
# SECRET_MANAGER_KEY_CSI: (e.g. secret-manager-api-key-csi)
# CC_ARTIF_ACCESS_TOKEN: (e.g. wcp-genctl-docker-local-artifactory-token)
# WCP_ARTIFACTORY_USERNAME: (e.g. wcp-genctl-docker-local-artifactory-username)
# WS_PATH: (default: workspace-path-placeholder)
# SUPPORTTED_HOSTOS_VERSIONS: (e.g. supported-hostos-release-bundles-z)
# SKIP_SMOKE_TESTS: (default: false)

# Set flags
set -eu
# Set default values
export VETTED_VERSIONS_DEFAULT=${VETTED_VERSIONS_DEFAULT:-"pre-integration.yaml"}
export GLOBAL_META_PURPOSES=${GLOBAL_META_PURPOSES:-"smoke"}
export GLOBAL_TEST_CONFIG=${GLOBAL_TEST_CONFIG:-"tests/qa/cpap/suites/rias_no_cos.ini"}
export SKIP_SMOKE_TESTS=${SKIP_SMOKE_TESTS:-"false"}
export GENCTL_VETTED_VERSIONS=${GENCTL_VETTED_VERSIONS:-""}
export ARTIFACTORY_DOCKER_PROD_URL=${ARTIFACTORY_DOCKER_PROD_URL:-""}
export VAULT_GIT_CONFIG_USER_EMAIL=${VAULT_GIT_CONFIG_USER_EMAIL:-""}
export VAULT_GIT_CONFIG_USERNAME=${VAULT_GIT_CONFIG_USERNAME:-""}
export SMOTAINER_INTEGRATION_BRANCH=${SMOTAINER_INTEGRATION_BRANCH:-""}
export MODE=${MODE:-""}
export WS_PATH=${WS_PATH:-"workspace-path-placeholder"}

if [[ "${SKIP_SMOKE_TESTS}" == "true" ]]; then
    exit 0
fi
if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
    echo "1PL Claimed mzone $CLAIM_MZONE_RESULT"
    export MZONE_NAME=${CLAIM_MZONE_RESULT}
else
    #Check if mzone_name env file exists if does , save the value as MZONE_NAME
    if [[ -d "$MZONE_NAME" ]]
    then
        if [[ -e $MZONE_NAME/pr.sh ]]; then
        source "$MZONE_NAME/pr.sh"
        MZONE_NAME=$MZONE_NAME
        fi
    else
        export MZONE_NAME=`cat $PATH_TO_RESOURCELOCK_REPO/metadata`
    fi

    if [[ -z "$MZONE_NAME" ]]; then
        . ${PATH_TO_GENCTL_CI}/scripts/rebase_and_retrieve_metadata.sh
        pushd $PATH_TO_RESOURCELOCK_REPO
        initGit
        rebase
        popd
        getPipelineDetails
        getMzone
        MZONE_NAME=$mzoneName
    fi
fi

case "$MZONE_NAME" in
mzone7215)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev05-etcd"
    APIKEY_ALIAS=nonprod023
    RIAS_GLOBAL_FOLDER=cicd
    ;;
mzone7286)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev06-etcd"
    APIKEY_ALIAS=nonprod024
    RIAS_GLOBAL_FOLDER=dev-szr
    ;;
mzone7287)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev07-etcd"
    APIKEY_ALIAS=nonprod025
    RIAS_GLOBAL_FOLDER=dev-szr
    ;;
mzone7288)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev08-etcd"
    APIKEY_ALIAS=nonprod033
    RIAS_GLOBAL_FOLDER=dev-szr
    ;;
mzone7301)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev24-etcd"
    APIKEY_ALIAS=cicd-mz2308
    RIAS_GLOBAL_FOLDER=dev-szr
    ;;
mzone7302)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev25-etcd"
    APIKEY_ALIAS=cicd-mz2309
    RIAS_GLOBAL_FOLDER=dev-szr
    ;;
*)
    echo "${MZONE_NAME} is not supported for rias smoke"
    exit 1
    ;;
esac

# TODO: remove $KEYS_DIR once smotainer stops requiring it
KEYS_DIR=/tmp/keys
mkdir -p ${KEYS_DIR}

#########################################     SMOKE     #########################################
set +x
template_data=$(yq -r '.spec.strTemplates[]' "${PATH_TO_RIAS_GLOBALS_REPO}/${RIAS_GLOBAL_FOLDER}/${IBMCLOUD_IKS_CLUSTER_NAME}.yaml")
PUBLIC_IP=$(echo "${template_data}" | yq -r '.data.ingress' | jq -r '.hosts[0]')
set -x
echo "PUBLIC IP: ${PUBLIC_IP}"
VETTED_VERSIONS_YAML=${PATH_TO_VETTED_VERSIONS_REPO}/${VETTED_VERSIONS_DEFAULT}

OUTPUT_DIR=$(pwd)/smoke-output
mkdir -p ${OUTPUT_DIR}

VAULT_CERT_DIR=$(pwd)/vaultcerts
mkdir -p ${VAULT_CERT_DIR}


set +x  # so we don't log the password
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_PROD_URL} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
set -x

SMOTAINER_IMAGE_PATH=qa-test/smotainer-${SMOTAINER_INTEGRATION_BRANCH}
if [ "${MODE}" = "local-build" ];  then
    eval "$(ssh-agent -s)"
    ssh-add - <<< "${GIT_PRIVATE_KEY}"
    mkdir -p ~/.ssh
    ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts

    pushd ${PATH_TO_INTEGRATION_TESTING_REPO}
    SMOTAINER_IMAGE_TAG=$(git rev-parse --verify HEAD)
    echo SMOTAINER_IMAGE_TAG: ${SMOTAINER_IMAGE_TAG}
    popd
else
    SMOTAINER_IMAGE_TAG=`yq -r '.version."smotainer-release" | select(. != null)' ${PATH_TO_VETTED_VERSIONS_REPO}/${GENCTL_VETTED_VERSIONS}`
    echo SMOTAINER_IMAGE_TAG: ${SMOTAINER_IMAGE_TAG} from ${PATH_TO_VETTED_VERSIONS_REPO}/${GENCTL_VETTED_VERSIONS}
    VETTED_VERSIONS_YAML=${PATH_TO_VETTED_VERSIONS_REPO}/${GENCTL_VETTED_VERSIONS}
fi
if [[ -z ${SMOTAINER_IMAGE_TAG} ]]; then
    SMOTAINER_IMAGE_TAG=`yq -r '.version."smotainer-release"' ${PATH_TO_VETTED_VERSIONS_REPO}/${VETTED_VERSIONS_DEFAULT}`
    echo SMOTAINER_IMAGE_TAG: ${SMOTAINER_IMAGE_TAG} from ${PATH_TO_VETTED_VERSIONS_REPO}/${VETTED_VERSIONS_DEFAULT}
fi

# pull smotainer image
docker pull ${ARTIFACTORY_DOCKER_PROD_URL}/${SMOTAINER_IMAGE_PATH}:${SMOTAINER_IMAGE_TAG}

# if PATH_TO_WORKSPACE_REPO is passed in, volume mount it to the smotainer; else, unset WS_PATH and don't volume mount
if [ -d $WS_PATH ]; then
    ws_volume_mount="-v $(pwd)/${WS_PATH}:/root/genctl/integration-testing/${WS_PATH}"
else
    # Unset WS_PATH so that build_functional_tests.py skips checking for user configured tests
    unset WS_PATH
    ws_volume_mount=""
fi

# Run build_functional_tests.py to generate test runs json config
export OUTPUT=test_executions.json
python3 ${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/build_functional_tests.py

# loop through global test config and user defined tests generated by build_functional_tests.py
for test_execution in $(cat ${OUTPUT} | jq -c '.[]'); do
    path=$(echo ${test_execution} | jq -r '.path')
    meta_purposes=$(echo ${test_execution} | jq -r '.meta_purposes')

    echo "Running tests ${path}"

    # cleanup volumes from previous smoke run
    docker run --rm --name=smotainer_$(date -u +%s) \
        --net=host \
        -v ${KEYS_DIR}:/root/.ssh \
        -v ${VAULT_CERT_DIR}:/vaultcerts \
        -v ${OUTPUT_DIR}:/output \
        ${ARTIFACTORY_DOCKER_PROD_URL}/${SMOTAINER_IMAGE_PATH}:${SMOTAINER_IMAGE_TAG} \
        python3 tools/python/pipeline_tools/rias_pipeline_cleanup.py \
            -v \
            -i ${PUBLIC_IP} \
            -vc /vaultcerts/vault-td-smotainer-cert.crt \
            --apikey ${APIKEY_ALIAS} \
            -nf "" \
            --all

    # generate a meta flags string that contains a flag for each meta_purpose
    base_meta_flag="-M environment=development"
    test_type=""
    if [ "${meta_purposes}" != "[]" ]; then
        meta_flags=""
        for meta_purpose in $(echo ${meta_purposes} | jq -c '.[]'); do
            meta_flags+="${base_meta_flag},purpose=$(echo ${meta_purpose} | tr -d '"') "
            test_type+="$(echo ${meta_purpose} | tr -d '"'),"
        done
    else
        meta_flags=$base_meta_flag
    fi
    # Remove the ending comma
    test_type=${test_type%?}

    export TIMESTAMP=$(date +"%Y%m%d-%H-%M-%S")

    # Check if has z node
    has_z=false
    hasSSCZ=false
    hasLinuxZ=false

    if [ ".{VETTED_VERSIONS_YAML}" != "." -a -f ${VETTED_VERSIONS_YAML} ]; then
        for bundle in hostos-boot-release \
            hostos-config-release \
            hostos-base-os-sw-release \
            hostos-base-net-sw-release \
            hostos-nextgen-os-sw-release \
            hostos-kernel-patch-release;
        do
            _version=$(grep ${bundle} ${VETTED_VERSIONS_YAML} 2>/dev/null | awk -F'[:]+' '{print $2}' | awk -F'[.]+' '{print $1}' | sed 's/^[ \t]*//g')
            for ver in ${SUPPORTTED_HOSTOS_VERSIONS}; do
                if [ "${ver}" == "${_version}" ]; then
                    has_z=true
                    break
                else
                    has_z=false
                fi
            done
            [ "${has_z}" == "true" ] && break
        done
    fi

    # If has z node, check z node type and run z smoke
    if [ "${has_z}" == "true" ] \
        && [ -f ${PATH_TO_PLATFORM_INVENTORY_REPO}/region/${MZONE_NAME}.yml ]; then
        index=0
        hostip_list=$(yq '.compute_node[].hostIP' ${PATH_TO_PLATFORM_INVENTORY_REPO}/region/${MZONE_NAME}.yml)
        hostip_array=(${hostip_list})
        ipmi_list=$(yq '.compute_node[].ipmi' ${PATH_TO_PLATFORM_INVENTORY_REPO}/region/${MZONE_NAME}.yml)
        ipmi_array=(${ipmi_list})
        arch_list=$(yq '.compute_node[].arch' ${PATH_TO_PLATFORM_INVENTORY_REPO}/region/${MZONE_NAME}.yml)

        for arch in ${arch_list};
        do
            arch=$(echo ${arch} | tr -d '"')
            if [ "${arch}" == "s390x" ]; then
                hostname=$(echo ${hostname_array[${index}]} | tr -d '"')
                hostip=$(echo ${hostip_array[${index}]} | tr -d '"')
                ipmiip=$(echo ${ipmi_array[${index}]} | tr -d '"')
                if [ "${hostip}" != "" -a "${ipmiip}" != "" -a \
                    "$(echo ${hostip} | grep -oE '[0-9]+' | awk 'NR==3')" == \
                    "$(echo ${ipmiip} | grep -oE '[0-9]+' | awk 'NR==3')" ]; then
                    hasSSCZ=true
                else
                    hasLinuxZ=true
                fi
            fi
            index=$(expr ${index} + 1)
        done

        if (${hasSSCZ} && [[ "${_version}" == "2" || "${_version}" == "3" ]]) \
            || (${hasLinuxZ} && [[ "${_version}" != "2" && "${_version}" != "3" ]]); then
            meta_flags+="-M environment=development,purpose=z-smoke --tc=use_z:True "
            test_type+=",z-smoke"
        fi
    fi
    
    echo "Execute RIAS_VPCTest to create zone-mapping"
    # running the RIAS_VPCTest in another smotainer to create a VPC in trun map a zone to the said APIKEY_ALIAS account. 
    docker run --name=smotainer_$(date -u +%s) \
        --net=host \
        -v ${KEYS_DIR}:/root/.ssh \
        -v ${OUTPUT_DIR}:/output \
        -e SECRET_MANAGER_KEY="${SECRET_MANAGER_KEY_CSI}" \
        ${ARTIFACTORY_DOCKER_PROD_URL}/${SMOTAINER_IMAGE_PATH}:${SMOTAINER_IMAGE_TAG} \
        python3 QA/lib/framework/cpap/launcher.py \
            -v tests/qa/cpap/rias/infrastructure/tests/RIAS_VPCTest.py:RIAS_VPCTest.test_create_vpc \
            --tc=public_ip:${PUBLIC_IP} \
            --tc=port:443 \
            --tc=secure:True --tc=apikey:${APIKEY_ALIAS} \
            --out-dir=/output \
            --save-artifacts

    # run smoke tests
    echo "Execute Smoke Tests"
    docker run --name=smotainer_$(date -u +%s) \
        --net=host \
        -v ${KEYS_DIR}:/root/.ssh \
        -v ${OUTPUT_DIR}:/output \
        -e SECRET_MANAGER_KEY="${SECRET_MANAGER_KEY_CSI}" \
        ${ws_volume_mount} \
        ${ARTIFACTORY_DOCKER_PROD_URL}/${SMOTAINER_IMAGE_PATH}:${SMOTAINER_IMAGE_TAG} \
        python3 QA/lib/framework/cpap/launcher.py \
            -v \
            --tc=public_ip:${PUBLIC_IP} \
            --tc=port:443 \
            --tc=secure:True --tc=apikey:${APIKEY_ALIAS} \
            -N 4 \
            --out-dir=/output \
            -S ${path} \
            --abf-enable \
            --report-rules-eng \
            --group-set=${MZONE_NAME} \
            --test-plan=${test_type} \
            --save-artifacts \
            --test-run=RIAS_${MZONE_NAME}_${TIMESTAMP} \
            ${meta_flags}

done

