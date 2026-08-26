#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI
# SECRET_PATH (Used by onepipeline to generate IAM token)

# In addition the following variables are optional and if not have values they will take the default

DYNAMIC_SCAN_STAGE_NAME=${DYNAMIC_SCAN_STAGE_NAME:-"dynamic-scan-as-subpipeline"}
DYNAMIC_SCAN_TRIGGER_TO_USE=${DYNAMIC_SCAN_TRIGGER_TO_USE:-"taas-worker-trigger"}
WAIT_FOR_FINISH=${WAIT_FOR_FINISH:-"false"} # By default dynamic scan run on fire & forget mode, therefore we set false
CUSTOM_SUB_PIPELINE_CONFIG=$1

# Dynamic scan might take long time so setting a bigger number of retries
# Math is: 
# Up to 1200 attempts, sleeping 30 seconds between each attempt = 36000 seconds 
# 36000 seconds / 60 = 600 minutes = 10 Hours
export MAX_ATTEMPTS_BUSY_WAIT=1200

${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_v11.sh ${DYNAMIC_SCAN_STAGE_NAME} ${DYNAMIC_SCAN_TRIGGER_TO_USE} ${WAIT_FOR_FINISH} ${CUSTOM_SUB_PIPELINE_CONFIG}
