#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

set -eux

COMP=$1; shift

# Prepare an mzone-specific directory on the deploy server where we can put things
export MZONE_DIR=/home/${BASTION_USERNAME}/${MZONE_NAME}
ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "mkdir -p ${MZONE_DIR}"

# Check if variable length is 0, if so, print message that it may cause an error
if [[ -z ${MDS_CONFIG_TEMPLATE:-} ]]; then
  echo "ERROR: \${MDS_CONFIG_TEMPLATE} was not set or null"
  exit 1
fi

source $PATH_TO_GENCTL_CI/scripts/deployer_utils.sh
source $PATH_TO_GENCTL_CI/scripts/retry.sh

# initialize a EYAML specific to this mzone with known-good tags
# This will also add nodelist to the eyaml if needed
python3 $PATH_TO_GENCTL_CI/scripts/MDS/config_mds_eyaml.py \
    --input-file $PATH_TO_GENCTL_CI/hack/MDS/${MDS_CONFIG_TEMPLATE} \
    --output-file $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
    --vetted-versions $PATH_TO_VETTED_VERSIONS_REPO/${GENCTL_VETTED_VERSIONS} \
    --inventory-file $PATH_TO_PLATFORM_INVENTORY_REPO/region/${MZONE_NAME}.yml \
    --operation init


# yaml dumps strings with double quotes wrappd in single quotes, since we only want double quotes, we remove them
pushd $PATH_TO_MDS_REPO
sed -i.bak "s/'//g" ${MZONE_NAME}.yaml
popd

# if the current component being deployed is the component that is being tested
# init the EYAML with the hash of the test component
if [[ ${COMP} == ${COMPONENT:-} ]]; then
    # if we want to deploy package only then trim down all the other packages for this component
    [[ ${DEPLOY_PACKAGE_ONLY} = 'true' ]] && EXTRA_CMD="--package-only" || EXTRA_CMD=""
    [[ ${DEPLOY_COMPONENT_ONLY} = 'true' ]] && EXTRA_CMD="--component-only" || EXTRA_CMD=""

    python3 $PATH_TO_GENCTL_CI/scripts/MDS/config_mds_eyaml.py  \
            --input-file $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
            --output-file $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
            --component ${COMP} \
            --package ${PACKAGE} \
            --version ${COMPONENT_HASH} \
            ${EXTRA_CMD} \
            --operation prep

    [[ $COMP == "etcd" ]] && ROOT_COMPONENT="kube" || ROOT_COMPONENT=$COMP
    # Pull image and copy to the deployer
    # (This function is from deployer_utils, which at this point should have been sourced already)
    set +x
    pull_image_and_copy_to_deployer ${ARTIFACTORY_DOCKER_STAGING_URL} \
    ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} ${ROOT_COMPONENT}/${PACKAGE}:${COMPONENT_HASH} \
    "true" ${ARTIFACTORY_DOCKER_PROD_URL}/${ROOT_COMPONENT}/${PACKAGE}:${COMPONENT_HASH} \
    ${PACKAGE}-${COMPONENT_HASH} ${MZONE_DIR}
    set -x
fi

cat $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml

# Copy MDS to deploy server
retry rsync -aq --delete -e "ssh ${SSH_CONFIG_PARAMS}" $PATH_TO_MDS_REPO/ ${DEPLOY_SERVER_TARGET}:${MZONE_DIR}/micro-deploy-server

# export variables used for vault in MDS/deploy.py
set +x; export IBMCLOUD_KEY=$(echo "$IBMCLOUD_KEY" | jq -r .apikey); set -x

# Pull and copy known-good images to deploy server
python3 $PATH_TO_GENCTL_CI/scripts/pull_mds_images.py \
    --infile $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
    --ssh-params "${SSH_CONFIG_PARAMS}" \
    --deploy-server "${DEPLOY_SERVER_TARGET}" \
    --artifactory-docker-url "${ARTIFACTORY_DOCKER_PROD_URL}" \
    --mzone-dir "${MZONE_DIR}" \
    --component "${COMP}"

# Run MDS deployment
python3 $PATH_TO_GENCTL_CI/scripts/MDS/deploy.py \
    --release-bundles ${COMP} \
    --eyaml-file $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
    --target-eyaml ${MZONE_NAME}.yaml
