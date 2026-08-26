#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
# This script is meant to ensure that the ffsld is scaled up, if it was scaled down
# It also sends a slack to notify the end of the promotion tests, in case of failures

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

RELEASE_BUNDLE="-RB-"

# Skip ffsld scaled up when branch is release bundle
if [[ $PR_BRANCH == *$RELEASE_BUNDLE* ]]; then
  echo "$PR_BRANCH contains $RELEASE_BUNDLE, skipping"
  return 0
fi

if [[ ${FF_SETLD_REPLICAS} == ${RAZEE_FF_SETLD_REPLICAS_MIN} ]]; then
    ### Scale up ###
    export FF_SETLD_REPLICAS=${RAZEE_FF_SETLD_REPLICAS_MAX}
    echo "Scaling ffsld back up ..."
    ${PATH_TO_GENCTL_CI}/scripts/scale_ffsld_controller_promotion.sh

    ### Send slack notification to announce the end of the promotion tests ###
    echo "Sending slack message to notify cluster unlock"
    export SLACK_ICON=":scm-unlock:"
    export STATUS="Unlocking cluster for promotion testing"
    export STATUS_OPS="Unlocking cluster for OPS promotion testing"
    ${PATH_TO_GENCTL_CI}/scripts/cd/go-notify-promotion-tests.sh
elif [[ ${FF_SETLD_REPLICAS} == ${RAZEE_FF_SETLD_REPLICAS_MAX} ]]; then
  echo "ffsld is already scaled up. Skipping the scale operation."
else
  echo "Unknown error. Manually verify that the cluster has ${RAZEE_FF_SETLD_REPLICAS_MAX} ffsld replicas."
fi
