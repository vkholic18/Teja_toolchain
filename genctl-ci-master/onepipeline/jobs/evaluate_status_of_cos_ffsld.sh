#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
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

if [[ -z ${RULE_TAG} ]]; then
    RULE_TAG=$(yq -r '.deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
fi

for RULE in ${RULE_TAG//,/ }; do
    if [[ $RULE != *"mzone"* ]]; then
        RIAS_AND_RIAS_ETCD_RULE_TAG=$RULE
    else
        MZONE_RULE_TAG=$RULE
    fi
done
echo "GENCTL_GLOBALS_STATUS"
if [ -n "$MZONE_RULE_TAG" ]; then
    GENCTL_GLOBALS_STATUS=$(find ${PATH_TO_GENCTL_GLOBALS_REPO} -name ${MZONE_RULE_TAG}-globals.json -type f -print -exec cat {} \; | grep "use_ffsld_controller")
    echo "GENCTL_GLOBALS_STATUS: ${GENCTL_GLOBALS_STATUS}"
fi
echo "RIAS_GLOBALS_STATUS"
if [ -n "$RIAS_AND_RIAS_ETCD_RULE_TAG" ]; then
    # Check rias-etcd globals
    if [[ ${RIAS_AND_RIAS_ETCD_RULE_TAG} == *"etcd"* ]]; then
        RIAS_GLOBALS_STATUS=$(find ${PATH_TO_RIAS_ETCD_RELEASE_REPO} -name ${RIAS_AND_RIAS_ETCD_RULE_TAG}.json -type f -print -exec cat {} \; | grep "use_ffsld_controller")
    else
        RIAS_GLOBALS_STATUS=$(find ${PATH_TO_RIAS_GLOBALS_REPO} -name ${RIAS_AND_RIAS_ETCD_RULE_TAG}.json -type f -print -exec cat {} \; | grep "use_ffsld_controller")
    fi
    echo "RIAS_GLOBALS_STATUS: ${RIAS_GLOBALS_STATUS}"
fi
if [[ $GENCTL_GLOBALS_STATUS =~ "false" ]] || [[ $RIAS_GLOBALS_STATUS =~ "false" ]]; then
    export COS_FFSLD_ENABLED=true
    echo "COS is enabled for FFSLD"
else
    export COS_FFSLD_ENABLED=false
    echo "COS is not enabled for FFSLD"
fi
