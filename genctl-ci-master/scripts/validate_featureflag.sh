#!/bin/bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script validates feature flags

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO, PATH_TO_PLATFORM_INVENTORY_REPO, FAIL_IF_ERROR
# ART_URL, IMG_TO_RUN_PATH, IMG_TO_RUN_TAG
# WCP_ARTIFACTORY_USERNAME,CC_ARTIF_ACCESS_TOKEN
# LAUNCH_DARKLY_ENVIRONMENT
# IBMCLOUD_KEY, AUTH_TOKEN,GIT_TOKEN
# BASTION_PRIVATE_KEY, BASTION_PRIVATE_KEY_ECDSA, BASTION_PRIVATE_KEY_RSA, BASTION_USERNAME
# DAL_VAULT_KEY

# In addition, the following are optional

# CLUSTERS_TO_VALIDATE can be defined before executing the script and if it has value, it will be used

# Set flags
set -ex
# Source the ibmcloud_utils.sh
. ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

# Source the validate_featureflag_utils.sh
. ${PATH_TO_GENCTL_CI}/scripts/validate_featureflag_utils.sh

# Source a script that help us to validate existence and retrieve values from pipeline.yaml
. ${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/verify_workspace_pipeline_yaml.sh ${PATH_TO_WORKSPACE_REPO} false

# Get the feature flag
LAUNCH_DARKLY_FEATURE_FLAG=$(check_pipeline_key ".deployment" "feature_flag" "${PIPELINE_YAML_FILE_LOCATION}" true)

# Check if we received an explicit list of cluster to validate
if [ ! -z "${CLUSTERS_TO_VALIDATE}" ]
then
    RULE_TAG=${CLUSTERS_TO_VALIDATE}
else
    # Get the rule tag
    RULE_TAG=$(check_pipeline_key ".deployment" "rule_tag" "${PIPELINE_YAML_FILE_LOCATION}" true)
fi

# At this point we either:
# 1. Have exited 1 due to missing pipeline.yaml
# 2. We have in RULE_TAG the list of clusters, coming from either the pipeline.yaml file or explicitly set in CLUSTERS_TO_VALIDATE

if [[ ${COS_FFSLD_ENABLED} == false ]]
then
    set +x
    validate_featureflags_from_cluster_list ${RULE_TAG} ${PATH_TO_GENCTL_CI} \
    ${LAUNCH_DARKLY_FEATURE_FLAG} ${LAUNCH_DARKLY_ENVIRONMENT} "${GIT_TOKEN}" \
    ${FAIL_IF_ERROR} \
    "${IBMCLOUD_KEY}" ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}" \
    "${DAL_VAULT_KEY}" ${PATH_TO_PLATFORM_INVENTORY_REPO} \
    ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} \
    ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
    set -x
else
    set +x
    sleep 300
    validate_featureflags_for_cos_ffsld_and_cluster ${RULE_TAG} ${PATH_TO_GENCTL_CI} "${GIT_TOKEN}" \
    ${FAIL_IF_ERROR} \
    "${IBMCLOUD_KEY}" ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}" \
    "${DAL_VAULT_KEY}" ${PATH_TO_PLATFORM_INVENTORY_REPO} \
    ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} \
    ${BRT_IMG_TO_RUN_PATH} ${BRT_IMG_TO_RUN_TAG}
    set -x
fi
