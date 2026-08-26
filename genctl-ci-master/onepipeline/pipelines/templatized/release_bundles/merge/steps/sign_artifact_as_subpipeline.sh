#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This step implements standard OnePipeline signing process running within csso-image-sign and call ciso/sign_artifactory.sh
# Latest image version to be used from: https://github.ibm.com/one-pipeline/compliance-commons-internal/blob/master/one-pipeline-defaults.yaml#L47
# Signing script code location: https://github.ibm.com/one-pipeline/compliance-commons-internal/blob/master/ciso/sign_artifactory.sh
# sign_artifactory.sh signs images that were saved as artifact in previous stage: https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/onepipeline/pipelines/templatized/merge_dev_integration/steps/test.sh#L68-L69
# due to the issue #  the signing script can sign only images located in artifactory and can not in ICR. This is why we need to save_artifact ICR images
# after signing stage is completed
# The following environment variables are required for sign_artifactory.sh
#  artifactory-docker-repo-name = wcp-genctl-docker-local
#  artifactory-primary-service = na
#  artifactory-sigstore-repo-name = wcp-genctl-sandbox-generic-local
#  taas-artifactory-token = Default.wcp-genctl-docker-local-artifactory-token
#  taas-artifactory-user = Default.wcp-genctl-docker-local-artifactory-username
# OnePipeline signing documenttion: https://test.cloud.ibm.com/docs/devsecops?topic=devsecops-devsecops-imagesigning

### Actual call to signing ###
/opt/commons/ciso/sign_artifactory.sh

### VPC CI Code ###

# Since we are running on the signing image we need to change the yq version
pip3 install yq==2.7.2

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="release_bundles"

INITIAL_PIPELINE_TYPE="merge"
get_pipeline_type "${PIPELINE_RUN_BRANCH}" "${INITIAL_PIPELINE_TYPE}" "${REPO_MAIN_BRANCH}"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="false"

# Get parent pipeline information
get_parent_pipeline_info

### Upload inventory pre release files ###
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "UPLOAD_FILES" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/inventory_candidate_files/create_and_upload_files.sh 