#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
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

# Preparation for ICR scan
# Basically:
# Pulling from artifactory
# Saving artifacts with ICR url
# Pushing to ICR so images will be scanned

if [[ "${SKIP_VA_SCAN}" == "true" ]]; then
    echo "VA Scan Skipped: The VA scan artifact was skipped due to an ongoing VA service outage in us-south. The issue is tracked under IRM: ISS0024698."
else

    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "PREPARE_FOR_ICR_SCAN" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/onepipeline/scripts/prepare_for_icr_scan.sh

    # Run One Pipeline scan images script
    /opt/commons/scan-artifact/scan.sh
fi
