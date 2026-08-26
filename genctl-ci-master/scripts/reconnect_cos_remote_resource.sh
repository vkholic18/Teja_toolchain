#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script scales razee clusters

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO, PATH_TO_PLATFORM_INVENTORY_REPO , FF_SETLD_REPLICAS
# ART_URL, IMG_TO_RUN_PATH, IMG_TO_RUN_TAG
# WCP_ARTIFACTORY_USERNAME,CC_ARTIF_ACCESS_TOKEN
# IBMCLOUD_KEY
# BASTION_PRIVATE_KEY, BASTION_PRIVATE_KEY_ECDSA, BASTION_PRIVATE_KEY_RSA, BASTION_USERNAME
# DAL_VAULT_KEY

# In addition, the following are optional

# Set flags
set -ex

# Source the ibmcloud_utils.sh
. ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

# Source the apply_desired_ffsld.sh
. ${PATH_TO_GENCTL_CI}/scripts/reconnect_cos_remote_resource_to_razee.sh

# Source a script that help us to validate existence and retrieve values from pipeline.yaml
. ${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/verify_workspace_pipeline_yaml.sh ${PATH_TO_WORKSPACE_REPO} false

# Get the rule tag
RULE_TAG=$(check_pipeline_key ".deployment" "rule_tag" "${PIPELINE_YAML_FILE_LOCATION}" true)

# At this point we either:
# 1. Have exited 1 due to missing pipeline.yaml
# 2. We have in RULE_TAG the list of clusters, coming from either the pipeline.yaml file


set +x
reconnect_cos_remote_resources ${RULE_TAG} ${PATH_TO_GENCTL_CI} \
    "${IBMCLOUD_KEY}" ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}" \
    "${DAL_VAULT_KEY}" ${PATH_TO_PLATFORM_INVENTORY_REPO} \
    ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} \
    ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG} 
set -x
