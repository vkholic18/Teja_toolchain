#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Source rhos utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/uuc_rhos_utils.sh

# Read the OCP release version used by the workspace mirror/build flow.
export OCP_RELEASE_VERSION=$(yq -r '.deployment.ocp_release_version | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)

# Docker auth for oc/oc-mirror is generated into a temporary config directory.
export DOCKER_CONFIG="${PATH_TO_WORKSPACE_REPO}/temp_sec_artifactory"

# Create DOCKER_CONFIG directory
echo "Creating DOCKER_CONFIG directory: ${DOCKER_CONFIG}"
mkdir -p "${DOCKER_CONFIG}"

# Generate registry authentication config used by the mirror/build steps.
echo "Generating authentication configuration..."
${PATH_TO_GENCTL_CI}/onepipeline/jobs/generate_auth_json.sh

# Ensure Docker auth was created before continuing.
if [[ ! -f "${DOCKER_CONFIG}/config.json" ]]; then
    echo "Error: Failed to create ${DOCKER_CONFIG}/config.json"
    exit 1
fi

# Create the local oc-mirror workspace directory if it does not already exist.
echo "Create working directory"
mkdir -p ocp_mirror_work_dir

# Install required tooling and run the workspace build/mirror logic.
echo "Running OCP mirror for release"
install_pkgs
install_oc_cli

${PATH_TO_WORKSPACE_REPO}/hack/ci/build.sh

ZIP_FILE_NAME="${PATH_TO_GENCTL_CI}/deployment_files.zip"

# If we have ZIP file, upload it
if [[ -f "${ZIP_FILE_NAME}" ]]
then
    BASIC_PATH_IN_ARTIFACTORY="${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_PRE_RELEASE_DIR}/${ORG_AND_REPO}/${PR_ID}"
    URL_TO_UPLOAD_ZIP="${BASIC_PATH_IN_ARTIFACTORY}/deployment_files.zip"

    upload_file_to_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${URL_TO_UPLOAD_ZIP}" "deployment_files.zip"
else
    echo "Could not find ${ZIP_FILE_NAME} in ${PWD}"
fi
