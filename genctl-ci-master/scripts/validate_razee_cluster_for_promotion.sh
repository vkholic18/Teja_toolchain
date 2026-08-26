#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# Set flags
set -ex

# Source the ibmcloud_utils.sh
. ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

# Source the validate_razee_cluster.sh
. ${PATH_TO_GENCTL_CI}/scripts/validate_razee_cluster_utils.sh

# Overrides for OnePipeline
if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
  export PROMOTION_OUTPUT="${WORKSPACE}/promotion"
fi
ls -l ${PROMOTION_OUTPUT}
if [[ ! "$(ls -A ${PROMOTION_OUTPUT})" ]]; then
  echo "Promotion folder is empty, no need to run promotion tests. Exiting ..."
  exit 0
fi

# Since all the workspaces have same clusters, we just take the first workspace (No matter which one it is)
promote_workspace=$(ls ${PROMOTION_OUTPUT} | grep -v components-ordered-list | head -1)
echo promote_workspace: $promote_workspace
if [ -d "${PROMOTION_OUTPUT}/${promote_workspace}" ]; then
  export WS_PATH=${PROMOTION_OUTPUT}/${promote_workspace}
  echo WS_PATH: ${WS_PATH}

  # Source a script that help us to validate existence and retrieve values from pipeline.yaml
  . ${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/verify_workspace_pipeline_yaml.sh ${WS_PATH} false

  # Get the rule tag
  RULE_TAG=$(check_pipeline_key ".deployment" "rule_tag" "${PIPELINE_YAML_FILE_LOCATION}" true)
fi

# At this point we either:
# 1. Have exited 1 due to missing pipeline yaml
# 2. We have in RULE_TAG the list of clusters

# If USE_QZ2_WORKER is true and we have a genctl cluster, skip validation here
# The QZ2 validation subpipeline will be triggered separately from the test stage
if [[ "${USE_QZ2_WORKER}" == "true" ]]; then
    # Parse RULE_TAG to get MZONE_NAME (format: "rias_cluster,mzone_name" or just "mzone_name")
    if [[ ${RULE_TAG} == *","* ]]; then
        MZONE_NAME=$(echo ${RULE_TAG} | cut -d ',' -f2)
    else
        MZONE_NAME=${RULE_TAG}
    fi

    # Only skip for genctl clusters (mzone*)
    if [[ ${MZONE_NAME} == mzone* ]]; then
        echo "Skipping validation for genctl cluster ${MZONE_NAME} - will be validated via QZ2 subpipeline"

        # Source one-pipeline utils to use set_env
        source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

        # Determine worker ID based on region
        REGIONDIGIT=${MZONE_NAME#*[[:digit:]]}  # Remove everything up to and including first digit
        REGIONDIGIT=${REGIONDIGIT:0:1}          # Take only the first character (2nd digit)
        [ "${REGIONDIGIT}" == "1" ] && REGIONDIGIT="0"
        WORKER_ID="qz2-tekton-worker-trigger-dal1${REGIONDIGIT}"

        # Use set_env to persist variables for use by run_promotion_tests.sh
        set_env genctl-mzone-name "${MZONE_NAME}"
        set_env genctl-worker-id "${WORKER_ID}"

        echo "Set genctl-mzone-name=${MZONE_NAME}"
        echo "Set genctl-worker-id=${WORKER_ID}"
    else
        # For RIAS clusters, run validation directly
        set +x
        validate_razee_clusters ${RULE_TAG} "${PATH_TO_GENCTL_CI}" \
        "${IBMCLOUD_KEY}" ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}" \
        "${DAL_VAULT_KEY}" "${PATH_TO_PLATFORM_INVENTORY_REPO}" \
        ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} \
        ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
        set -x
    fi
else
    # USE_QZ2_WORKER is false, run validation directly
    set +x
    validate_razee_clusters ${RULE_TAG} "${PATH_TO_GENCTL_CI}" \
    "${IBMCLOUD_KEY}" ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}" \
    "${DAL_VAULT_KEY}" "${PATH_TO_PLATFORM_INVENTORY_REPO}" \
    ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} \
    ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
    set -x
fi