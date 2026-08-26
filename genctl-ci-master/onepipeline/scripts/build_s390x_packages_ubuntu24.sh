#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, IBMCLOUD_KEY, SKIP_BUILD_S390X_PACKAGES_UBUNTU24

# In addition the following variables are optional and if not have values they will take the default

BUILD_S390X_STAGE_NAME=${BUILD_S390X_STAGE_NAME:-"build-s390x-packages-ubuntu24-as-subpipeline"}
BUILD_S390X_TRIGGER_TO_USE=${BUILD_S390X_TRIGGER_TO_USE:-"build-s390x-packages-ubuntu24"}

#This can be removed once we get new agent
CUSTOM_SUB_PIPELINE_CONFIG=$1

if [[ $SKIP_BUILD_S390X_PACKAGES_UBUNTU24 = true ]]; then
    echo "Skipping..."
else
    # build s390x images might take long time so setting a bigger number of retries
    # Math is:
    # Up to 500 attempts, sleeping 30 seconds between each attempt = 15000 seconds
    # 15000 seconds / 60 = 300 minutes = 5 Hours
    export MAX_ATTEMPTS_BUSY_WAIT=500

    ${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_v11.sh ${BUILD_S390X_STAGE_NAME} ${BUILD_S390X_TRIGGER_TO_USE} "" ${CUSTOM_SUB_PIPELINE_CONFIG}
fi