#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
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

# By default we bump all the components
COMPONENT_RELEASE_BUNDLES=${COMPONENT_RELEASE_BUNDLES:-"genctl rias-etcd rias"}

if [[ "$COMPONENT_RELEASE_BUNDLES" =~ (^|[[:space:]])"rias"($|[[:space:]]) ]]
then
    export REPO_NAME_TO_BUMP=${RIAS_RELEASE_REPO_NAME}
    export ORG_NAME_TO_BUMP=${RIAS_RELEASE_ORG_NAME}
    export BRANCH_TO_BUMP=${RIAS_RELEASE_BRANCH}

    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "BUMP_RIAS" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/bump_rias_component.sh
fi

if [[ "$COMPONENT_RELEASE_BUNDLES" =~ (^|[[:space:]])"genctl"($|[[:space:]]) ]]
then
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "BUMP_GENCTL" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/bump_genctl_component.sh
fi

if [[ "$COMPONENT_RELEASE_BUNDLES" =~ (^|[[:space:]])"rias-etcd"($|[[:space:]]) ]]
then
    export REPO_NAME_TO_BUMP=${RIAS_ETCD_RELEASE_REPO_NAME}
    export ORG_NAME_TO_BUMP=${RIAS_ETCD_RELEASE_ORG_NAME}
    export BRANCH_TO_BUMP=${RIAS_ETCD_RELEASE_BRANCH}

    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "BUMP_RIAS_ETCD" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/bump_rias_component.sh
fi