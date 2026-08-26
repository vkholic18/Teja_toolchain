#!/bin/bash

## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2021
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================

set -eu

# This script contains all the code for processing the build-meta.yaml file, separated into applicable functions
# and is intended to be called after the images and packages for an architecture have been built for a repository.

# The main function of this code will call the function to process the entire build-meta.yaml file
# To use specific functions, instead run this file like so: `. ./process_build_meta.sh --source-only`

# Script Requirements
# - hack/ci/build-meta.yaml file must exist in the repository (or this script is run with ${BUILD_META_PATH} defined correctly)
# - the login to the docker repository/repositories has already been done
# - The base image this script runs in includes docker
# Highly recommended:
# - This script is called from the root of the repository
#   - This isn't required as the path to the build_meta file can be specified as a param now, however not using the root
#     of the repository may make it difficult to find the packages (and/or debug)

# configurable values:
# ${Optional Environment Variable:-default value}
upload_images=${UPLOAD_IMAGES:-true}
upload_packages=${UPLOAD_PACKAGES:-true}
command_retries=${COMMAND_RETRIES:-3}
path_to_build_meta_file=${BUILD_META_PATH:-"./hack/ci/build-meta.yaml"}
artifactory_base_url=${ARTIFACTORY_BASE_URL:-"https://na.artifactory.swg-devops.com/artifactory"}
debian_push_url=${DEBIAN_PUSH_URL:-"wcp-genctl-platform-nextgen-debian-local"}
rpm_push_url=${RPM_PUSH_URL:-"wcp-genctl-platform-nextgen-rpm-local"}
golang_push_url=${GOLANG_PUSH_URL:-"wcp-genctl-sandbox-generic-local"}
# Key Format: Name (Comment) <email>
signing_key_uid="NextGen VPC CI (GPG Signing Key) <clconc@us.ibm.com>"
signing_key="${GPG_PRIVATE_KEY:-}"
# Override this variable by passing in "SIGN_PACKAGES" set to true. This variable is used with the build-meta.yaml file
sign_packages=${SIGN_PACKAGES:-false}
# Variable indicating if gpg has been setup / is ready to sign
is_gpg_signing_setup=false
is_rpm_signing_setup=false

# "safe" attempts to install missing dependencies over exiting with an error stating that the dependencies are not met.
# "strict" will not attempt to install missing dependencies, will return a message with the missing dependency, and exit
check_dependency_mode=${CHECK_DEPENDENCY_MODE:-"safe"}

TR_ARTIFACTORY_ACCESS_TOKEN=${TR_ARTIFACTORY_ACCESS_TOKEN:-""}
CC_ARTIF_ACCESS_TOKEN=${CC_ARTIF_ACCESS_TOKEN:-$TR_ARTIFACTORY_ACCESS_TOKEN}

# Upload mode related
CI_UPLOAD_PACKAGES_MODE=${CI_UPLOAD_PACKAGES_MODE:-"legacy"} # By default we keep existing functionality

# Paths used in "new" mode
PATH_TO_GENCTL_CI=${PATH_TO_GENCTL_CI:-""}
CI_ARTIFACTS_TO_UPLOAD_DIR=${CI_ARTIFACTS_TO_UPLOAD_DIR:-""}

# The following flags are evaluated/used only when mode is "new"
CI_UPLOAD_PACKAGES_DRY_RUN_MODE=${CI_UPLOAD_PACKAGES_DRY_RUN_MODE:-"false"}
CI_UPLOAD_PACKAGES_INCLUDE_METADATA=${CI_UPLOAD_PACKAGES_INCLUDE_METADATA:-"false"}
CI_UPLOAD_PACKAGES_CHECK_AND_FAIL_IF_PACKAGE_EXISTS=${CI_UPLOAD_PACKAGES_CHECK_AND_FAIL_IF_PACKAGE_EXISTS:-"false"}

# Vars with regexes for specific package types
debian_regex="_.*_.*\.deb"
rpm_regex="-+.+\.rpm"
golang_regex="_.*_.*"

# This is for local testing of the script
if [[ $(uname) == "Darwin" ]]; then
    echo "MacOS test environment detected; changing find executable to gnu find"
    export PATH=/usr/local/opt/findutils/libexec/gnubin:$PATH
fi

# The safe_retry_command function is used to retry a command up to command_retries times if it results in an error.
# On encountering the error threshold, it will:
# - print a message stating all the retries were expended due to failures, and that it's exiting w/ error
# - restore the original options prior to entering the safe_retry_command function
# - exit with the return code of the last error
function safe_retry_command(){
  options=$- # store the set options into a var to reset the options after we're done with the code that needs some flag disabled

  # Turn off exiting when a command returns a non-zero status code; we want to do some retries on a failure
  # Also turn off verbose mode since the command may contain a secret in it that we don't want to display
  set +ex

  # space separated variable values that contain information that should not be output in the command echo
  secret_vars="${CC_ARTIF_ACCESS_TOKEN} "

  # Run the sed command on the command we're going to display to the user to replace secrets with REDACTED
  displayed_command=$(echo "$*")
  for secret in ${secret_vars}
  do
     displayed_command=$(echo "$displayed_command" | sed "s,${secret},REDACTED,g")
  done

  # Determine if the command is a curl command, if so, we need to do a couple curl-specific checks
  # so that the code will fails when it should (while preventing the curl checks from breaking this function for
  # other commands)
  if [[ $* =~ ^curl ]]; then
    is_curl_command=true
  else
    is_curl_command=false
  fi

  retries=${command_retries}
  echo "${displayed_command}" # print out the command that will be run, without secrets displayed
  while [[ ${retries} -gt 0 ]];
  do
    retries=$[retries-1]
    if [[ is_curl_command == true ]]; then
      response=$($*) # Run the command
      return_code=$? # Get the return code from the last command
      if [[ ${response} -ne 200 ]] || [[ ${response} -ne 201 ]] && [[ ${return_code} -ne 0 ]]; then
        echo "Error: Command returned status code of ${response}, and a return code of ${return_code}"
        echo "Warning: Failed to execute command successfully, retries remaining: ${retries}"
      else
        echo "Success: Command returned status code of ${response}, and a return code of ${return_code}"
        break # If we got a status code of zero, break out of the loop
      fi
      if [[ ${retries} == 0 ]]; then
        echo "Error: All retries expended due to failures, exiting with error"
        set -${options} # In case this function is used and the error is wrapped, we want to ensure we restore the original options
        # We need to check the return code and ensure we don't pass a "0" when exiting (if the response code of the command was not OK)
        if [[ ${return_code} -ne 0 ]]; then
          exit ${return_code}
        else
          exit 1
        fi
      fi
    else # not a curl command, do the following:
      $* && break # $* runs the command, if successful, exits the while loop.
      returnCode=$? # get return code of the command to use it if we need to exit with a failure
      echo -e "\nWarning: Failed to execute command successfully, retries remaining: ${retries}"
      if [[ ${retries} == 0 ]]; then
          echo "Error: All retries expended due to failures, exiting with error"
          set -${options} # In case this function is used and the error is wrapped, we want to ensure we restore the original options
          exit ${returnCode}
      fi
    fi
  done
  set -${options}
}

# Echos out the system architecture to get captured via caller - e.g. build_sys_arch=$(get_system_arch)
# Also converts "x86_64" to "amd64" to compare with the architecture specified in the build-meta.yaml file.
function get_system_arch(){
  local build_sys_arch=$(uname -m)
  if [[ ${build_sys_arch} == "x86_64" ]]; then
    echo "amd64"
  else
    echo "${build_sys_arch}"
  fi
}

# Contains the logic to handle the 'packages' part of the build-meta.yaml file.
# Checks the build system's architecture so that we error out if we cannot find the packages we should have found,
# and do not error out if we don't find the packages for a different architecture
# Sets up the upload location based on the package type using variables set from env vars, or defaults if available
function process_packages(){
  concourse_default_path="."
  path_to_packages=${1:-"/home/travis/build"}
  process_package_types=${2:-"all"}

  # We need to know what architecture we're running in so we can determine what should be present to be uploaded
  echo "processing packages..."
  echo "Info: build system architecture is $(get_system_arch)"

  packages=$(yq -r '.packages | select(. != null)' ${path_to_build_meta_file})
  if [[ -n ${packages} ]]; then
    if [[ "${CI_UPLOAD_PACKAGES_MODE}" = "new" ]]; then
      # This is the "new" upload mode, in order to use it there are few pre-requisites:

      # 1.  The artifacts that will be uploaded should exist in the local file system where this code runs
      #     Specifically, they need to be in ${CI_ARTIFACTS_TO_UPLOAD_DIR}
      # 2.  The build-meta.yaml should have the relevant structure, specifically for each package specification
      #     the logic applied is the following:

      # from the beginning to the package until the last /, is the path in artifactory to where we will upload
      # after the last slash, is the name that will be combined with the relevant regex (According to the package type)
      # in order to find it locally

      # For example, if the package is defined in build-meta as: pool/compute/localdisk-tools/cld-localdisk-tools
      # Means that we will:
      # Find under the ${CI_ARTIFACTS_TO_UPLOAD_DIR} directory, a file that matches the relevant regex with name cld-localdisk-tools
      # And it will be uploaded to the relevant artifactory URL and repo, under path pool/compute/localdisk-tools

      # In "new" mode, we consume some artifactory function that are under tool.sh
      source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

      echo "################ CI Upload packages new mode "################
      pushd ${CI_ARTIFACTS_TO_UPLOAD_DIR}
      echo "We are in directory ${CI_ARTIFACTS_TO_UPLOAD_DIR} which should hold the packages/artifacts to upload..."
      echo "This is the content of the directory : "
      ls -la
      popd
    fi
    # Get the types of packages we need to process
    package_types=$(echo ${packages} | yq -r 'keys[] | select(. != null)')
    # Get the types of packages
    for package_type in ${package_types}; do
      if [[ $(echo ${process_package_types} | grep ${package_type}) ]] || [[ $(echo ${process_package_types} | grep "all") ]]; then
        echo "Processing ${package_type} packages..."

        # Set variables to values based on the package type
        if [[ ${package_type} == "debian" ]]; then
          package_regex=${debian_regex}
          package_push_url=${debian_push_url}
        elif [[ ${package_type} == "rpm" ]]; then
          package_regex=${rpm_regex}
          package_push_url=${rpm_push_url}
        elif [[ ${package_type} == "golang" ]]; then
          package_regex=${golang_regex}
          package_push_url=${golang_push_url}
        else
          echo "Warning: Unhandled package type: ${package_type}"
        fi
        # Validate that the variables supposed to have been set above for the package type actually were
        # Can run into this case with an unhandled package type / typo in the yaml file.
        if [[ ! -n ${package_regex} || ! -n ${package_push_url} ]]; then
          echo "Error: required variable(s) were not set or configured correctly:"
          if [[ ! -n ${package_regex} ]]; then
            echo "Variable package_regex was of length zero"
          fi
          if [[ ! -n ${package_push_url} ]]; then
            echo "Variable package_push_url was of length zero"
          fi
          exit 1
        fi
        # This is set separately from the for statement so that an error with the yq command will relay the non-zero error code instead of causing this script to exit with a status code of 0
        meta_arches=$(yq -r ".packages.${package_type} | keys | .[]" ${path_to_build_meta_file})
        for meta_arch in ${meta_arches}
        do
          if [[ ${package_type} == "debian" ]]; then
            artifact_meta=";deb.distribution=bionic;deb.component=main;deb.architecture=${meta_arch}"
          elif [[ ${package_type} == "rpm" ]]; then
            artifact_meta=";rpm.metadata.arch=${meta_arch}"
          elif [[ ${package_type} == "golang" ]]; then
            artifact_meta=";golang.metadata.arch=${meta_arch}"
          fi

          # This check ensures that we only look for packages (that are of the same architecture as the env) defined in the build-meta.yaml file
          if [[ ${meta_arch} == "$(get_system_arch)" ]]; then
            echo "The current architecture (${meta_arch}) defined in the applicable section of the build-meta.yaml file matches the current system's architecture ($(get_system_arch))."
            echo "Proceeding to verify that the applicable packages are in the expected areas and uploading for ${meta_arch}"
            echo "Processing packages for ${meta_arch}"
            # Get list of packages under the arch, if "null" -> empty string
            meta_package_list=$(yq -r ".packages.${package_type}.${meta_arch} | select(. != null) | if type==\"string\" then . else .[] end" ${path_to_build_meta_file})
            if [[ ${meta_package_list} == "" ]]; then # If the architecture doesn't have any values specified in it
              echo "Info: No packages defined under ${meta_arch} for upload"
            else
              if [[ "${CI_UPLOAD_PACKAGES_MODE}" = "new" ]]; then
                echo "The following packages were found in the packages section of build-meta.yaml"
                echo "Will process them one after the other..."
                echo ${meta_package_list}
              fi
            fi
            for package in ${meta_package_list}
            do
              echo "Processing ${package}..."
              if [[ "${CI_UPLOAD_PACKAGES_MODE}" = "new" ]]; then
                file_name_to_search=$(echo ${package} | sed -e 's/^.*\///')
                pushd ${CI_ARTIFACTS_TO_UPLOAD_DIR}
                echo "Will find in directory ${PWD}, files that match regex .*${file_name_to_search}${package_regex}"
                result=$(find -regextype posix-extended -regex ".*${file_name_to_search}${package_regex}")
                if [[ ! -z ${result} ]]; then
                  FOUND_FILE_NAME=$(echo "$result" | sed 's|^./||')
                  echo "Found local file ${FOUND_FILE_NAME}, in directory ${PWD}"
                  PATH_IN_ARTIFACTORY=$(dirname ${package}) # We use dirname to keep all the path until the last /
                  PATH_AFTER_ARTIFACTORY_URL="${package_push_url}/${PATH_IN_ARTIFACTORY}/${FOUND_FILE_NAME}"
                  FULL_PATH_IN_ARTIFACTORY="${artifactory_base_url}/${PATH_AFTER_ARTIFACTORY_URL}"

                  # If needed check, and eventually fail if the file already exists
                  if [[ $CI_UPLOAD_PACKAGES_CHECK_AND_FAIL_IF_PACKAGE_EXISTS = true ]]; then
                    status_code=$(curl --fail --retry 5 -I -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${CC_ARTIF_ACCESS_TOKEN}" "${artifactory_base_url}/api/storage/${PATH_AFTER_ARTIFACTORY_URL}")
                    if [[ "${status_code}" -eq 200 ]]; then
                      echo "${PATH_AFTER_ARTIFACTORY_URL} already exists in ${artifactory_base_url}, will exit with error"
                      exit 1
                    fi
                  fi

                  # If needed, include the metadata
                  if [[ $CI_UPLOAD_PACKAGES_INCLUDE_METADATA = true ]]; then
                    FULL_PATH_IN_ARTIFACTORY="${FULL_PATH_IN_ARTIFACTORY}${artifact_meta}"
                  fi

                  # Dry run mode
                  if [[ $CI_UPLOAD_PACKAGES_DRY_RUN_MODE = true ]]; then
                    echo "DRY RUN MODE !!! - We would have uploaded file ${FOUND_FILE_NAME} to ${FULL_PATH_IN_ARTIFACTORY}"
                  else
                    upload_file_to_artifactory "${CC_ARTIF_ACCESS_TOKEN}" "${FULL_PATH_IN_ARTIFACTORY}" "${FOUND_FILE_NAME}" "10" "true"
                  fi
                else
                  echo "Could not find local file matching what is described in build-meta.yaml"
                  echo "Seems something went wrong in a previous step... Exiting with error"
                  exit 1
                fi
                popd
              else
              short_package_name=$(echo ${package} | sed -e 's/^.*\///')
              package_upload_dir=""
              echo "Searching for matching package..."

              # Attempt to find in Concourse first
              # First, search for the full entry, e.g. path/package-name
              # If the first search returned a zero length string, then just search for the package-name
              # and finally, if that also returned a zero length string, print an error message and exit
              echo "Looking under \".*${concourse_default_path}/${package}${package_regex}\", then \".*${concourse_default_path}/${short_package_name}${package_regex}\" if that fails"
              result=$(find -regextype posix-extended -regex ".*${concourse_default_path}/${package}${package_regex}")
              if [[ -z ${result} ]]; then
                echo "Warning: Did not match first regex for path and package, trying to find by package name only"
                result=$(find -regextype posix-extended -regex ".*${concourse_default_path}/${short_package_name}${package_regex}")
                if [[ -z ${result} ]]; then
                  echo "Error: Failed to find ${package} under Concourse path"
                  file_found=false
                else
                  echo "Found local file \"${result}\" by searching by filename only"
                  package_upload_dir=$(echo ${package} | grep -o '^.*\/')
                  file_found=true
                fi
              else
                file_found=true
                echo "Found local file \"${result}\" using path and filename."
              fi
              if [[ ${file_found} != true ]]; then
                echo "Looking under \".*${path_to_packages}/${package}${package_regex}\", then \".*${path_to_packages}/${short_package_name}${package_regex}\" if that fails"
                result=$(find -regextype posix-extended -regex ".*${path_to_packages}/${package}${package_regex}")
                if [[ -z ${result} ]]; then
                  echo "Warning: Did not match first regex for path and package, trying to find by package name only"
                  result=$(find -regextype posix-extended -regex ".*${path_to_packages}/${short_package_name}${package_regex}")
                  if [[ -z ${result} ]]; then
                    echo "Error: Failed to find ${package}"
                    file_found=false
                  else
                    echo "Found local file \"${result}\" by searching by filename only"
                    package_upload_dir=$(echo ${package} | grep -o '^.*\/')
                    file_found=true
                  fi
                else
                  file_found=true
                  echo "Found local file \"${result}\" using path and filename."
                fi
              fi
              if [[ ${file_found} == false ]]; then
                echo "Error: File was not found in any applicable locations"
                exit 1
              fi

              # Sed makes the output nicer, removes the "./" part
              path_to_package=$(echo "$result" | sed 's|^./||')
              # remove path to package, and just get the package name itself:
              package_name=$(echo ${path_to_package} | sed 's,.*/,,')

              set +e

              if [[ -z ${CC_ARTIF_ACCESS_TOKEN} ]]; then
                echo "Error: \${CC_ARTIF_ACCESS_TOKEN} is empty, cannot continue"
                exit 1
              fi
              if [[ -z ${artifactory_base_url} ]]; then
                echo "Error: \${artifactory_base_url} is empty, cannot continue"
                exit 1
              fi

              retries=${command_retries}
              status_code=""
              while [[ retries -gt 0 ]];
              do
                # -I Gets the headers only
                # -s is silent
                # -o sends the response to /dev/null
                # -w writes the http code to std out
                # -H is headers for authentication
                # --fail does not exit the script
                status_code=$(curl --fail --retry 5 -I -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${CC_ARTIF_ACCESS_TOKEN}" "${artifactory_base_url}/api/storage/${package_push_url}/${package_upload_dir}${package_name}")
                if [[ ${status_code} -eq 404 || ${status_code} -eq 200 ]]; then
                  break
                fi
                retries=$[retries-1]
              done
              set -e

              if [[ "${status_code}" -eq 200 ]]; then
                echo "WARNING: The package was found in ${package_push_url}/${package_upload_dir}${package_name}, skipping pushing over the already existing package!"
                exit 1
              elif [[ "${status_code}" -eq 404 ]]; then
                echo "The package was not found in artifactory already, continuing pushing to ${package_push_url}/${package_upload_dir}${package_name}"
                # the metadata is necessary as the debian packages are not automatically indexed in the repository, thus making it necessary to specify extra options so they are indexed.

                # -X changes request type, in this case to PUT
                # -I Gets the headers only
                # -s is silent
                # -o sends the response to /dev/null
                # -w the arg passed in writes the http code to std out
                # -T is to upload a file
                # -H is for the headers, used to authenticate by passing the bearer token
                # --retry is to retry defined number of times
                # --retry-delay is the exponential backoff algorithm for delays between re-tries

                curl --retry 3 --retry-delay 5 --fail -X PUT -I -s -o /dev/null -w "%{http_code}" -T "${path_to_package}" -H "Authorization: Bearer ${CC_ARTIF_ACCESS_TOKEN}" "${artifactory_base_url}/${package_push_url}/${package_upload_dir}${package_name}${artifact_meta}"

                # writes package artifacts to build/build-versions
                # general usage is for extracting build information to automate hostOS pr
                # requires CI_BUILD_ROOT to be present and pointing to container build root
                if [[ ! -z "${CI_BUILD_ROOT:-}" ]]; then
                  if [[ -d "${CI_BUILD_ROOT}"/build/build-versions ]]; then
                    echo ${package_name} >> "${CI_BUILD_ROOT}"/build/build-versions/"${short_package_name}.txt"
                  fi
                fi
              else
                echo "ERROR: Unexpected status code (${status_code}) encountered"
                exit 1
              fi
              fi
            done # closes for package in ${meta_package_list}
          else
            echo "The current architecture (${meta_arch}) defined in the applicable section of the build-meta.yaml file doesn't match the current system's architecture ($(get_system_arch))"
            echo "Skipping verification of applicable packages & uploads for ${meta_arch}"
          fi

        done # closes for meta_arch in ${meta_arches}
        echo ""
      else
        echo "Skipping processing this package; it was not specified in the variable \"process_package_types\""
      fi
    done # Closes for package_type in package_types
  fi
}

function process_images(){

images=$(yq -r '.images | select(. != null)' ${path_to_build_meta_file})
if [[ -n ${images} ]]; then

  echo "Processing images..."

  # If ARTIFACTORY_DOCKER_URL is not of zero length (e.g. is set to a value):
  if [[ ! -z ${ARTIFACTORY_DOCKER_URL+""} ]]; then
    # If DOCKER_REGISTRY_PUSH_URL was not set use the default ARTIFACTORY_DOCKER_URL
    DOCKER_REGISTRY_PUSH_URL="${DOCKER_REGISTRY_PUSH_URL:-${ARTIFACTORY_DOCKER_URL}}"
  fi

  docker_image_list=$(docker images --format "{{.Repository}}:{{.Tag}}")
  [[ -f .git/resource/head_sha ]] && git_hash=$(cat .git/resource/head_sha) || git_hash=$(git rev-parse HEAD)
  git_tag=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true
  echo "Info: build system architecture is $(get_system_arch)"

  for meta_arch in $(yq -r '.images | keys | .[]' ${path_to_build_meta_file})
  do
    # Always say the build-yaml specified architecture we're processing
    echo "Processing images for ${meta_arch}"

    # Ignore architectures that are not the same as the current one, unless multi_arch is specified, then verify that we're in s390x:
    if [[ ${meta_arch} == $(get_system_arch) ]] || [[ ${meta_arch} == "multi_arch" && $(get_system_arch) == "s390x" ]]; then
      # Get list of images under the arch, if "null" -> empty string
      meta_image_list=$(yq -r ".images.${meta_arch} | select(. != null) | if type==\"string\" then . else .[] end" ${path_to_build_meta_file})

      if [[ ${meta_image_list} == "" ]]; then # If the architecture doesn't have any values specified in it
        echo "Info: No images defined under ${meta_arch} for upload"
      fi

      # Workaround for build-meta.yaml files specifying "multi_arch" instead of "s390x"
      if [[ ${meta_arch} == "multi_arch" && $(get_system_arch) == "s390x" ]]; then
        meta_arch="s390x"
        echo "Processing multi_arch as s390x"
      fi
    # If the system we're using doesn't match one of the conditions
    # - architectures match 1:1,
    # - multi_arch is specified and the system is s390x
    # clear the meta_image_list; we aren't going to process that architecture
    else
      meta_image_list=""
    fi

    for image in ${meta_image_list}
    do
      # Image(s)
      echo "Processing ${image}..."
      short_image_name=$(echo ${image} | sed -e 's/^.*\///')
      echo "Searching list of built docker images for ${image}..."
      # search the image list for the full image name. If that was successful, set "result" to that output,
      # otherwise check for the short image name, and if that was successful, set "result" to that output.
      # Otherwise, print an error message, and exit
      # Make sure we are exact matching images returned from the docker image list.
      result=$(echo "${docker_image_list}" | grep -E "^${image}:" \
          || echo "${docker_image_list}" | grep -E "^${short_image_name}:") \
          || (echo "Failed to find ${image}! Exiting with error" && exit 1) # These parenthesis are required; otherwise it will always exit with an error.
      confirmed_image_name=$(echo "$result" | awk '{print $1}')
      echo "Confirmed that at least one image with a matching name was built"

      versions="${git_hash} ${git_tag}"
      for version in $versions; do
        image_path="${DOCKER_REGISTRY_PUSH_URL}/${image}:${version}-${meta_arch}"

        set +e
        inspect_result=$(docker manifest inspect ${image_path})
        status_code=$?
        set -e
        if [[ "${status_code}" -ne 0 ]]; then
          echo "Image tag was not found, continue pushing to ${DOCKER_REGISTRY_PUSH_URL}"
          echo "docker tag \"${confirmed_image_name}\" \"${image_path}\""
          docker tag "${confirmed_image_name}" "${image_path}"
          safe_retry_command docker push ${image_path}

          # Manifest(s)
          echo "Creating manifest for ${image}" # This is needed for the release job which utilizes the manifest to get images.
          manifest_name="${DOCKER_REGISTRY_PUSH_URL}/${image}:${version}"
          manifest_params="${manifest_name} ${image_path}"
          # Next command uses the "safe_retry_command" since it can fail due to network issues
          safe_retry_command docker manifest create ${manifest_params}
          docker manifest annotate ${manifest_params} --arch ${meta_arch}
          echo "manifest created and annotated successfully"
          safe_retry_command docker manifest push ${manifest_name}
          echo "manifest pushed successfully"
          safe_retry_command docker rmi ${image_path}
          echo "done"

        else
          echo "WARNING: ${image_path} already exists, skipping the push to ${DOCKER_REGISTRY_PUSH_URL}"
        fi
      done
    done
  done

else
  echo "No images specified for upload"
fi

}

# This function combines the processing of the entire build meta file into a single function
function process_build_meta(){

  # Assert that the build-meta file exists in the expected location
  if [[ -f ${path_to_build_meta_file} ]]; then
    echo "build-meta.yaml file was found"
  else
    echo "Failed to find build-meta.yaml file at ${path_to_build_meta_file}"
    exit 1
  fi

  # Process the build-meta.yaml file's contents and take actions based on what is defined in them
  if [[ ${upload_images} == "true" ]]; then
    process_images
  else
    echo "Variable determining whether to upload images was not true, skipping uploading of images"
  fi
  if [[ ${upload_packages} == "true" ]]; then
    process_packages
  else
    echo "Variable determining whether to upload packages was not true, skipping uploading of packages"
  fi
}

# Travis doesn't support newline characters in env variables, so I had to write this ridiculous function because
# GPG won't load the key if there isn't a newline after the Begin / before the End GPG key blocks.
# Note the extra newline after the Begin doesn't appear to be required to import the key, but not including it can cause an invalid armor header message to appear
# Written by taking the "meat" of the key and wrapping it in the key blocks -
# won't work with the key blocks already present in the var - this is intended as the newline would break the feature
# of travis to obfuscate the key in logging
function fix_travis_gpg_key(){
  signing_key=$(echo "-----BEGIN PGP PRIVATE KEY BLOCK-----
${signing_key}
-----END PGP PRIVATE KEY BLOCK-----")
}

# Function that loads the private GPG Key into GPG (or if $1 is set to test, creates a key to use)
# Defaults to stdin / loading the variable from GPG_PRIVATE_KEY variable.
# Use $1 to specify whether to run in test mode, or if the GPG Private Key is loaded via "stdin", or "file".
# use $2 to specify the key value or filename. Should not be required to specify
function load_key(){
  options=$-
  set +e
  check_dependencies "pinentry"
  # Load the key mode from $1 - if nothing specified, default to stdin
  key_mode=${1:-"stdin"}
  # Check if we're in test mode, if so, generate a private key and use that to sign.
  if [[ ${1:-""} == "test" ]]; then
    echo "Loading key..."
    echo "Test mode: creating new key and using"
    gpg_generate_key "${signing_key_uid}"
  # If we're not doing a test, we need the real signing key, so load the key from stdin (or file, if specified)
  else
    if [[ ${key_mode} == "stdin" ]]; then
      echo "Loading key from stdin..."
      # Try to load the key, outputting stderr to stdout so it can be captured
      import_key_command_output=$(echo "${2:-${signing_key}}" | gpg --import 2>&1)
      if [[ $? != 0 ]] ; then
        # If there was an error when trying to import the key, check the output for if it was already in the keyring
        echo "${import_key_command_output}" | grep -q "already in secret keyring"
        if [[ $? == 0 ]] ; then # If it was already in the keyring (previously imported) print out a message
          echo "Key has already been imported"
        else
          echo "${import_key_command_output}" | grep -q "no valid OpenPGP data found"
          if [[ $? == 0 ]] ; then
            # If the error wasn't that it was already in the keyring, try the travis workaround.
            echo "Attempting to automatically fix failed key import with Travis workaround..."
            fix_travis_gpg_key
            echo "${signing_key}" | gpg --import
            if [[ $? != 0 ]]; then
              echo "Error: Failed to load the signing key"
              exit 1
            else
              echo "Loaded fixed key successfully"
            fi
          else
            # Error that we don't have logic to automatically handle, just output the error to the log
            echo "Error: ${import_key_command_output}"
          fi
        fi
      fi
    elif [[ ${key_mode} == "file" ]]; then
      echo "Loading key from file..."
      gpg --import ${2:-${signing_key_uid}}
      if [[ $? != 0 ]]; then
        echo "Failed to import signing key by filename"
        exit 1
      fi
    else
      echo "Error: No option specified for key import type, or incompatible option"
      exit 1
    fi

    echo "Updating trustdb for key..."
    # List secret keys, grep for the key we want, get the line before the key name, which contains the fingerprint, filter out the other line via head
    fingerprint=$(gpg --list-secret-keys | grep "${signing_key_uid}" -B 1 | head -n 1)
    # Remove whitespace
    fingerprint=$(echo $fingerprint)
    #echo the key fingerprint with the trust level (format is "FINGERPRINT:TRUST_LEVEL:") into the gpg command to import ownertrust
    # note that the TRUST_LEVEL is as it appears when editing keys, but with the value incremented by one.
    echo "${fingerprint}:6:" | gpg --import-ownertrust
    echo "Updated trustdb for key"

  fi
  echo "Loaded Keys: "
  gpg --list-secret-keys --keyid-format LONG
  set -${options}
}

# Function to be used by repositories to setup GPG for signing.
# Intended to be simple evocation without parameters needed.
function setup_gpg_signing(){
  options=$-
  set +e
  echo "Setting up GPG signing..."
  if [[ ${is_gpg_signing_setup} != "true" ]]; then
    load_key
  else
    echo "GPG is already setup, skipping re-loading key. "
  fi
  # If we loaded the key without error, set is_gpg_signing_setup to true
  if [[ $? == 0 ]]; then
    is_gpg_signing_setup=true
    echo "Reloading GPG Process..."
    gpg-connect-agent reloadagent /bye
    echo "gpg_sign function ready to use"
  fi
  set -${options}
}

# Implemented based on the information found at https://access.redhat.com/articles/3359321
function setup_rpm_signing(){
  options=$-
  set +e
  if [[ ${is_gpg_signing_setup} != true ]]; then
    setup_gpg_signing
  fi
  check_dependencies "rpm rpmsign"
  # Export the public key so it can be imported into RPM database
  # -a option is for "armor" - (binary -> text conversion)
  gpg --output "${signing_key_uid}.pub" --export --yes -a "${signing_key_uid}"

  # Import public key to RPM
  echo "Importing public key to RPM"
  rpm --import "${signing_key_uid}.pub"
  # Confirm the public key that was imported was done so correctly by outputting the public keys
  echo "Listing public keys loaded in RPM: "
  rpm -q gpg-pubkey --qf '%{name}-%{version}-%{release} --> %{summary}\n'

  echo "Setting up .rpmmacros file"
  GNUPGHOME=$(eval echo "~/.gnupg") # This may be necessary in order for the rpm signing to use the correct dir
# Setup ~/.rpmmacros in order to utilize the key.
cat << EOF > ~/.rpmmacros
%_signature gpg
%_gpg_path ${GNUPGHOME}
%_gpg_name ${signing_key_uid}
%_gpgbin /usr/bin/gpg2
%__gpg_sign_cmd %{__gpg} gpg --force-v3-sigs --batch --verbose --no-armor --no-secmem-warning -u "%{_gpg_name}" -sbo %{__signature_filename} --digest-algo sha256 %{__plaintext_filename}
EOF
  is_rpm_signing_setup=true
  echo "rpm_sign function ready to use"
  set -${options}
}

# Uses GPG to sign a file, creating output file(s) in the form of "${input_file}.gpg", and verifying the signature on the output file(s)
# The command will output a space-separated list of the files that were signed
function gpg_sign(){
  options=$-
  set +e
  signed_files=""
  for file_name in $@
    do
      # GPG signs the file, creating a file named ${file_name}.gpg, which contains the file itself and is signed.
      # The --local-user specifies which key to use when signing. Fails for no matches.
      # The --batch and --yes prevent prompts for things such as overwriting a file
      gpg --local-user "${signing_key_uid}" --batch --yes --sign "${file_name}"
      # Verify the signing of the file
      gpg --local-user "${signing_key_uid}" --batch --yes --verify "${file_name}.gpg"
      status_code=$?
      if [[ ${status_code} != 0 ]]; then
        echo "Error: GPG Failed verifying that the file ${file_name} was either signed or correctly signed, status code: ${status_code}"
        exit ${status_code}
      fi
      signed_files="${signed_files} ${file_name}.gpg"
    done
  echo "${signed_files}"
  set -${options}
}

# Signs rpms with rpm-sign, accepts list of packages to sign
# Skips over signing packages without .rpm in the name
# e.g. rpm_sign "package1.rpm package2.rpm package3.rpm"
function rpm_sign(){
  options=$-
  set +e
  if [[ is_rpm_signing_setup != true ]]; then
    setup_rpm_signing
    if [[ $? != 0 ]]; then
      echo "Encountered error when attempting to automatically setup rpm signing"
      exit 1
    fi
  fi
  signed_files=""
  for package_name in $@
  do
    echo ${package_name} | grep ".rpm"
    status_code=$?
    if [[ ${status_code} != 0 ]]; then
      echo "package_name not an .rpm file, skipping"
    else
      echo "Signing package: ${package_name}"
      # note: Getting a message like "gpg: skipped "Key Name": No secret key" when signing using gpg itself functions correctly may be due to:
      # an incorrect .gnupg directory being set
      # a mismatch between what's in the macros file and the actual key name
      rpm --addsign ${package_name}
      status_code=$?
      if [[ ${status_code} != 0 ]]; then
        echo "Error: An error occurred when trying to sign ${package_name} with status code of ${status_code}"
      fi
      rpm --checksig ${package_name}
      status_code=$?
      if [[ ${status_code} != 0 ]]; then
          echo "Error: RPM Failed verifying that the file ${package_name} was either signed or correctly signed, status code: ${status_code}"
          exit ${status_code}
      fi
      signed_files="${signed_files} ${file_name}"
      rpm -q --qf '%{SIGPGP:pgpsig} %{SIGGPG:pgpsig}\n' -p ${package_name}
    fi
  done
  echo "${signed_files}"
  set -${options}
}

# This function takes in optional params username, password to generate a gpg key
# Here only for testing purposes
function gpg_generate_key(){
  options=$-
  set +e
  check_dependencies "pinentry"
  username=${1:-${signing_key_uid}}
  password=${2:-""}
  gpg --quick-generate-key --passphrase ${password} --batch --pinentry-mode loopback --yes "${username}"
  gpg --list-keys
  set -${options}
}

# Simple function that returns the name of the (first match) of a system's package management tooling
function get_system_package_manager(){
  options=$-
  set +e
  considered_package_managers="dnf yum apt"
  for package_manager_name in ${considered_package_managers}
    do
      which ${package_manager_name} >> /dev/null
      if [[ $? == 0 ]]; then
        echo "${package_manager_name}"
        break
      fi
    done
  set -${options}
}

# First param is the dependency/dependencies name (Needs to be in quotes for multiple dependencies, space-separated entries)
# Second param is an optional param that can be set to "safe" to try to automatically install missing dependencies
# rather than exiting on failing to find the dependency
function check_dependencies(){
  options=$-
  set +e
  check_dependency_mode=$(echo "${2:-${check_dependency_mode}}")
  failed_packages="" # Packages that aren't installed, failed to install if check_dependency_mode is "safe"
  for dependency_to_check in ${1};
  do
    which ${dependency_to_check} > /dev/null
    if [[ $? != 0 ]]; then
      echo "${dependency_to_check} not found/installed on system"
      if [[ ${check_dependency_mode} == "safe" ]]; then
        echo "Attempting to install ${dependency_to_check}..."
        sudo $(get_system_package_manager) install ${dependency_to_check} -y
        if [[ $? != 0 ]]; then
          echo "Failed to install ${dependency_to_check}"
          failed_packages="${failed_packages} ${dependency_to_check}"
        fi
      else
        failed_packages="${failed_packages} ${dependency_to_check}"
      fi
    else
      echo "${dependency_to_check} is installed on the system"
    fi
  done

  if [[ ${failed_packages} != "" ]]; then
    echo "Exiting due to unsatisfied dependency/dependencies:${failed_packages}"
    exit 1
  fi
  set -${options}
}

# Function that can be used to do a 'default' run of the shell
# not called by default to allow this file to have specific functions run from it if needed
function main(){
  process_build_meta
}

# Used to enable calling the file and specifying a function to use without sourcing the file
case "${1:-}" in
    "") ;;
    main) "$@";;
    safe_retry_command) "$@";;
    get_system_arch) "$@";;
    process_packages) "$@";;
    process_images) "$@";;
    process_build_meta) "$@";;
    setup_gpg_signing) "$@";;
    gpg_sign) "$@";;
    setup_rpm_signing) "$@";;
    rpm_sign) "$@";;
    *) echo "Received call to unknown function: $1. Skipping function execution";;
esac
