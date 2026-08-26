#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script handles the new process build-meta logic for packages

# The supported modes are:
        # upload
        # download_and_save_artifacts
        # move_from_pre_release_to_vetted
        # move_from_vetted_to_final_destination

# The following environment variables need to be set before executing the script:

# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO, ORG_AND_REPO
# ARTIFACTORY_BASE_URL, CC_ARTIF_ACCESS_TOKEN
# ARTIFACTORY_DEBIAN_SANDBOX_REPO_PATH
# ARTIFACTORY_GOLANG_BINARIES_SANDBOX_REPO_PATH
# ARTIFACTORY_TAR_SANDBOX_REPO_PATH

# The following environment variables need to be set if mode is upload
# CI_ARTIFACTS_TO_UPLOAD_DIR
# PACKAGES_PRE_RELEASE_DIR

# THe following environment variables need to be set if mode is download_and_save_artifacts
# CI_ARTIFACTS_TO_DOWNLOAD_DIR
# PACKAGES_PRE_RELEASE_DIR
# PACKAGES_PATH_TO_USE_IN_ARTIFACT_FIELD_IN_JSON

# The following environment variables need to be set if mode is move_from_pre_release_to_vetted
# PACKAGES_PRE_RELEASE_DIR, PACKAGES_VETTED_DIR

# The following environment variables need to be set if mode is move_from_vetted_to_final_destination
# PACKAGES_VETTED_DIR
# ARTIFACTORY_DEBIAN_REPO_PATH
# ARTIFACTORY_GOLANG_BINARIES_REPO_PATH
# ARTIFACTORY_TAR_REPO_PATH

# Optional
export SHA_TO_USE_FOR_SEARCH_PACKAGES=${SHA_TO_USE_FOR_SEARCH_PACKAGES:-""}

# Some variables
supported_process_modes="upload download_and_save_artifacts move_from_pre_release_to_vetted move_from_vetted_to_final_destination"
supported_packages_types="debian golang tar rpm"
debian_regex="_.*_.*\.deb"
tar_regex="-.*\.tar\.gz"
golang_regex="_.*_.*"
rpm_regex="_.*_.*\.rpm"

# Source required utils
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Check if we are in a valid mode and show it
# If mode is not valid, exit

# Set the path to the build-meta.yaml in a variable for easier use
PATH_TO_BUILD_META="${PATH_TO_WORKSPACE_REPO}/hack/ci/build-meta.yaml"

# Check build-meta.yaml file exists
if [ -f "${PATH_TO_BUILD_META}" ]
then

    # Get the mode
    process_mode=$1

    # If we got a SHA, prefer it
    if [[ ! -z "${SHA_TO_USE_FOR_SEARCH_PACKAGES}" ]]
    then
        echo "Process build meta packages will prefer SHA: ${SHA_TO_USE_FOR_SEARCH_PACKAGES}"
        SHORT_SHA=${SHA_TO_USE_FOR_SEARCH_PACKAGES:0:12}
    else
        # If we didn't get a SHA, assume we want to use current SHA

        # Get the SHA and its short version
        pushd ${PATH_TO_WORKSPACE_REPO}
        GIT_SHA=$(git rev-parse --verify HEAD)
        SHORT_SHA=${GIT_SHA:0:12}
        popd
    fi

    # Check the mode is supported
    if [[ "$supported_process_modes" =~ (^|[[:space:]])$process_mode($|[[:space:]]) ]]
    then
        # Get all the packages
        packages=$(yq -r '.packages | select(. != null)' "${PATH_TO_BUILD_META}")

        # Check if any package
        if [[ -n ${packages} ]]; then

            # Get the types of packages we need to process
            package_types=$(echo ${packages} | yq -r 'keys[] | select(. != null)')

            # Iterate over the packages types
            for package_type in ${package_types}; do

                # Check if is a valid package type
                if [[ "$supported_packages_types" =~ (^|[[:space:]])$package_type($|[[:space:]]) ]]
                then
                      echo "Will process packages of type $package_type"

                    # Set the proper regex
                    if [[ ${package_type} == "debian" ]]; then
                        package_regex_to_search_for_upload=${debian_regex}
                        package_sandbox_repo=${ARTIFACTORY_DEBIAN_SANDBOX_REPO_PATH}
                        package_prod_repo=${ARTIFACTORY_DEBIAN_REPO_PATH}
                    elif [[ ${package_type} == "golang" ]]; then
                        package_regex_to_search_for_upload=${golang_regex}
                        package_sandbox_repo=${ARTIFACTORY_GOLANG_BINARIES_SANDBOX_REPO_PATH}
                        package_prod_repo=${ARTIFACTORY_GOLANG_BINARIES_REPO_PATH}
                    elif [[ ${package_type} == "tar" ]]; then
                        package_regex_to_search_for_upload=${tar_regex}
                        package_sandbox_repo=${ARTIFACTORY_TAR_SANDBOX_REPO_PATH}
                        package_prod_repo=${ARTIFACTORY_TAR_REPO_PATH}
                    elif [[ ${package_type} == "rpm" ]]; then
                        package_regex_to_search_for_upload=${rpm_regex}
                        package_sandbox_repo=${ARTIFACTORY_RPM_SANDBOX_REPO_PATH}
                        package_prod_repo=${ARTIFACTORY_RPM_REPO_PATH}
                    fi

                    # For each type of package we might have multiple architectures, iterate over them
                    meta_arches=$(yq -r ".packages.${package_type} | keys | .[]" "${PATH_TO_BUILD_META}")
                    
                    for meta_arch in ${meta_arches}
                    do
                        if [[ ${package_type} == "debian" ]]; then
                            artifact_meta=";deb.distribution=bionic;deb.component=main;deb.architecture=${meta_arch}"
                        elif [[ ${package_type} == "golang" ]]; then
                            artifact_meta=";golang.metadata.arch=${meta_arch}"
                        elif [[ ${package_type} == "tar" ]]; then
                            artifact_meta=";tar.metadata.arch=${meta_arch}"
                        elif [[ ${package_type} == "rpm" ]]; then
                            artifact_meta=";rpm.metadata.arch=${meta_arch}"
                        fi

                        # Get the packages list for the relevant package type and architecture
                        meta_package_list=$(yq -r ".packages.${package_type}.${meta_arch} | select(. != null) | if type==\"string\" then . else .[] end" "${PATH_TO_BUILD_META}")
                        
                        if [[ ${meta_package_list} != "" ]]; then # If the architecture doesn't have any values specified in it
                            echo "The following packages were found for package type ${package_type} and architecture ${meta_arch}"
                            echo ${meta_package_list}
                            
                            # At this point, verify that we have important parts of the URL and if any of it is empty, exit 1
                            if [[ ! -z "${ARTIFACTORY_BASE_URL}" ]] && [[ ! -z "${package_sandbox_repo}" ]] && [[ ! -z "${ORG_AND_REPO}" ]]
                            then
                                for package in ${meta_package_list}
                                do
                                    # This is to build what we call "workspace desired path"
                                    # It is the path in artifactory AFTER the fixed path we define 

                                    # Workspaces can control this by defining the package name with slashes
                                    # We will take up to the last slash as this desired
                                    
                                    # For example if the package is defined in the YAML as: cloudnet/fabcon-cli-versions/fabcon-cli
                                    # then workspace_desired_path_in_artifactory will be cloudnet/fabcon-cli-versions
                                    
                                    # Important note: If the package does not have any slash then we will set as workspace_desired_path_in_artifactory the package name itself
                                    if [[ "$package" == *"/"* ]]
                                    then
                                        workspace_desired_path_in_artifactory=$(dirname ${package}) # We use dirname to keep all the path until the last /
                                    else 
                                        workspace_desired_path_in_artifactory=${package}
                                    fi

                                    # Remove all the slashes and keep the last part
                                    # For example if the package is defined in the YAML as: pool/compute/proxy/cld-computeproxy
                                    # then file_name_to_search will be cld-computeproxy
                                    file_name_to_search=$(echo ${package} | sed -e 's/^.*\///')

                                    # # At this point, we can build few useful paths (Without filename)
                                    path_to_package_after_repo_and_destination="${ORG_AND_REPO}/${SHORT_SHA}/${package_type}/${meta_arch}/${workspace_desired_path_in_artifactory}"
                                    pre_release_path_after_url="${package_sandbox_repo}/${PACKAGES_PRE_RELEASE_DIR}/${path_to_package_after_repo_and_destination}"
                                    vetted_path_after_url="${package_sandbox_repo}/${PACKAGES_VETTED_DIR}/${path_to_package_after_repo_and_destination}"
                                    final_destination_path_after_url="${package_prod_repo}/${workspace_desired_path_in_artifactory}"

                                    if [[ "${process_mode}" == "upload" ]]
                                    then
                                        echo "### UPLOAD MODE ###"

                                        # Check we have the PACKAGES_PRE_RELEASE_DIR
                                        if [[ ! -z "${PACKAGES_PRE_RELEASE_DIR}" ]]
                                        then
                                            # Move to the directory where the files to upload should be the present
                                            # Each workspace has to ensure that the packages are in this folder in their build.sh/makefile
                                            pushd "${CI_ARTIFACTS_TO_UPLOAD_DIR}"
                                            
                                            # Find
                                            echo "Will find in directory ${PWD} files that match regex .*${file_name_to_search}${package_regex_to_search_for_upload}"
                                            result=$(find -regextype posix-extended -regex ".*${file_name_to_search}${package_regex_to_search_for_upload}")
                                            
                                            # If we found, process
                                            if [[ ! -z ${result} ]]; then
                                                found_file_name=$(echo "$result" | sed 's|^./||')
                                                
                                                echo "Found local file ${found_file_name}, in directory ${PWD}"
                                                
                                                # Add the filename
                                                full_path_in_artifactory="${ARTIFACTORY_BASE_URL}/${pre_release_path_after_url}/${found_file_name}"

                                                # If needed, include the metadata
                                                if [[ $PROCESS_BUILD_META_UPLOAD_PACKAGES_INCLUDE_METADATA = true ]]; then
                                                    echo "Will include metadata of the package"
                                                    full_path_in_artifactory="${full_path_in_artifactory}${artifact_meta}"
                                                fi

                                                # Dry run mode
                                                if [[ $PROCESS_BUILD_META_DRY_RUN_MODE = true ]]; then
                                                    echo "DRY RUN MODE !!! - We would have uploaded file ${found_file_name} to ${full_path_in_artifactory}"
                                                else
                                                    upload_file_to_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${full_path_in_artifactory}" "${found_file_name}" "10" "true"
                                                fi
                                            else 
                                                echo "Could not find local file matching what is described in build-meta.yaml"
                                                echo "Seems something went wrong in a previous step... Exiting with error"
                                                exit 1
                                            fi
                                            popd
                                        else
                                            echo "PACKAGES_PRE_RELEASE_DIR is empty, can't move forward with upload mode"
                                            exit 1
                                        fi
                                    elif [[ "${process_mode}" == "download_and_save_artifacts" ]]
                                    then
                                        echo "### DOWNLOAD AND SAVE ARTIFACTS MODE ###"

                                        # Source save artifacts utils
                                        source ${PATH_TO_GENCTL_CI}/onepipeline/utils/save_artifacts_utils.sh
                                        
                                        # Move to temporary download dir
                                        pushd "${CI_ARTIFACTS_TO_DOWNLOAD_DIR}"

                                        if [[ "${PACKAGES_PATH_TO_USE_IN_ARTIFACT_FIELD_IN_JSON}" == "pre_release" ]]
                                        then
                                            repo_for_artifact_field="${package_sandbox_repo}/${PACKAGES_PRE_RELEASE_DIR}/${ORG_AND_REPO}/${SHORT_SHA}/${package_type}/${meta_arch}"
                                        elif [[ "${PACKAGES_PATH_TO_USE_IN_ARTIFACT_FIELD_IN_JSON}" == "vetted" ]]
                                        then
                                            repo_for_artifact_field="${package_sandbox_repo}/${PACKAGES_VETTED_DIR}/${ORG_AND_REPO}/${SHORT_SHA}/${package_type}/${meta_arch}"
                                        elif [[ "${PACKAGES_PATH_TO_USE_IN_ARTIFACT_FIELD_IN_JSON}" == "final_destination" ]]
                                        then
                                            repo_for_artifact_field="${package_prod_repo}"
                                        else
                                            echo "${PACKAGES_PATH_TO_USE_IN_ARTIFACT_FIELD_IN_JSON} is not a valid value for PACKAGES_PATH_TO_USE_IN_ARTIFACT_FIELD_IN_JSON"
                                            echo "Will exit with error..."
                                            exit 1
                                        fi

                                        save_artifact_package "${ARTIFACTORY_BASE_URL}" "${CC_ARTIF_ACCESS_TOKEN}" \
                                        "${package_sandbox_repo}" "${PACKAGES_PRE_RELEASE_DIR}" \
                                        "${ORG_AND_REPO}" "${GIT_SHA}" "${package_type}" "${meta_arch}" \
                                        "${workspace_desired_path_in_artifactory}" "${repo_for_artifact_field}" "${file_name_to_search}"
                                        
                                        # Come back
                                        popd 
                                    elif [[ "${process_mode}" == "move_from_pre_release_to_vetted" ]]
                                    then
                                        echo "### MOVE FROM PRE-RELEASE TO VETTED ###"
                                        
                                         # First get the name
                                        get_file_name_in_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${ARTIFACTORY_BASE_URL}" \
                                        "${pre_release_path_after_url}" "${file_name_to_search}"

                                        # Then move from pre-release to vetted
                                        from="${pre_release_path_after_url}/${FOUND_FILE_NAME_IN_ARTIFACTORY}"
                                        to="${vetted_path_after_url}/${FOUND_FILE_NAME_IN_ARTIFACTORY}"

                                        if [[ $PROCESS_BUILD_META_DRY_RUN_MODE = true ]]; then
                                            echo "DRY RUN MODE !!! - We would have moved from ${from} to ${to}"
                                        else
                                            move_in_artifactory ${CC_ARTIF_ACCESS_TOKEN} ${ARTIFACTORY_BASE_URL} ${from} ${to}
                                        fi

                                    elif [[ "${process_mode}" == "move_from_vetted_to_final_destination" ]]
                                    then
                                        echo "### MOVE FROM VETTED TO FINAL DESTINATION ###"
                                        
                                        # First get the name
                                        get_file_name_in_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${ARTIFACTORY_BASE_URL}" \
                                        "${vetted_path_after_url}" "${file_name_to_search}"

                                        # Then move from pre-release to vetted
                                        from="${vetted_path_after_url}/${FOUND_FILE_NAME_IN_ARTIFACTORY}"
                                        to="${final_destination_path_after_url}/${FOUND_FILE_NAME_IN_ARTIFACTORY}"

                                        if [[ $PROCESS_BUILD_META_DRY_RUN_MODE = true ]]; then
                                            echo "DRY RUN MODE !!! - We would have moved from ${from} to ${to}"
                                        else
                                            move_in_artifactory ${CC_ARTIF_ACCESS_TOKEN} ${ARTIFACTORY_BASE_URL} ${from} ${to}
                                        fi                                    
                                    fi
                                done
                            else
                                echo "The URL that we built for upload/download is missing some parts, please check it"
                                echo "ARTIFACTORY_BASE_URL: ${ARTIFACTORY_BASE_URL} / package_sandbox_repo: ${package_sandbox_repo} / ORG_AND_REPO: ${ORG_AND_REPO}"
                                exit 1
                            fi 
                        else
                            echo "No packages found for package type ${package_type} and architecture ${meta_arch}"
                        fi
                    done
                else
                    echo "Package type $package_type is not supported"
                fi
            done
        else
            echo "No packages found in build-meta.yaml ..."
        fi
    else
        echo "Process mode $process_mode is not supported for packages"
    fi
else
    echo "Could not find build-meta.yaml file under ${PATH_TO_WORKSPACE_REPO}/hack/ci"
    echo "Can't process packages without build-meta.yaml file; will exit with error"
    exit 1
fi