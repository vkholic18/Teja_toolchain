#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script verifies that a component is part of inventory

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO, COMPONENT, RAZEE_CLUSTER_ENVIRONMENT

# Set flags
set -ex

echo "COMPONENT: ${COMPONENT}"
echo "RAZEE_CLUSTER_ENVIRONMENT: ${RAZEE_CLUSTER_ENVIRONMENT}"

# check if component exist genctl inventory. If not exit
# used in the genctl pipelines to build release bundles if the component is shared with rias
if [[ -n "${COMPONENT}" ]];  then
    echo "check if the component ${RIAS_COMPONENT} is a shared genctl component"
    set +e
    python3 ${PATH_TO_GENCTL_CI}/scripts/exist_in_inventory_razee.py ${COMPONENT} ${PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO}/hack/deploy/razee/${RAZEE_CLUSTER_ENVIRONMENT}
    result=$?
    echo $result
    set -e
    if [[ ${result} == 0 ]]; then
    echo "component ${COMPONENT} exists in the environment ${RAZEE_CLUSTER_ENVIRONMENT}."
    exit 0
    elif [[ ${result} == 100 ]]; then
    echo "component ${COMPONENT} does not exist in the environment ${RAZEE_CLUSTER_ENVIRONMENT}."
    exit 1
    else
    echo "error in searching the component ${COMPONENT} in the environment ${RAZEE_CLUSTER_ENVIRONMENT}."
    exit 1
    fi
fi
