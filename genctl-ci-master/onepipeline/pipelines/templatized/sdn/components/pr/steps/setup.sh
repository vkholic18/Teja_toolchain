#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
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
export PIPELINE_TEMPLATE_TYPE="sdn-components"

INITIAL_PIPELINE_TYPE="pr"
get_pipeline_type "${PR_BASEBRANCH}" "${INITIAL_PIPELINE_TYPE}" "${REPO_MAIN_BRANCH}"

# Basic logging info
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/basic_logging_info.sh

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# To have same effect that in concourse of in this template not having SKIP_CHECK_PR_TITLE
export SKIP_CHECK_PR_TITLE=""

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the SSH
eval "$(ssh-agent -s)" # Check if needed here
ssh-add - <<< "${GIT_PRIVATE_KEY}" # Check if needed here

# Set the flag that indicates if exit when a job fails
export EXIT_ON_JOB_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

### All Scans ###
run_job "ALL_SCANS" ${EXIT_ON_JOB_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/jobs/all_scans_artifacts.sh

### Build ###
run_job "BUILD" ${EXIT_ON_JOB_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/jobs/build.sh

### Execute Static code scan using Mend SAST, set EXIT_ON_JOB_FAILURE to false
export EXIT_ON_JOB_FAILURE="false"
run_job "CODE_STATIC_SCAN" ${EXIT_ON_JOB_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/jobs/run_static_scan.sh
