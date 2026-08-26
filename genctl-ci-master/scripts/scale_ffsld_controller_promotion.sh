#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

#
# This script scales razee clusters for the CD promotion pipeline.
#

# Set flags
set -ex

# Source the ibmcloud_utils.sh
. ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

# Source the scale_ffsetld_razee_cluster.sh
. ${PATH_TO_GENCTL_CI}/scripts/scale_ffsetld_razee_cluster.sh

# Source the reconnect_cos_remote_resource_to_razee.sh
. ${PATH_TO_GENCTL_CI}/scripts/reconnect_cos_remote_resource_to_razee.sh

# Overrides for OnePipeline
if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
  export PROMOTION_YAMLS_DIR="${WORKSPACE}/promotion-repo"
elif [[ -e ./pipe-data/pr.sh ]]; then
  . pipe-data/pr.sh
fi

# Determine which promotion yaml file to use based on branch name
SUBSTR='OPS-PROMOTION-BRANCH'
if [[ "$PR_BRANCH" == *"$SUBSTR"* ]]; then
  export PROMOTION_YAML_FILE_NAME="ops-promotion.yaml"
else
  export PROMOTION_YAML_FILE_NAME="promotion.yaml"
fi

# Source a script that help us to validate existence and retrieve values from pipeline.yaml
. ${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/verify_workspace_promotion_yaml.sh ${PROMOTION_YAML_FILE_NAME} ${PATH_TO_WORKSPACE_REPO} false

# Temporarily skip lock/unlock on staging or production clusters from promotion pipeline.
promotion_repo_name=`yq '.name' ${PROMOTION_YAMLS_DIR}/master_environment.yaml`
stage_prod_pattern="^(staging|[a-z]+-prod)$"
if [[ $promotion_repo_name =~ $stage_prod_pattern ]]; then
  echo "Skipping lock/unlock on staging and production clusters from promotion pipeline."
  exit 0
fi

# Build a rule tag
tmp_rule=$(mktemp)
single_rias_cluster_rule=$(mktemp)
python3 ${PATH_TO_GENCTL_CI}/tasks/create-rule-tag-for-promotion-tests.py \
  ${PROMOTION_YAML_FILE_NAME} \
  ${PATH_TO_WORKSPACE_REPO} \
  ${PR_BRANCH} \
  ${tmp_rule} \
  ${PROMOTION_YAMLS_DIR}/master_environment.yaml \
  ${single_rias_cluster_rule}
export RULE_TAG=`cat ${tmp_rule}`
export SINGLE_RIAS_CLUSTER_RULE=`cat ${single_rias_cluster_rule}` 
rm ${tmp_rule}
rm ${single_rias_cluster_rule}

# debug purpose only
echo "RULE_TAG: $RULE_TAG"
echo "SINGLE_RIAS_CLUSTER_RULE: $SINGLE_RIAS_CLUSTER_RULE"

# Evaluates if for given ws, configured env is has disabled tarditional ffsld controller in globals repo
source ${PATH_TO_GENCTL_CI}/onepipeline/jobs/evaluate_status_of_cos_ffsld.sh

# debug purpose only
echo "COS_FFSLD_ENABLED: " ${COS_FFSLD_ENABLED}
set_env cos-ffsld-enabled ${COS_FFSLD_ENABLED}

# At this point we either:
# 1. Have exited 1 due to missing promotion yaml
# 2. We have in RULE_TAG the list of clusters, built from promotion yaml file

if [[ ${RECONNECT_COS} != true ]]; then
  if [[ ${COS_FFSLD_ENABLED} == false ]]; then
      set +x
      # Iterate through clusters and call promotion-specific scale function
      for rule_tag in $(echo ${RULE_TAG} | tr "," "\n")
      do
          if [[ -z "${rule_tag}" ]]; then
              echo "The rule tag does not exist or empty. Continue ..."
              continue
          fi
          
          scale_ffsetld_razee_cluster_promotion "${rule_tag}" ${PATH_TO_GENCTL_CI} ${FF_SETLD_REPLICAS} \
          "${IBMCLOUD_KEY}" ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}" \
          "${DAL_VAULT_KEY}" ${PATH_TO_PLATFORM_INVENTORY_REPO} \
          ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} \
          ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
      done
      set -x
  else
      set +x
      # Iterate through clusters and call promotion-specific disconnect function
      for rule_tag in $(echo ${RULE_TAG} | tr "," "\n")
      do
          if [[ -z "${rule_tag}" ]]; then
              echo "The rule tag does not exist or empty. Continue ..."
              continue
          fi
          
          set +x
          disconnect_cos_remote_resource_promotion "${rule_tag}" ${PATH_TO_GENCTL_CI} \
          "${IBMCLOUD_KEY}" ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}" \
          "${DAL_VAULT_KEY}" ${PATH_TO_PLATFORM_INVENTORY_REPO} \
          ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} \
          ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG} ${SINGLE_RIAS_CLUSTER_RULE}
          set -x
      done
      sleep 300  #wait time for env to come up
      set -x
  fi
else

  set +x
  reconnect_cos_remote_resources_promotion ${RULE_TAG} ${PATH_TO_GENCTL_CI} \
  "${IBMCLOUD_KEY}" ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}" \
  "${DAL_VAULT_KEY}" ${PATH_TO_PLATFORM_INVENTORY_REPO} \
  ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} \
  ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG} ${SINGLE_RIAS_CLUSTER_RULE}
  set -x

fi
