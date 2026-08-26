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

python3 -m pip install -q ${PATH_TO_GENCTL_CI}/tools/ci_python_tools
pip3 install -r ${PATH_TO_GENCTL_CI}/scripts/generateFFSLD/requirements.txt

function generate_ffsld_for_ve(){
    python3 ${PATH_TO_GENCTL_CI}/scripts/generate_ffslds_for_ve.py -f $PATH_TO_DEV_REGIONS_REPO
}

generate_ffsld_for_ve

echo "push to COS"
${PATH_TO_GENCTL_CI}/scripts/ffsld_upload_to_cos/ffsld_upload_to_cos.sh ${PATH_TO_DEV_REGIONS_REPO}/FFSLD_ARTIFACTS

