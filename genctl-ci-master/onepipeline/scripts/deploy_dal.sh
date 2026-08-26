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

DEPLOY_DAL_STAGE_NAME=${DEPLOY_DAL_STAGE_NAME:-"deploy-dal-as-subpipeline"}
DEPLOY_DAL_TRIGGER_TO_USE=${DEPLOY_DAL_TRIGGER_TO_USE:-"vpc-ci-private-worker-trigger"}

# Deploy Dal might take long time so setting a bigger number of retries
# Math is: 
# Up to 600 attempts, sleeping 30 seconds between each attempt = 18000 seconds 
# 18000 seconds / 60 = 300 minutes = 5 Hours
export MAX_ATTEMPTS_BUSY_WAIT=600

${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline.sh ${DEPLOY_DAL_STAGE_NAME} ${DEPLOY_DAL_TRIGGER_TO_USE}