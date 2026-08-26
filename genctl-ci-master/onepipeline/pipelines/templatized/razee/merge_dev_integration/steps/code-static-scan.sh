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
# Source retry logic
source ${PATH_TO_GENCTL_CI}/scripts/retry.sh

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="razee"

export PIPELINE_TYPE="dev-integration-merge"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

popd

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

MEND_SAST_METADATA=$(yq -r '.mend_sast_info' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
if [[ -z "$MEND_SAST_METADATA" ]];
then
    echo "Mend SAST metadata not found in pipeline.yaml file. Unable to proceed with the scan."
    exit 1
fi

set_env mend-product-name "$MEND_PRODUCT_NAME"
set_env mend-user-email "$MEND_USER_EMAIL"

retry python3 -m pip install -q -r ${PATH_TO_GENCTL_CI}/scripts/fetch_secrets_from_secrets_manager/requirements.txt
python3 ${PATH_TO_GENCTL_CI}/scripts/fetch_secrets_from_secrets_manager/fetch_mend_secrets.py -se $VPC_CI_UNIVERSAL_SECRETS_MANAGER_PUBLIC_ENDPOINT -ck $ONE_PIPELINE_CI_IBM_CLOUD_API_KEY -sg $MEND_SECRET_GROUP

if [ -f "./mend-sast-info.sh" ]; then    
    [ -x "./mend-sast-info.sh" ] || chmod +x ./mend-sast-info.sh
    source ./mend-sast-info.sh    
    # set_env mend-project-name-branch-suffix "$BASE_BRANCH"
    set_env mend-product-name "$MEND_PRODUCT_NAME"
    set_env mend-user-email "$MEND_USER_EMAIL"    
    /opt/commons/static-scan/run.sh
else
    echo "mend-sast-info.sh file not found! Failed to run the Mend SAST Scan..."
    exit 1
fi
