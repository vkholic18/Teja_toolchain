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

# Required environment variables (supplied by the pipeline runtime):
#   PATH_TO_GENCTL_CI              - path to the one-pipeline-config-repo checkout
#   ONE_PIPELINE_CI_IBM_CLOUD_API_KEY - IBM Cloud API key used by downstream scripts
#   CI_TEMP_DIR                    - scratch directory for temporary artefacts
#   SKIP_CI_FAILURE_ANALYSIS       - set to "true" to bypass analysis (default: false)

source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/analyse_logs.sh
