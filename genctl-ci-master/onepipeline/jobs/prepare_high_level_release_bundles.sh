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

set +x  # so we will not log the password
echo "loging in ${ARTIFACTORY_DOCKER_PROXY_URL}"
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_PROXY_URL} -u ${ARTIFACTORY_USER} --password-stdin
set -x

# By default we prepare all the bundles
COMPONENT_RELEASE_BUNDLES=${COMPONENT_RELEASE_BUNDLES:-"genctl rias-etcd rias"}

if [[ "$COMPONENT_RELEASE_BUNDLES" =~ (^|[[:space:]])"genctl"($|[[:space:]]) ]]
then
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "PREPARE_GENCTL_RELEASE_BUNDLE" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/prepare-genctl-release-bundle.sh

fi

if [[ "$COMPONENT_RELEASE_BUNDLES" =~ (^|[[:space:]])"rias"($|[[:space:]]) ]]
then
    export PATH_TO_RELEASE_REPO=${PATH_TO_RIAS_RELEASE_REPO}
    export RELEASE_BUNDLE_IMAGE_NAME=${RIAS_RELEASE_BUNDLE_IMAGE_NAME}
    export NEXTGEN_SERVICE_DEPLOYER_RELEASE_IMAGE_NAME=${NEXTGEN_SERVICE_DEPLOYER_RIAS_RELEASE_IMAGE_NAME}
    
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "PREPARE_RIAS_RELEASE_BUNDLE" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/prepare-rias-release-bundle.sh
fi

if [[ "$COMPONENT_RELEASE_BUNDLES" =~ (^|[[:space:]])"rias-etcd"($|[[:space:]]) ]]
then
    export PATH_TO_RELEASE_REPO=${PATH_TO_RIAS_ETCD_RELEASE_REPO}
    export RELEASE_BUNDLE_IMAGE_NAME=${RIAS_ETCD_RELEASE_BUNDLE_IMAGE_NAME}
    export NEXTGEN_SERVICE_DEPLOYER_RELEASE_IMAGE_NAME=${NEXTGEN_SERVICE_DEPLOYER_RIAS_ETCD_RELEASE_IMAGE_NAME}

    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "PREPARE_RIAS_ETCD_RELEASE_BUNDLE" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/prepare-rias-release-bundle.sh
fi