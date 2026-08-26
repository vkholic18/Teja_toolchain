#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

#
# This script creates the test configuration to run the promotion tests later
#

# Set flags
set -ex

# Overrides for OnePipeline
if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
  # Source one-pipeline utils
  # WORKSPACE = /workspace/app = root directory
  source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

  # Needed for upload to artifactory
  source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh
  export PROMOTION_YAMLS_DIR="${WORKSPACE}/promotion-repo"

  # Create empty directory to store output of create_promotion_test_configs.py below
  mkdir ${WORKSPACE}/promotion

  # Clone the workspace repo (e.g. mzone7x1) at its master commit
  export WORKSPACE_REPO_MASTER=${WORKSPACE}/workspace-repo-master
  mkdir ${WORKSPACE_REPO_MASTER}
  pushd ${WORKSPACE}
  git clone ${IBM_GITHUB_URI_BASE}:${APP_REPO_ORG}/${APP_REPO_NAME}.git ${WORKSPACE_REPO_MASTER}

  ls -l ${WORKSPACE_REPO_MASTER}
  popd

elif [[ -e ./pipe-data/pr.sh ]]; then
  . pipe-data/pr.sh
  echo "Git Environment:"
  env | grep ^PR_

  export WORKSPACE=$(pwd)
fi

export PROMOTION_PR_BRANCH=${PR_BRANCH}
echo PROMOTION_PR_BRANCH: ${PROMOTION_PR_BRANCH}
echo ROOT_DIR: ${WORKSPACE}

# Search for dev config file and extract the public ip
function get_cluster_public_ip() {
  # Reduce log verbosity
  set +x
  echo "Searching for cluster directory."
  cluster_dir=$(find -L ${RIAS_GLOBALS_REPO} -type f -name "$1\.yaml")
  if [[ -z ${cluster_dir} ]]; then
    echo "Cluster $1 directory was not found in globals, no op"
    exit 1
  fi
  echo "Cluster directory : ${cluster_dir}."
  template_data=$(yq -r '.spec.strTemplates[]' "${cluster_dir}")
  PUBLIC_IP=$(echo "${template_data}" | yq -r '.data.ingress' | jq -r '.hosts[0]')
  echo "Cluster public ip : ${PUBLIC_IP}"
  set -x
}

# Determine which promotion yaml file to use based on branch name
SUBSTR='OPS-PROMOTION-BRANCH'
if [[ "$PROMOTION_PR_BRANCH" == *"$SUBSTR"* ]]; then
  export PROMOTION_YAML_FILE_NAME="ops-promotion.yaml"
else
  export PROMOTION_YAML_FILE_NAME="promotion.yaml"
fi

# Build a rule tag
tmp_rule=$(mktemp)
single_rias_cluster_rule=$(mktemp)
python3 ${PATH_TO_GENCTL_CI}/tasks/create-rule-tag-for-promotion-tests.py \
  ${PROMOTION_YAML_FILE_NAME} \
  ${PATH_TO_WORKSPACE_REPO} \
  ${PROMOTION_PR_BRANCH} \
  ${tmp_rule} \
  ${PROMOTION_YAMLS_DIR}/master_environment.yaml \
  ${single_rias_cluster_rule}

RULE_TAG=`cat ${tmp_rule}`
rm ${tmp_rule}
rm ${single_rias_cluster_rule}

python3 ${PATH_TO_GENCTL_CI}/scripts/promotion/create_promotion_test_configs.py \
  ${PROMOTION_YAML_FILE_NAME} \
  ${PATH_TO_WORKSPACE_REPO} \
  ${WORKSPACE_REPO_MASTER} \
  ${PROMOTION_PR_BRANCH} \
  ${WORKSPACE}/promotion/ \
  ${RULE_TAG}


if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
  # Upload promotion tar file to artifactory
  pushd ${WORKSPACE}
  export PROMOTION_TAR_FILE="promotion_${PIPELINE_RUN_ID}.tar.gz"
  export PROMOTION_TAR_PATH="${WORKSPACE}/${PROMOTION_TAR_FILE}"
  tar -zvcf "${PROMOTION_TAR_FILE}" promotion

  echo "Uploading promotion tar file to ${PROMOTION_TAR_PATH}"

  export URL_TO_UPLOAD="${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/genctl-cd/ci-promotion-tests/${PROMOTION_TAR_FILE}"
  upload_file_to_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${URL_TO_UPLOAD}" "${PROMOTION_TAR_PATH}"
  popd
fi
