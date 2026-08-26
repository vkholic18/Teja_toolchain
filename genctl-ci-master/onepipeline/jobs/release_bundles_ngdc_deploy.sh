#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Source lock utils
source ${PATH_TO_GENCTL_CI}/tools/lock_and_queue_utils/multiple_locks_grouped/multiple_locks_grouped.sh

# Set the flag that exits if the task failed
EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

# Configuration required for working with the git remote (Needed for acquire/release lock)
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

function ensure(){
    # This function releases all the locks that were acquired

    # This function assumes some environment variables like 
    # CI_TEMP_DIR, PATH_TO_GENCTL_CI
    
    PTGCI=${1} # The path to genctl ci repo
    PTRLR=${2} # The path to the resourcelock repo
    LTR=${3} # The locks to release
    CM=${4} # String used for git commit when releasing
    ATT=${5} # Max attempts to release lock
    SLP=${6} # Sleep time between attempts for lock release
    
    # The resource lock branch name or if not set, master
    RLBN=${7:-"master"}

    # First check if we have file with created roles; if yes, delete them
    if [[ -f "${CI_TEMP_DIR}/created_roles.txt" ]]
    then
        export ROLES_TO_DELETE=$(cat ${CI_TEMP_DIR}/created_roles.txt)
        python3 ${PATH_TO_GENCTL_CI}/tools/ngdc/delete_netbox_context_role.py
    fi

    release_multiple_locks "${PTGCI}" "${PTRLR}" "${LTR}" "${CM}" ${ATT} ${SLP} "${RLBN}"
}

# We get from the parent pipeline the commit msg, this is used to release the lock
export PARENT_PIPELINE_MULTIPLE_LOCKS_COMMIT_MSG=$(get_env ci_parent_pipeline_multiple_locks_commit_msg)

# For easier use, set a var with path to the yaml
path_to_pipeline_yaml_file="${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml"

# In the ensure function we could just access them as they are environment variables, but we prefer pass them to make this little bit safer...
trap 'ensure ${PATH_TO_GENCTL_CI} ${PATH_TO_RESOURCELOCK_REPO} "${final_nodes_to_deploy}" "${PARENT_PIPELINE_MULTIPLE_LOCKS_COMMIT_MSG}" 360 10 ${RESOURCELOCK_NGDC_BRANCH_NAME}' EXIT

# Get info from parent pipeline
get_parent_pipeline_info

# Need to switch to branches for few repos:

# CD script we use for deployment is on a specific branch, so we need to check out to it
pushd ${PATH_TO_GENCTL_CD}
git fetch
git checkout "${GENCTL_CD_NGDC_SUPPORT_BRANCH}" --
popd

# In addition, NGDC locks are also on a specific branch 
pushd ${PATH_TO_RESOURCELOCK_REPO}
git fetch
git checkout "${RESOURCELOCK_NGDC_BRANCH_NAME}" --
popd

# First check that the pipeline.yaml file exists
if [[ -f "${path_to_pipeline_yaml_file}" ]]
then
    # Check that the file has the proper section
    deployment_ngdc_section_exists=$(yq ". | has(\"deployment_ngdc\")" "${path_to_pipeline_yaml_file}")

    if [[ "${deployment_ngdc_section_exists}" == "true" ]]
    then
        # Get the names of the deployments_and_tests and check we have something
        deployments_and_tests_names=$(yq -r '.deployment_ngdc.deployments_and_tests[].name' "${path_to_pipeline_yaml_file}")

        if [[ ! -z "${deployments_and_tests_names}" ]]
        then
            # Iterate over the deployments_and_tests
            for d_and_t_name in ${deployments_and_tests_names}
            do
                # Get the mode
                mode=$(yq -r ".deployment_ngdc.deployments_and_tests[] | select(.name == \"${d_and_t_name}\").mode" "${path_to_pipeline_yaml_file}")

                # Get the nodes, will be used later
                nodes_to_deploy=$(yq -r ".deployment_ngdc.deployments_and_tests[] | select(.name == \"${d_and_t_name}\").nodes[]" "${path_to_pipeline_yaml_file}")

                # Do some processing
                processed_nodes_to_deploy=""
                for n in ${nodes_to_deploy}
                do 
                    processed_nodes_to_deploy="${processed_nodes_to_deploy} $n"
                done
                final_nodes_to_deploy=$(echo ${processed_nodes_to_deploy} | tr -d '\n')

                # Claim (Should not stop on error)
                set +e
                acquire_multiple_locks "${PATH_TO_GENCTL_CI}" "${PATH_TO_RESOURCELOCK_REPO}" \
                "${final_nodes_to_deploy}" "${PARENT_PIPELINE_MULTIPLE_LOCKS_COMMIT_MSG}" 900 10 "${RESOURCELOCK_NGDC_BRANCH_NAME}"

                if [ "${mode}" == "override" ]
                then
                    # In override mode, we do an approach of creating "temporary roles" based on the ones defined in the YAML
                    # To differentiate them we add them a suffix
                    SHORT_PR_HEAD_SHA=${PR_HEADSHA:0:12}
                    export TMP_ROLES_SUFFIX="_${PIPELINE_REPO_NAME}_${SHORT_PR_HEAD_SHA}_${d_and_t_name}_ci_temp"
                    
                    # Call python script that generates file that we use to export ROLE_HOSTNAMES
                    export PATH_TO_PIPELINE_YAML=${path_to_pipeline_yaml_file}
                    export D_AND_T=${d_and_t_name}
                    python3 ${PATH_TO_GENCTL_CI}/tools/ngdc/generate_role_hostnames_file.py

                    # Check file was created and export
                    if [[ -f "role_hostnames_result.json" ]]
                    then
                        export ROLE_HOSTNAMES="$(cat role_hostnames_result.json)"
                    else
                        echo "At this point we should have a file role_hostnames_result.json"
                        echo "Will exit with error..."
                        exit 1
                    fi

                    # At this point we can assume we have only one role defined in the list
                    export EXISTING_ROLES=$(yq -r ".deployment_ngdc.deployments_and_tests[] | select(.name == \"${d_and_t_name}\").roles[0]" "${path_to_pipeline_yaml_file}")

                    # Install netbox python library as is required for few scripts
                    python3 -m pip install pynetbox==7.3.3

                    # Create temporary role based on existing ones                    
                    python3 ${PATH_TO_GENCTL_CI}/tools/ngdc/create_netbox_context_role.py

                    # Check file was created and export
                    # Since we are in override mode we can assume we have only one role on the file
                    # NOTE: This file can contain role that was either actually created on this run or it exists for some reason from a previous run
                    if [[ $? -eq 0 && -f "${CI_TEMP_DIR}/created_roles.txt" ]]
                    then
                        # This is used in update netbox script
                        export ROLES_TO_GET_NETBOX_BUNDLES_FROM="$(cat "${CI_TEMP_DIR}/created_roles.txt")"
                    else
                        echo "Something went wrong when creating role"
                        echo "Will exit with error..."
                        exit 1
                    fi

                    # Export environment vars for update netbox python script
                    export BUNDLE_NAME_FOR_REPLACE_VERSION="${PIPELINE_REPO_NAME}"
                    export VERSION_TO_REPLACE="${PR_HEADSHA}"
                    export ART_VALUE_TO_REPLACE_IN_TESTED_BUNDLE="${ARTIFACTORY_DOCKER_PATH}/${COMPONENT}/"
                    export ART_VALUE_TO_REPLACE_IN_VETTED="${ARTIFACTORY_DOCKER_PATH}/${COMPONENT}/"
                    export PATH_TO_VETTED_VERSION_FILES_FOR_REPLACEMENT="${PATH_TO_VETTED_VERSIONS_REPO}/${GENCTL_VETTED_VERSIONS_FILE}"
                    export INVENTORY_REPO_BRANCH=${PR_BASEBRANCH} # This is used to get from the right branch in inventory

                    # Update the created role
                    python3 ${PATH_TO_GENCTL_CI}/tools/ngdc/update_netbox_bundles_data.py

                    if [[ $? -eq 0 ]]
                    then
                        echo "Succesfully updated netbox"
                    else
                        echo "Something went wrong when updating netbox"
                        echo "Will exit with error..."
                        exit 1
                    fi

                    # Handle the undercloud file
                    undercloud_file_defined_in_yaml_info=$(yq ".deployment_ngdc.deployments_and_tests[] | select(.name == \"${d_and_t_name}\") | has(\"undercloud_file\")" "${path_to_pipeline_yaml_file}")

                    if [[ "${undercloud_file_defined_in_yaml_info}" == "true" ]]
                    then
                        echo "We found undercloud_file key defined in YAML; we will use that instead of default..."
                        export UNDERCLOUD_FILE=$(yq -r ".deployment_ngdc.deployments_and_tests[] | select(.name == \"${d_and_t_name}\").undercloud_file" "${path_to_pipeline_yaml_file}")
                    else
                        echo "No undercloud_file key defined in YAML; will use default undercloud file..."
                        export UNDERCLOUD_FILE=${DEFAULT_UNDERCLOUD_FILE}
                    fi

                    serviceAttributes_defined_in_yaml_info=$(yq ".deployment_ngdc.deployments_and_tests[] | select(.name == \"${d_and_t_name}\") | has(\"serviceAttributes\")" "${path_to_pipeline_yaml_file}")

                    if [[ "${serviceAttributes_defined_in_yaml_info}" == "true" ]]
                    then
                        echo "We found serviceAttributes key defined in YAML; we will pass additional serviceAttributes ..."
                        SERVICE_ATRIBUTE_KEY=$(yq -r ".deployment_ngdc.deployments_and_tests[] | select(.name == \"${d_and_t_name}\").serviceAttributes.attributekey" "${path_to_pipeline_yaml_file}")
                        SERVICE_ATRIBUTE_VALUE=$(yq -r ".deployment_ngdc.deployments_and_tests[] | select(.name == \"${d_and_t_name}\").serviceAttributes.attributevalue" "${path_to_pipeline_yaml_file}")
                        SERVICE_ATRIBUTE_TYPE=$(yq -r ".deployment_ngdc.deployments_and_tests[] | select(.name == \"${d_and_t_name}\").serviceAttributes.attributetype" "${path_to_pipeline_yaml_file}")

                        export SERVICE_ATTRIBUTES="[ {\"attributekey\":\"${SERVICE_ATRIBUTE_KEY}\",\"attributevalue\":\"${SERVICE_ATRIBUTE_VALUE}\",\"attributetype\":\"${SERVICE_ATRIBUTE_TYPE}\"} ]"
                        echo SERVICE_ATTRIBUTES: ${SERVICE_ATTRIBUTES}
                    else
                        echo "serviceAttributes is not defined"
                    fi
                else
                    echo "Not supported yet"
                fi

                # # At this point we should have exported the following environment variables
                # # 1. ROLE_HOSTNAMES
                # # 2. In addition we might have either ROLE_OVERRIDES or ROLE_PATCHES (But not both of them)
                
                echo "********************************************"
                echo "Before calling CD NGDC deployment script we have the following environment variables:"
                echo "UNDERCLOUD_FILE=${UNDERCLOUD_FILE}"
                echo "ROLE_HOSTNAMES=${ROLE_HOSTNAMES}"
                echo "ROLE_OVERRIDES=${ROLE_OVERRIDES}"
                echo "ROLE_PATCHES=${ROLE_PATCHES}"
                echo "ATTRIBUTE_KEY=${ATTRIBUTE_KEY}"
                echo "ATTRIBUTE_VALUE=${ATTRIBUTE_VALUE}"
                echo "SERVICE_ATTRIBUTES: ${SERVICE_ATTRIBUTES}"

                echo "ENV_TYPE=${ENV_TYPE}"
                echo "DEPLOYMENT_ZONE=${DEPLOYMENT_ZONE}"
                echo "LOGICAL_ZONE=${LOGICAL_ZONE}"
                echo "LOGICAL_REGION=${LOGICAL_REGION}"
                echo "********************************************"

                # Call CD script
                run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "NGDC_DEPLOY" ${EXIT_ON_TASK_FAILURE} \
                ${PATH_TO_GENCTL_CD}/ngdc/toolchain-scripts/fnds_deploy.sh

                if [ "${mode}" == "override" ]
                then
                    # Delete temporary created role
                    export ROLES_TO_DELETE=$(cat ${CI_TEMP_DIR}/created_roles.txt)
                    python3 ${PATH_TO_GENCTL_CI}/tools/ngdc/delete_netbox_context_role.py
                fi
                
                # Unclaim (Should not stop on error)
                set +e
                release_multiple_locks "${PATH_TO_GENCTL_CI}" "${PATH_TO_RESOURCELOCK_REPO}" \
                "${final_nodes_to_deploy}" "${PARENT_PIPELINE_MULTIPLE_LOCKS_COMMIT_MSG}" 900 10 "${RESOURCELOCK_NGDC_BRANCH_NAME}"
            done
        else
            # Later implement this as a hard stop
            echo "No deployments_and_tests defined"
            #echo "Will exit with error..."
            #exit 1
        fi
    else
        # Later implement this as a hard stop
        echo "Can't proceed to deploy NGDC without section deployment_ngd on pipeline.yaml file"
        #echo "Will exit with error"
        #exit 1
    fi
else
    echo "pipeline.yaml file with NGDC provisioning configuration does not exists"
    echo "Will exit with error..."
    exit 1
fi
