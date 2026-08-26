#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -e
set +x

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

#source icr related utils
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="razee"

export PIPELINE_TYPE="pr"

echo "Test subpipeline"

# Define the repositories to be cloned
REPOS_TO_CLONE="
PLATFORM_INVENTORY
RESOURCELOCK
GENCTL_GLOBALS
RIAS_GLOBALS
DEV_REGIONS
GENESIS_DEPLOY_ARTIFACTS
RIAS_ETCD_GLOBALS
RIAS_ETCD_RELEASE
"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Clone required repos
clone_repos_from_env_vars "${IBM_HTTPS_BASE_URL}" "${WORKSPACE}" "${REPOS_TO_CLONE}" 

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_VETTED_VERSIONS_REPO="${WORKSPACE}/${GENCTL_VETTED_VERSIONS_REPO_NAME}"
export PATH_TO_PLATFORM_INVENTORY_REPO="${WORKSPACE}/${PLATFORM_INVENTORY_REPO_NAME}"
export PATH_TO_RESOURCELOCK_REPO="${WORKSPACE}/${RESOURCELOCK_REPO_NAME}"
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_RIAS_ETCD_GLOBALS_REPO="${WORKSPACE}/${RIAS_ETCD_GLOBALS_REPO_NAME}"
export PATH_TO_RIAS_ETCD_RELEASE_REPO="${WORKSPACE}/${RIAS_ETCD_RELEASE_REPO_NAME}"
export PATH_TO_GENCTL_GLOBALS_REPO="${WORKSPACE}/${GENCTL_GLOBALS_REPO_NAME}"
export PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO="${WORKSPACE}/${GENESIS_DEPLOY_ARTIFACTS_REPO_NAME}"
export PATH_TO_DEV_REGIONS_REPO="${WORKSPACE}/${DEV_REGIONS_REPO_NAME}"

# Note: PATH_TO_WORKSPACE_REPO will be set after downloading the promotion tar
# Don't rely on the default PATH_TO_WORKSPACE_REPO from one_pipeline_utils.sh

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Source shared kubeconfig setup
source ${PATH_TO_PIPELINE}/steps/qz2-setup-kubeconfig.sh

# Setup kubeconfig
setup_qz2_kubeconfig

# Get the parent pipeline info to pass it to the sub-pipeline
get_parent_pipeline_info

# Download the promotion tar file and unzip to access workspace repos
pushd ${WORKSPACE}
export PROMOTION_TAR_FILE="promotion_${PARENT_PIPELINE_RUN_ID}.tar.gz"
export PROMOTION_TAR_PATH="${WORKSPACE}/${PROMOTION_TAR_FILE}"

URL_TO_DOWNLOAD="${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/genctl-cd/ci-promotion-tests/${PROMOTION_TAR_FILE}"

echo "Downloading ${URL_TO_DOWNLOAD}"
download_file_from_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${URL_TO_DOWNLOAD}" "${PROMOTION_TAR_FILE}"

if [ ! -f "${PROMOTION_TAR_FILE}" ]; then
  echo "ERROR: Failed to download promotion tar file from ${URL_TO_DOWNLOAD}"
  exit 1
fi

echo "Extracting promotion tar file..."
tar -xzvf "${PROMOTION_TAR_FILE}"

export PROMOTION_OUTPUT="${WORKSPACE}/promotion"

# Verify the promotion directory exists and has content
if [ ! -d "${PROMOTION_OUTPUT}" ]; then
  echo "ERROR: PROMOTION_OUTPUT directory does not exist after tar extraction!"
  echo "Contents of ${WORKSPACE}:"
  ls -la "${WORKSPACE}"
  exit 1
fi

echo "Promotion workspace extracted successfully. Contents:"
ls -la "${PROMOTION_OUTPUT}"

popd

setup_validation_prerequisites() {
    echo "=========================================="
    echo "Setting up validation prerequisites"
    echo "=========================================="

    # Test kubectl access
    echo "Testing kubectl access..."
    kubectl get pods -n razee

    echo "=========================================="
    echo "Validation prerequisites complete"
    echo "=========================================="
}

validate_razee_cluster_genctl() {
    echo "Validating cluster readiness..."

    # Source validation utilities
    source ${PATH_TO_GENCTL_CI}/scripts/validate_razee_cluster_utils.sh

    # Check readiness (lock status check is disabled inside the function)
    check_readiness_and_lock_status "${PATH_TO_GENCTL_CI}" genctl
    check_crds_genctl

    echo "Cluster readiness validated"
}


#==============================================================================
# MAIN EXECUTION
#==============================================================================

# Setup all prerequisites for validation
setup_validation_prerequisites

# Cluster validation
validate_razee_cluster_genctl

echo "All validations completed successfully"