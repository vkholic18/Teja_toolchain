#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
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

# Required environment variables:
# - CC_ARTIF_ACCESS_TOKEN
# - ARTIFACTORY_USER
# - RHOS_IMAGE_PULL_SECRET (existing JSON with auths)

pushd ${PATH_TO_WORKSPACE_REPO}


source ${PATH_TO_CICD_UTILS}/onepipeline/utils/load_secrets.sh \
    --secret-list "sg-uuc-core-services-ocp-image-pull-secret" \
    --env-vars-to-export "RHOS_IMAGE_PULL_SECRET"

if [[ -n "${RHOS_IMAGE_PULL_SECRET}" ]]; then
    echo "RHOS_IMAGE_PULL_SECRET is set"
else
    echo "RHOS_IMAGE_PULL_SECRET is not set or is empty."
fi

# Generate base64 encoded auth string for artifactory
ARTIFCATORY_AUTH=$(echo -n "${ARTIFACTORY_USER}:${CC_ARTIF_ACCESS_TOKEN}" | base64 -w0)

# Check if RHOS_IMAGE_PULL_SECRET is set
if [[ -z "${RHOS_IMAGE_PULL_SECRET}" ]]; then
    echo "Error: RHOS_IMAGE_PULL_SECRET environment variable is not set"
    exit 1
fi

# Parse the existing JSON and add the new artifactory entry
# Using jq to merge the new entry into the existing auths object
echo "${RHOS_IMAGE_PULL_SECRET}" | jq --arg auth "${ARTIFCATORY_AUTH}" \
  '.auths["docker-na-public.artifactory.swg-devops.com"] = {"auth": $auth}' > temp_sec_artifactory/config.json

echo "Authentication JSON file created successfully with merged entries"

popd
