#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, IBMCLOUD_KEY, SKIP_ONE_PIPELINE_SIGNING

# In addition the following variables are optional and if not have values they will take the default

SIGNING_STAGE_NAME=${SIGNING_STAGE_NAME:-"sign-artifact-as-subpipeline"}
SIGNING_TRIGGER_TO_USE=${SIGNING_TRIGGER_TO_USE:-"sign-artifact-trigger"}
CUSTOM_SUB_PIPELINE_CONFIG=$1

if [[ $SKIP_ONE_PIPELINE_SIGNING = true ]]; then
    echo "Skipping..."
else
    # signing might take long time so setting a bigger number of retries
    # Math is:
    # Up to 360 attempts, sleeping 30 seconds between each attempt = 10800 seconds
    # 10800 seconds / 60 = 180 minutes = 3 Hours
    export MAX_ATTEMPTS_BUSY_WAIT=360

    ${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_v11.sh ${SIGNING_STAGE_NAME} ${SIGNING_TRIGGER_TO_USE} "" ${CUSTOM_SUB_PIPELINE_CONFIG}
fi
