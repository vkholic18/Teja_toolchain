#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO
# ARTIFACTORY_USER, CC_ARTIF_ACCESS_TOKEN
# GIT_PRIVATE_KEY
# CC_GITHUB_TOKEN
# VAULT_GIT_CONFIG_USER_EMAIL, VAULT_GIT_CONFIG_USERNAME
# CC_ARTIFACTORY_READER, CC_ARTIFACTORY_READER_APIKEY
# GPG_SIGNING_KEY, GPG_SIGNING_PW
# GHE_USERNAME, GHE_RO_TOKEN

# The following environment variables can be set before executing the script, if not they will use default values (Can be empty)

# ARTIFACTORY_DOCKER_URL, ARTIFACTORY_SANDBOX_DOCKER_URL
# CC_ARTIFACTORY_SANDBOX_DOCKER_URL

# =============================================================================================
set -eu
# Set default values (Important since we have u flag and we can't have unbound variables)

export ARTIFACTORY_DOCKER_URL=${ARTIFACTORY_DOCKER_URL:-""}
export ARTIFACTORY_SANDBOX_DOCKER_URL=${ARTIFACTORY_SANDBOX_DOCKER_URL:-""}
export IS_ONE_PIPELINE_RUN=${IS_ONE_PIPELINE_RUN:-"false"}
export ICR_MIGRATION_MODE=${ICR_MIGRATION_MODE:-"false"} # By default we are not pushing images to ICR
export VPC_ICR_SANDBOX_URL=${VPC_ICR_SANDBOX_URL:-""}
export IBMCLOUD_CR_URL_ONEPIPELINE=${IBMCLOUD_CR_URL_ONEPIPELINE:-""}
export DISABLE_ARTIFACTORY_PUSH=${DISABLE_ARTIFACTORY_PUSH:-"false"} # By default create manifests for Artifactory

source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh 

echo -e "${BYellow}Create Manifest starts at: $(date)............. ${NC}"
START=$(date +%s)


##############
# used for upload deb in image-service-workspace with put_to_artifactory common repo function called by image-service-workspace hack/ci/build.sh
export TR_ARTIFACTORY_LOGIN="${ARTIFACTORY_USER}"
export TR_ARTIFACTORY_ACCESS_TOKEN="${CC_ARTIF_ACCESS_TOKEN}"
##############

export DOCKER_REGISTRY_PUSH_URL
cd ${PATH_TO_WORKSPACE_REPO}
if [[ ! -z ${ARTIFACTORY_DOCKER_URL} && ${DISABLE_ARTIFACTORY_PUSH} == false ]]; then
    DOCKER_REGISTRY_PUSH_URL=${ARTIFACTORY_DOCKER_URL}
    echo "Creating manifests for the images existed in ${DOCKER_REGISTRY_PUSH_URL}"
    ${PATH_TO_GENCTL_CI}/scripts/process_build_meta_v11.sh process_image_manifests
elif [[ ! -z ${ARTIFACTORY_DOCKER_URL} && ${DISABLE_ARTIFACTORY_PUSH} == true ]]; then
    echo "Skipping Artifactory production manifest creation (DISABLE_ARTIFACTORY_PUSH=true)"
fi

# Create manifests for the images in ICR prod url
if [[ ! -z ${IBMCLOUD_CR_URL_ONEPIPELINE} && ${ICR_MIGRATION_MODE} == true ]]; then
    # Upload to prod only if the repo we are building is from a prod org
    if repo_is_from_prod_org ${PATH_TO_WORKSPACE_REPO}
    then                        
        DOCKER_REGISTRY_PUSH_URL=${IBMCLOUD_CR_URL_ONEPIPELINE}
        echo "Creating manifests for the images existed in ${DOCKER_REGISTRY_PUSH_URL}"
        ${PATH_TO_GENCTL_CI}/scripts/process_build_meta_v11.sh process_image_manifests
    else
        echo "Seems the repository is not from a production organization (For example, it might be a fork) ..."
    fi
fi

if [[ ! -z ${ARTIFACTORY_SANDBOX_DOCKER_URL} && ${DISABLE_ARTIFACTORY_PUSH} == false ]]; then
    DOCKER_REGISTRY_PUSH_URL=${ARTIFACTORY_SANDBOX_DOCKER_URL}
    echo "Creating manifests for the images existed in ${DOCKER_REGISTRY_PUSH_URL}"
    ${PATH_TO_GENCTL_CI}/scripts/process_build_meta_v11.sh process_image_manifests
elif [[ ! -z ${ARTIFACTORY_SANDBOX_DOCKER_URL} && ${DISABLE_ARTIFACTORY_PUSH} == true ]]; then
    echo "Skipping Artifactory sandbox manifest creation (DISABLE_ARTIFACTORY_PUSH=true)"
fi

# Create manifests for the images in ICR sanbox url
if [[ ! -z ${VPC_ICR_SANDBOX_URL} && ${ICR_MIGRATION_MODE} == true ]]; then    
    DOCKER_REGISTRY_PUSH_URL=${VPC_ICR_SANDBOX_URL}
    echo "Creating manifests for the images existed in ${DOCKER_REGISTRY_PUSH_URL}"
    ${PATH_TO_GENCTL_CI}/scripts/process_build_meta_v11.sh process_image_manifests
fi

echo "Created all manifests"

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Create Manifest ends at: $(date)............. ${NC}"
echo -e "${BYellow}Create Manifest took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete............. ${NC}"
