#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
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

if [[ -z "${COMPONENT}" ]]
then
    echo "In order to prepare release bundles, we need environment variable COMPONENT to be set, currently is not set"
    echo "Will exit with error..."
    exit 1
else
    echo "Component is: ${COMPONENT}"
    if [[ "$LOW_LEVEL_RELEASE_BUNDLE_TYPES" =~ (^|[[:space:]])$COMPONENT($|[[:space:]]) ]]
    then
        echo "Component is a low level release bundle"
        run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "PREPARE_RELEASE_BUNDLE" ${EXIT_ON_TASK_FAILURE} \
        ${PATH_TO_GENCTL_CI}/scripts/prepare_low_level_release_bundle.sh
    elif [[ "$HIGH_LEVEL_RELEASE_BUNDLE_TYPES" =~ (^|[[:space:]])$COMPONENT($|[[:space:]]) ]]
    then
        echo "Component is a high level release bundle"
        run_job "PREPARE_RELEASE_BUNDLES" ${EXIT_ON_JOB_FAILURE} \
        ${PATH_TO_GENCTL_CI}/onepipeline/jobs/prepare_high_level_release_bundles.sh
    else 
        echo echo "Component is neither low level nor high level release bundle"
        echo "Will exit with error..."
        exit 1
    fi
fi