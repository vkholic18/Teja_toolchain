#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script builds the rias-release and the rias-etcd-release bundles and pushes them to artifactory

set -exuc
export RESULT_DEV_INT_SHA=${RESULT_DEV_INT_SHA:-""}
export VETTED_VERSIONS_DEFAULT=${VETTED_VERSIONS_DEFAULT:-"pre-integration.yaml"}
export HOTFIX=${HOTFIX:-"false"}
# BOTH DEPLOY_PACKAGE_ONLY AND DEPLOY_COMPONENT_ONLY CAN ONLY BE SET TO TRUE IF THE PACKAGE IS PART OF THE COMPONENT
export RAZEE_HOTFIX_ON_DEPLOY_NEXT_GENERATION=${RAZEE_HOTFIX_ON_DEPLOY_NEXT_GENERATION:-""}
export DEPLOY_PACKAGE_ONLY=${DEPLOY_PACKAGE_ONLY:-"false"}
export DEPLOY_COMPONENT_ONLY=${DEPLOY_COMPONENT_ONLY:-"false"}
export VETTED_VERSIONS_VALIDATION_MODE=${VETTED_VERSIONS_VALIDATION_MODE:-"soft"}
export VV_REPO_PATH=${VV_REPO_PATH:-"./vetted-versions-repo"}
export IS_OVERRIDE_GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION=${IS_OVERRIDE_GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION:-"false"}
export OVERRIDE_GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION=${OVERRIDE_GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION:-""}
export EXPLICIT_USE_MZONE=${EXPLICIT_USE_MZONE:-""}
export SKIP_DEPLOY_DAL=${SKIP_DEPLOY_DAL:-"false"}
export IS_ONE_PIPELINE_RUN=${IS_ONE_PIPELINE_RUN:-"false"}
export LABEL_TO_SEARCH=${LABEL_TO_SEARCH:-""}
export REPOSITORY_NAME=${REPOSITORY_NAME:-""}
export LAUNCH_DARKLY_DEFAULT_URL=${LAUNCH_DARKLY_DEFAULT_URL:-""}
export RAZEE_HOTFIX_NEXTGEN_ENVIRONMENT_FILE=${RAZEE_HOTFIX_NEXTGEN_ENVIRONMENT_FILE:-""}
####################  WORKSPACE_REPO_NAME  #################
# WORKSPACE_REPO_NAME is used to check if it also shared component on rias release
# if shared deploy-rias.sh deploy the custom rias release bundle
# if not shared deploy-rias.sh deploy the rias release bundle from vetted version
export WORKSPACE_REPO_NAME=${WORKSPACE_REPO_NAME:-""}
export HOTFIX_MAJOR_COMPONENT=${HOTFIX_MAJOR_COMPONENT:-""}
export PACKAGE=${PACKAGE:-""}
####################  RIAS_DEPLOY_COMPONENT_TYPE [ rias | kube | hostos | genctl ]  #################
# defines which rias release bundle to deploy
# if rias: use custom release bundle
# if genctl use custom release bundle if this component shared on rias release
# if other use last rias release from vetted version
export RIAS_DEPLOY_COMPONENT_TYPE=${RIAS_DEPLOY_COMPONENT_TYPE:-""}
####################  COMPONENT [ rias | genctl ]  ##################
# if COMPONENT = comp update release tag and indicate it as in local registry
export COMPONENT=${COMPONENT:-""}
################## DDT nextgen environments repo #####################
export ENV_REPO_ORG=${ENV_REPO_ORG:-""}
export ENV_REPO_REF=${ENV_REPO_REF:-""}
export GENCTL_VETTED_VERSIONS=${GENCTL_VETTED_VERSIONS:-""}
export GITHUB_API_URL=${GITHUB_API_URL:-""}
export GHE_API_URL=${GHE_API_URL:-""}
export GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION=${GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION:-""}
#################### for rollback CI cluster to default rules
export LAUNCH_DARKLY_ENVIRONMENT=${LAUNCH_DARKLY_ENVIRONMENT:-""}
export DDT_CONFIG_TEMPLATE=${DDT_CONFIG_TEMPLATE:-""}
export VAULT_GIT_CONFIG_USER_EMAIL=${VAULT_GIT_CONFIG_USER_EMAIL:-""}
export VAULT_GIT_CONFIG_USERNAME=${VAULT_GIT_CONFIG_USERNAME:-""}
# VETTED_VERSIONS_OVERRIDE is to use a specific vetted versions file, and merge it with the default to produce a full/usable vetted versions file
export VETTED_VERSIONS_OVERRIDE=${VETTED_VERSIONS_OVERRIDE:-""}
export ARTIFACTORY_DOCKER_STAGING_URL=${ARTIFACTORY_DOCKER_STAGING_URL:-""}
export ARTIFACTORY_DOCKER_PROD_URL=${ARTIFACTORY_DOCKER_PROD_URL:-""}

if [[ "${SKIP_DEPLOY_DAL}" == "true" ]]; then
    exit 0
fi
source $PATH_TO_GENCTL_CI/scripts/retry.sh

if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
    if [[ ! -z "${EXPLICIT_USE_MZONE}" ]]
    then
        # No need to work with the queue
        echo "It was explicitly required to use Mzone: ${EXPLICIT_USE_MZONE}"
        export MZONE_NAME=${EXPLICIT_USE_MZONE}
    else
        echo "1PL Claimed mzone $CLAIM_MZONE_RESULT"
        export MZONE_NAME=${CLAIM_MZONE_RESULT}
    fi
else
    #Check if mzone_name env file exists if does , save the value of MZONE_NAME as EXPLICIT_USE_MZONE
    if [[ -d $PATH_TO_MZONE_NAME ]]; then
        if [[ -e $PATH_TO_MZONE_NAME/pr.sh ]]; then
            source $PATH_TO_MZONE_NAME/pr.sh
            EXPLICIT_USE_MZONE=$MZONE_NAME
        fi
    fi


    source $PATH_TO_GENCTL_CI/scripts/rebase_and_retrieve_metadata.sh
    # Verify if there is an explicit mzone that we want to use
    if [[ ! -z "${EXPLICIT_USE_MZONE}" ]]
    then
        # No need to work with the queue
        echo "It was explicitly required to use Mzone: ${EXPLICIT_USE_MZONE}"
        export MZONE_NAME=${EXPLICIT_USE_MZONE}
    else
    # Make usual logic with the queue
        echo "No explicit Mzone was set, checking in the queue..."
        pushd $PATH_TO_RESOURCELOCK_REPO
        initGit
        rebase
        popd
        getPipelineDetails
        getMzone
        export MZONE_NAME=$mzoneName
    fi
fi

# Source ssh utils
source $PATH_TO_GENCTL_CI/scripts/ssh_utils.sh

# Source deployer utils
source $PATH_TO_GENCTL_CI/scripts/deployer_utils.sh

# So we don't log any password
set +x

# Setup ssh to deployer
if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
    setup_ssh_to_deployer_one_pipeline ${MZONE_NAME} ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}"
else
    setup_ssh_to_deployer ${MZONE_NAME} ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}"
fi
# Delete all copied repos in mzone folder on the deployer at the end of deploy process
trap 'ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "rm -rf /home/${BASTION_USERNAME}/${MZONE_NAME}/repos/*"' EXIT

# Revert flag
set -x

set +x  # so we do not log the vault key
export VAULT_KEY="${DAL_VAULT_KEY}"
set -x
export VAULT_CACERT="$PATH_TO_GENCTL_CI/certificates/vault-dal-intermediary-ca.pem"

# Export vault related vars
export_vault_vars ${MZONE_NAME} "$PATH_TO_PLATFORM_INVENTORY_REPO"

# Override docker_registry from the dev undercloud file
DEV_UNDERCLOUD_FILE=$PATH_TO_PLATFORM_INVENTORY_REPO/region/undercloud/dal${REGIONDIGIT}-qz2-undercloud.yml
if [ -f "$DEV_UNDERCLOUD_FILE" ]; then
    export REG_URL_PREFIX=$(yq -r ".services.docker_registry.addresses[]" ${DEV_UNDERCLOUD_FILE})
    echo "*****************"
    echo "* ++NOTE++ We are overriding the docker registry value in the ${DEV_UNDERCLOUD_FILE} undercloud file with ${REG_URL_PREFIX}"
    echo "*****************"
else
    echo "${DEV_UNDERCLOUD_FILE} does not exist to get the correct docker_registry"
    exit 1
fi

if [[ -d $PATH_TO_WORKSPACE_REPO ]]; then
    export COMPONENT_HASH=`(cd $PATH_TO_WORKSPACE_REPO; git rev-parse --verify HEAD)`
    echo COMPONENT_HASH=${COMPONENT_HASH}
fi

# Determine if executing deployment for a hotfix pipeline
if [[ ! -z "$HOTFIX_MAJOR_COMPONENT" ]]; then
echo "Executing deployment as a hotfix with major component, ${HOTFIX_MAJOR_COMPONENT}"
export HOTFIX=true

# Set component and package to only test hotfix major component
case "$HOTFIX_MAJOR_COMPONENT" in
    "genctl")
    export COMPONENT=genctl
    export PACKAGE=genctl-release
    ;;

    "rias")
    export COMPONENT=rias
    export PACKAGE=rias-release
    export RIAS_DEPLOY_COMPONENT_TYPE=rias
    ;;

    "rias-etcd")
    export COMPONENT=rias
    export PACKAGE=rias-etcd-release
    export RIAS_DEPLOY_COMPONENT_TYPE=rias
    ;;
esac
fi
echo RAZEE_HOTFIX_ON_DEPLOY_NEXT_GENERATION: ${RAZEE_HOTFIX_ON_DEPLOY_NEXT_GENERATION}
if [[ ! -z "$RAZEE_HOTFIX_ON_DEPLOY_NEXT_GENERATION" || ! -z "$HOTFIX_MAJOR_COMPONENT" ]]; then
    #copy dynamically created razee vetted version file under vetted version directory
    if [[ -d $PATH_TO_VV_UPDATED ]]; then
        echo "make a copy of environment file to new-${RAZEE_HOTFIX_NEXTGEN_ENVIRONMENT_FILE} to configure cluster state with LD flags"
        cp ${PATH_TO_VETTED_VERSIONS_REPO}/${RAZEE_HOTFIX_NEXTGEN_ENVIRONMENT_FILE} ${PATH_TO_VETTED_VERSIONS_REPO}/"new-${RAZEE_HOTFIX_NEXTGEN_ENVIRONMENT_FILE}"
        cp ${PATH_TO_VV_UPDATED}/${GENCTL_VETTED_VERSIONS} ${PATH_TO_VETTED_VERSIONS_REPO}/${GENCTL_VETTED_VERSIONS}
        echo "razee hotfix vetted version file ${GENCTL_VETTED_VERSIONS}"
        cat ${PATH_TO_VETTED_VERSIONS_REPO}/${GENCTL_VETTED_VERSIONS}
    fi
fi

echo "component: ${COMPONENT:-}"
echo "package: ${PACKAGE}"

export VAULT_NAMESPACE="nextgen"

# Code chunk for merging specified vetted versions file with default to produce a 'full' vetted versions file
# If code is run (e.g. if VETTED_VERSIONS_OVERRIDE is of non-zero length), this will set the var passed to deploy-ddt.sh to the new file's name
pushd $PATH_TO_VETTED_VERSIONS_REPO

# Set the right override file
if [[ -n ${VETTED_VERSIONS_OVERRIDE} ]]; then
    OVERRIDE_FILE="${VETTED_VERSIONS_OVERRIDE}"
else
    OVERRIDE_FILE="${GENCTL_VETTED_VERSIONS}"
fi

# Validate the vetted versions file
echo "Will validate the vetted versions file ${OVERRIDE_FILE}"
export PATH_TO_VETTED_VERSIONS_FILE="${OVERRIDE_FILE}"
retry python3 -m pip install -q -r $PATH_TO_GENCTL_CI/scripts/validate_vetted_versions/requirements.txt
python3 $PATH_TO_GENCTL_CI/scripts/validate_vetted_versions/validate_vetted_versions.py

# If we validated in soft mode, then a new file was created and that is the one that should be merged
if [[ "${VETTED_VERSIONS_VALIDATION_MODE}" == "soft" ]]; then
    OVERRIDE_FILE="vetted_versions_cleaned.yaml"
fi

DEFAULT_OUTPUT_FILE=pre-integration-merged.yaml
echo "Running merge..."
yaml-merge "${VETTED_VERSIONS_DEFAULT}" "${OVERRIDE_FILE}" > "${DEFAULT_OUTPUT_FILE}"

echo "catting merged file"
cat ${DEFAULT_OUTPUT_FILE}
echo "Setting GENCTL_VETTED_VERSIONS to merged file"
GENCTL_VETTED_VERSIONS=${DEFAULT_OUTPUT_FILE}
popd


echo GENCTL_VETTED_VERSIONS=${GENCTL_VETTED_VERSIONS}
echo DDT_CONFIG_TEMPLATE=${DDT_CONFIG_TEMPLATE}

echo DEPLOY_PACKAGE_ONLY: ${DEPLOY_PACKAGE_ONLY}
if [[ ${DEPLOY_PACKAGE_ONLY} = 'true' || ${DEPLOY_COMPONENT_ONLY} = 'true' ]]; then
    echo "in DEPLOY_MODE_ONLY: DEPLOY_PACKAGE_ONLY: ${DEPLOY_PACKAGE_ONLY}, DEPLOY_COMPONENT_ONLY: ${DEPLOY_COMPONENT_ONLY}"
    $PATH_TO_GENCTL_CI/scripts/deploy-ddt.sh ${COMPONENT}
else
# Deploy hostos
$PATH_TO_GENCTL_CI/scripts/deploy-ddt.sh hostos

# Deploy cloudnet
$PATH_TO_GENCTL_CI/scripts/deploy-ddt.sh cloudnet

# Deploy RIAS
# Do this before deploying genctl so that genctl can use RIAS storage
# RIAS will not work in TD, so exclude that datacenter

if [ ${REGIONDIGIT} != 0 ]; then
    echo "set up rias cluster LD flags"
    $PATH_TO_GENCTL_CI/scripts/setup_razee_ci_cluster.sh
    $PATH_TO_GENCTL_CI/scripts/deploy-rias.sh
fi

# Deploy kube
$PATH_TO_GENCTL_CI/scripts/deploy-ddt.sh kube

# Deploy genctl
$PATH_TO_GENCTL_CI/scripts/deploy-ddt.sh genctl
# Source the validate_razee_cluster.sh
source $PATH_TO_GENCTL_CI/scripts/validate_razee_cluster_utils.sh
#execute cluster MTPs readiness check
set +x
validate_razee_cluster_genctl ${MZONE_NAME} "${PATH_TO_GENCTL_CI}" ${BASTION_USERNAME} \
"${DAL_VAULT_KEY}" "${PATH_TO_PLATFORM_INVENTORY_REPO}" \
${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN}      \
${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
set -x

#execute cluster pods readiness check
set +x
validate_pods_cluster_readiness_genctl ${MZONE_NAME} "$PATH_TO_GENCTL_CI" ${BASTION_USERNAME} \
"${DAL_VAULT_KEY}" "$PATH_TO_PLATFORM_INVENTORY_REPO" \
${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN}      \
${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
set -x

fi