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

COMP=$1; shift

# Source deployer_utils
source $PATH_TO_GENCTL_CI/scripts/deployer_utils.sh

# NOTE: we should be checking all env vars we expect to be declared outside of this script - here

# Prepare an mzone-specific directory on the deploy server where we can put things
MZONE_DIR=/home/${BASTION_USERNAME}/${MZONE_NAME}
REPO_DIR=${MZONE_DIR}/repos
ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "mkdir -p ${REPO_DIR}"

# Check if variable length is 0, if so, print message that it may cause an error
if [[ -z ${DDT_CONFIG_TEMPLATE:-} ]]; then
  echo "ERROR: \${DDT_CONFIG_TEMPLATE} was not set or null"
  exit 1
fi

# initialize a DDT hjson specific to this mzone with known-good tags
python3 $PATH_TO_GENCTL_CI/scripts/config_ddtool_hjson.py \
    $PATH_TO_GENCTL_CI/hack/ddtool/${DDT_CONFIG_TEMPLATE} \
    $PATH_TO_DDT_REPO/${MZONE_NAME}.hjson \
    mzone ${MZONE_NAME} $PATH_TO_VETTED_VERSIONS_REPO/${GENCTL_VETTED_VERSIONS}

# Add --node-list flag to hostos release bundles in .hjson file to exclude z nodes, if
# hostos release bundles are too old to support z arch.
python3 $PATH_TO_GENCTL_CI/scripts/MDS/add_nodelist_flags.py \
    ddtool \
    $PATH_TO_VETTED_VERSIONS_REPO/${GENCTL_VETTED_VERSIONS} \
    $PATH_TO_PLATFORM_INVENTORY_REPO/region/${MZONE_NAME}.yml \
    $PATH_TO_DDT_REPO/${MZONE_NAME}.hjson \
    $PATH_TO_DDT_REPO/${MZONE_NAME}.hjson

cat $PATH_TO_DDT_REPO/${MZONE_NAME}.hjson

# trim down the hjson to just the COMP we want to deploy in this pass
# and update the tag if we are changing that
if [[ ${COMP} == ${COMPONENT:-} ]]; then
    python3 $PATH_TO_GENCTL_CI/scripts/config_ddtool_hjson.py \
        $PATH_TO_DDT_REPO/${MZONE_NAME}.hjson \
        $PATH_TO_DDT_REPO/${MZONE_NAME}.hjson \
        prep-component ${COMPONENT} ${PACKAGE} ${COMPONENT_HASH} ${DEPLOY_PACKAGE_ONLY} ${DEPLOY_COMPONENT_ONLY}
else
    python3 $PATH_TO_GENCTL_CI/scripts/config_ddtool_hjson.py \
        $PATH_TO_DDT_REPO/${MZONE_NAME}.hjson \
        $PATH_TO_DDT_REPO/${MZONE_NAME}.hjson \
        prep-component ${COMP}
fi
cat $PATH_TO_DDT_REPO/${MZONE_NAME}.hjson

# Copy ddtool to deploy server
rsync -aq --delete -e "ssh ${SSH_CONFIG_PARAMS}" $PATH_TO_DDT_REPO/ ${DEPLOY_SERVER_TARGET}:${REPO_DIR}/ddtool

# Delete .git and copy genctl global files to deploy server
rm -rf $PATH_TO_GENCTL_GLOBALS_RPEO/.git
rsync -aq --delete -e "ssh ${SSH_CONFIG_PARAMS}" $PATH_TO_GENCTL_GLOBALS_RPEO/ ${DEPLOY_SERVER_TARGET}:${REPO_DIR}/genctl-globals

# Copy platform-inventory files to deploy server
ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "mkdir -p ${REPO_DIR}/platform-inventory"
rsync -aq --delete -e "ssh ${SSH_CONFIG_PARAMS}" $PATH_TO_PLATFORM_INVENTORY_REPO/region/ ${DEPLOY_SERVER_TARGET}:${REPO_DIR}/platform-inventory/region

if [[ ${COMP} == ${COMPONENT:-} ]]; then
    # So we don't log any password
    set +x

    # Pull image and copy to the deployer
    # (This function is from deployer_utils, which at this point should have been sourced already)

    pull_image_and_copy_to_deployer ${ARTIFACTORY_DOCKER_STAGING_URL} \
    ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} ${COMPONENT}/${PACKAGE}:${COMPONENT_HASH} \
    "true" ${ARTIFACTORY_DOCKER_PROD_URL}/${COMPONENT}/${PACKAGE}:${COMPONENT_HASH} \
    ${PACKAGE}-${COMPONENT_HASH} ${MZONE_DIR}

    # Revert flag
    set -x
fi

# docker login to prod registry so that we can pull images
set +x  # so we do not log the password
echo "docker logging in to ${ARTIFACTORY_DOCKER_PROD_URL}"
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_PROD_URL} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
set -x

# Pull and copy known-good images to deploy server
python3 $PATH_TO_GENCTL_CI/scripts/pull_ddt_images.py $PATH_TO_DDT_REPO/${MZONE_NAME}.hjson "${SSH_CONFIG_PARAMS}" ${DEPLOY_SERVER_TARGET} \
    ${ARTIFACTORY_DOCKER_PROD_URL} ${MZONE_DIR}


# Generate Vault token and copy to deployer
# (This function is from deployer_utils, which at this point should have been sourced already)

# So we don't log
set +x

generate_ngsec_and_copy_to_deployer ${VAULT_IP} "${VAULT_KEY}" ${VAULT_NAMESPACE} "${VAULT_CACERT}" ${VAULT_PREFIX} ${MZONE_DIR} "true"

# Revert flag
set -x


# Run DDTool deployment
echo "Deploying..."
ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "cd ${REPO_DIR}/ddtool; ARTIF_USER=bogus ARTIF_APIKEY=bogus REG_URL_PREFIX=${REG_URL_PREFIX} ./ddt.sh -i=${MZONE_NAME}.hjson -t=default --no-readiness"

# remove the vault token
ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "rm -rf ${MZONE_DIR}/.ngsec"
