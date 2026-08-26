#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
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

# Source retry logic
source ${PATH_TO_GENCTL_CI}/scripts/retry.sh

if [[ ${RUN_STATIC_SCAN_IN_PR_TO_DEV_INT} == "true" ]] || [[ ${RUN_STATIC_SCAN_IN_PR} == "true" ]] || [[ $SKIP_CODE_STATIC_SCAN = "false" ]]; then
    echo "Mend SAST enabled in PR pipeline, executing the scan..."
    MEND_SAST_METADATA=$(yq -r '.mend_sast_info' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
    if [[ -z "$MEND_SAST_METADATA" ]];
    then
        echo "Mend SAST metadata not found in pipeline.yaml file. Unable to proceed with the scan."
        exit 1
    fi
    retry python3 -m pip install -q -r ${PATH_TO_GENCTL_CI}/scripts/fetch_secrets_from_secrets_manager/requirements.txt
    python3 ${PATH_TO_GENCTL_CI}/scripts/fetch_secrets_from_secrets_manager/fetch_mend_secrets.py -se $VPC_CI_UNIVERSAL_SECRETS_MANAGER_PUBLIC_ENDPOINT -ck $ONE_PIPELINE_CI_IBM_CLOUD_API_KEY -sg $MEND_SECRET_GROUP    
    if [ -f "./mend-sast-info.sh" ]; then
        [ -x "./mend-sast-info.sh" ] || chmod +x ./mend-sast-info.sh
        source ./mend-sast-info.sh
        set_env opt-in-mend-sast "1"
        set_env mend-server-url "https://ibmets.whitesourcesoftware.com"
        set_env mend-product-name "$MEND_PRODUCT_NAME"
        set_env mend-user-email "$MEND_USER_EMAIL"
        set_env mend-exclude-paths-file "scan_excludes.txt"
        set_env mend-suppressions-file "suppressions.json"
        set_env mend-print-scan-summaries "1"
        set_env mend-print-scan-results	"1"
        run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "${CODE_STATIC_SCAN_CHECK_LABEL}" ${EXIT_ON_TASK_FAILURE_CODE_STATIC_SCAN} \
        "/opt/commons/static-scan/run.sh"
    else
        echo "mend-sast-info.sh file not found! Failed to run the Mend SAST Scan..."
        exit 1
    fi
else
    echo "Skipping Mend SAST static scan..."
fi
