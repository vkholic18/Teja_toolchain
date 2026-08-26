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

BRT_STAGE_NAME=${BRT_STAGE_NAME:-"brt-as-subpipeline"}
BRT_TRIGGER_TO_USE=${BRT_TRIGGER_TO_USE:-"taas-worker-trigger"}

# BRTs might take long time so setting a bigger number of retries
# Math is: 
# Up to 1200 attempts, sleeping 30 seconds between each attempt = 36000 seconds 
# 36000 seconds / 60 = 600 minutes = 10 Hours
export MAX_ATTEMPTS_BUSY_WAIT=1200

${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline.sh ${BRT_STAGE_NAME} ${BRT_TRIGGER_TO_USE}