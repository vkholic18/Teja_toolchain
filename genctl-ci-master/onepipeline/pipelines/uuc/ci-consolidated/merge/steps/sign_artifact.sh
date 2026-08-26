#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="uuc-ci"

PIPELINE_TYPE="merge"

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

# ### Signing ###
# run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "SIGNING" ${EXIT_ON_TASK_FAILURE} \
# ${PATH_TO_GENCTL_CI}/onepipeline/scripts/signing_v11.sh "onepipeline/pipelines/uuc/ci-consolidated/merge/.pipeline-config-subpipeline-signing.yaml"

### Actual call to signing ###
if [[ ${DISABLE_ARTIFACTORY_PUSH} == true ]]; then
    echo "DISABLE_ARTIFACTORY_PUSH is true, using ICR signing"
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "SIGNING" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/onepipeline/scripts/signing_v11.sh "onepipeline/pipelines/uuc/ci-consolidated/merge/.pipeline-config-subpipeline-signing-icr.yaml"
else
    echo "DISABLE_ARTIFACTORY_PUSH is false, using Artifactory signing"
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "SIGNING" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/onepipeline/scripts/signing_v11.sh "onepipeline/pipelines/uuc/ci-consolidated/merge/.pipeline-config-subpipeline-signing-artifactory.yaml"
fi
