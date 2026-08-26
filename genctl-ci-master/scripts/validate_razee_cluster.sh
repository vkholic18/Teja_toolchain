#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
# The following environment variables need to be set before executing the script:

# PATH_TO_GENCTL_CI
# PATH_TO_WORKSPACE_REPO
# PATH_TO_PLATFORM_INVENTORY_REPO
# WCP_ARTIFACTORY_USERNAME eg: wcp-genctl-docker-local-artifactory-username
# CC_ARTIF_ACCESS_TOKEN eg: wcp-genctl-docker-local-artifactory-token
# IBMCLOUD_KEY  egclconc-Balaji-ibmcloud-key
# DAL_VAULT_KEY eg: clconc-vault-dal-qz1-genctl-deploy-key
# CLUSTERS_TO_VALIDATE

# Set flags
set -ex
# Source the ibmcloud_utils.sh
. ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

# Source the validate_razee_cluster.sh
. ${PATH_TO_GENCTL_CI}/scripts/validate_razee_cluster_utils.sh

# Check if we received an explicit list of cluster to validate
if [ ! -z "${CLUSTERS_TO_VALIDATE}" ]
then
  RULE_TAG=${CLUSTERS_TO_VALIDATE}
else
  # Source a script that help us to validate existence and retrieve values from pipeline.yaml
  . ${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/verify_workspace_pipeline_yaml.sh ${PATH_TO_WORKSPACE_REPO} false

  # Get the rule tag
  RULE_TAG=$(check_pipeline_key ".deployment" "rule_tag" "${PIPELINE_YAML_FILE_LOCATION}" true)
fi
# At this point we either:
# 1. Have exited 1 due to missing pipeline.yaml
# 2. We have in RULE_TAG the list of clusters, coming from either the pipeline.yaml file or explicitly set in CLUSTERS_TO_VALIDATE

if [[ ${COS_FFSLD_ENABLED} == false ]]
then
    set +x
    validate_razee_clusters ${RULE_TAG} "${PATH_TO_GENCTL_CI}" \
    "${IBMCLOUD_KEY}" ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}" \
    "${DAL_VAULT_KEY}" "${PATH_TO_PLATFORM_INVENTORY_REPO}" \
    ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} \
    ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
    set -x
else
    set +x
    sleep 150 #wait time for env to come up
    validate_razee_clusters ${RULE_TAG} "${PATH_TO_GENCTL_CI}" \
    "${IBMCLOUD_KEY}" ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}" \
    "${DAL_VAULT_KEY}" "${PATH_TO_PLATFORM_INVENTORY_REPO}" \
    ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} \
    ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
    set -x
fi