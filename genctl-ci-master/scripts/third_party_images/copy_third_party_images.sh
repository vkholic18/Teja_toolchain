#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script copies third party images that are uploaded by devs, changing the tag and adding prefix
# Currently it copies as the following

# From artifactory sandbox to artifactory sandbox (Retag)
# From artifactory sandbox to artifactory prod

# The following environment variables need to be set before executing the script:
# PATH_TO_WORKSPACE_REPO

# =============================================================================================

# Set flags
set -e

# Define path to the file
third_party_images_yaml_file="${PATH_TO_WORKSPACE_REPO}/${THIRD_PARTY_IMAGES_YAML_FILE_PATH}"

# First check if the file exists at all
if [ -f "${third_party_images_yaml_file}" ]
then
    # Create a temporary dir that will hold the file
    export PATH_TO_IMAGES_TO_COPY="${CI_TEMP_DIR}/tmp_third_party_dir"
    mkdir "${PATH_TO_IMAGES_TO_COPY}"
            
    # Generate a file with the list of the images
    yq -r '.images[]' "${third_party_images_yaml_file}" > "${PATH_TO_IMAGES_TO_COPY}/final_image_list.txt"

    # Check the file got created and is not empty...
    if [[ ! -s "${PATH_TO_IMAGES_TO_COPY}/final_image_list.txt" ]]
    then
        echo "Image file does not exists or is empty"
        echo "Will exit with error..."
        exit 1
    fi
    
    # Get SHA and print it
    current_sha=$(load_repo app-repo commit)
    echo "Current SHA is: ${current_sha}"

    # Check if we are in razee
    if [[ "${PIPELINE_TEMPLATE_TYPE}" == "razee" ]]
    then

        # Pull from sandbox

        export PULL_REGISTRY=${VPC_ICR_SANDBOX_URL}
        export PULL_REGISTRY_API_KEY=${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}
        export PULL_REGISTRY_USER=""
        export PULL_REGISTRY_PASSWORD=""

        # Push to sandbox
        export PUSH_REGISTRY=${ARTIFACTORY_SANDBOX_DOCKER_URL}
        export PUSH_REGISTRY_USER=${ARTIFACTORY_USER}
        export PUSH_REGISTRY_PASSWORD=${CC_ARTIF_ACCESS_TOKEN}

        export DO_NOT_OVERWRITE="true"
        export FAIL_ON_IMAGE_PULL_FAILURE="true"
        export VERIFY_COPIED_IMAGES_CAN_BE_PULLED="true"

        export COPY_IMAGES_RETAG_MODE="true"
        export RETAG_PREFIX_TO_IMAGE="third-party-images/${PIPELINE_REPO_NAME}"
        export RETAG_SPECIFIC_TAG_TO_PUSH=${current_sha}

        # In PR to dev-integration we copy from sandbox to prod adding prefix and re-tagging tag with SHA of PR to dev-int
        if [[ "${PIPELINE_TYPE}" = "dev-integration-pr" ]]
        then
            # This pulls from sandbox and pushes to sandbox with the SHA of PR to dev-int and prefix
            # For example

            # Pull from:
            # us.icr.io/vpc-sandbox-docker-local/sysdig/agent-slim:13.4.0
            # And push to:
            # docker-na-public.artifactory.swg-devops.com/wcp-genctl-sandbox-local/third-party-images/monitoring-workspace/sysdig/agent-slim:ecdb58e849472e08321779760baae89397ce623b
            ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

            # Additional run with prod (Pull from sandbox and push to prod)
            export PUSH_REGISTRY=${ARTIFACTORY_DOCKER_URL}
            export PUSH_REGISTRY_USER=${ARTIFACTORY_USER}
            export PUSH_REGISTRY_PASSWORD=${CC_ARTIF_ACCESS_TOKEN}
            ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

        elif [[ "${PIPELINE_TYPE}" = "dev-integration-merge" ]]
        then
            # This pulls from sandbox and pushes to sandbox with the SHA of merge to dev-int and prefix
            # For example

            # Pull from:
            #us.icr.io/vpc-sandbox-docker-local/sysdig/agent-slim:13.4.0
            # And push to: 
            # docker-na-public.artifactory.swg-devops.com/wcp-genctl-sandbox-local/third-party-images/monitoring-workspace/sysdig/agent-slim:ecdb58e849472e08321779760baae89397ce623b
            ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

            # Additional run with prod (Pull from sandbox and push to prod)
            export PUSH_REGISTRY=${ARTIFACTORY_DOCKER_URL}
            export PUSH_REGISTRY_USER=${ARTIFACTORY_USER}
            export PUSH_REGISTRY_PASSWORD=${CC_ARTIF_ACCESS_TOKEN}
            ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

            # This pulls from sandbox and pushes to sandbox with the semver of merge to dev-int and prefix
            # For example

            # Pull from:
            # docker-na-public.artifactory.swg-devops.com/wcp-genctl-sandbox-docker-local/sysdig/agent-slim:13.4.0
            # And push to: 
            # docker-na-public.artifactory.swg-devops.com/wcp-genctl-sandbox-local/third-party-images/monitoring-workspace/sysdig/agent-slim:1.117.0-dev.2
            export PUSH_REGISTRY=${ARTIFACTORY_SANDBOX_DOCKER_URL}

            # Get semver
            pushd ${PATH_TO_WORKSPACE_REPO}
            semver=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true
            popd

            export RETAG_SPECIFIC_TAG_TO_PUSH=${semver}

            ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh

            # Additional run with prod (Pull from sandbox and push to prod)
            export PUSH_REGISTRY=${ARTIFACTORY_DOCKER_URL}
            ${PATH_TO_GENCTL_CI}/scripts/copy_images.sh
        fi
    fi 
else
    echo "No third party images file..."
fi