#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI

# In addition the following variables are optional and if not have values they will take the default

RIAS_SMOKE_STAGE_NAME=${RIAS_SMOKE_STAGE_NAME:-"rias-smoke-as-subpipeline"}
RIAS_SMOKE_TRIGGER_TO_USE=${RIAS_SMOKE_TRIGGER_TO_USE:-"taas-worker-trigger"}

# Smoke Tests might take long time so setting a bigger number of retries
# Math is: 
# Up to 900 attempts, sleeping 30 seconds between each attempt = 28800 seconds 
# 28800 seconds / 60 = 480 minutes = 8 Hours
export MAX_ATTEMPTS_BUSY_WAIT=960

${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline.sh ${RIAS_SMOKE_STAGE_NAME} ${RIAS_SMOKE_TRIGGER_TO_USE}
