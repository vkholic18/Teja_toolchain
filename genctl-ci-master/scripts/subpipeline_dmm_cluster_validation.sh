#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI

# In addition the following variables are optional and if not have values they will take the default

CLUSTER_VALIDATION_STAGE_NAME=${CLUSTER_VALIDATION_STAGE_NAME:-"cluster-validation-as-subpipeline"}
CLUSTER_VALIDATION_TRIGGER_TO_USE=${CLUSTER_VALIDATION_TRIGGER_TO_USE:-"vpc-ci-private-worker-trigger"}

# Math is: 
# Up to 600 attempts, sleeping 30 seconds between each attempt = 18000 seconds
# 18000 seconds / 60 = 300 minutes = 5 Hours
export MAX_ATTEMPTS_BUSY_WAIT=600

${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline.sh ${CLUSTER_VALIDATION_STAGE_NAME} ${CLUSTER_VALIDATION_TRIGGER_TO_USE}
