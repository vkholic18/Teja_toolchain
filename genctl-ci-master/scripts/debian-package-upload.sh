#!/bin/bash

## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2021
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================

set -eu
# Script Description:
#  This script is for uploading the built debian packages
#  The produced package(s) name(s) must match the values in the build-meta.yaml file

# Script Requirements
# - hack/ci/build-meta.yaml file must exist in the repository
# - This script is called from the root of the repository
# - the login to the docker repository/respositories has already been done
# - The base image this script runs in includes docker

debian_push_url=$1
command_retries=5 # The maximum number of retries to attempt before exiting with a failure

# This function takes the arguments in and runs them as the command.
# It additionally prints out the command that will be run (one time, not for every try)
# It disables exiting on error during this function, and re-enables it before exiting this function (if it was enabled prior to entering the function)
# Includes logic built-in to redact secrets, but need to be defined in the "secret_vars" variable in the code.
function safeRetryCommand(){
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

    retries=${command_retries}
    echo "${displayed_command}" # print out the command that will be run, without secrets displayed
    while [[ ${retries} -gt 0 ]];
    do
        retries=$[retries-1]
        $* && break # $* runs the command, if successful, exits the while loop.
        returnCode=$? # get return code of the command to use it if we need to exit with a failure
        echo "Warning: Failed to execute command successfully, retries remaining: ${retries}"
        if [[ ${retries} == 0 ]]; then
            echo "Error: All retries expended due to failures, exiting with error"
            set -${options} # In case this function is used and the error is wrapped, we want to ensure we restore the original options
            exit ${returnCode}
        fi
    done
    set -${options}
}

# Get some information about the machine we're running on
build_sys_arch=`uname -p`

if [[ ${build_sys_arch} == "x86_64" ]]; then
echo "Info: build system architecture is amd64"
else
echo "Info: build system architecture is ${build_sys_arch}"
fi

# This is set separately from the for statement so that an error with the yq command will relay the non-zero error code instead of causing this script to exit with a status code of 0
meta_arches=$(yq -r '.packages.debian | keys | .[]' hack/ci/build-meta.yaml)
for meta_arch in ${meta_arches}
do
  echo "Processing packages for ${meta_arch}"
  # Get list of packages under the arch, if "null" -> empty string
  meta_package_list=$(yq -r ".packages.debian.${meta_arch} | select(. != null) | if type==\"string\" then . else .[] end" hack/ci/build-meta.yaml)
  if [[ ${meta_package_list} == "" ]]; then # If the architecture doesn't have any values specified in it
    echo "Info: No packages defined under ${meta_arch} for upload"
  fi
  for package in ${meta_package_list}
  do
    echo "Processing ${package}..."
    short_package_name=$(echo ${package} | sed -e 's/^.*\///')
    package_upload_dir=""
    echo "Searching for matching package..."

    # First, search for the full entry, e.g. path/package-name
    # If the first search returned a zero length string, then just search for the package-name
    # and finally, if that also returned a zero length strinig, print an error message and exit
    result=$(find -regextype posix-extended -regex "./${package}_.*_.*\.deb")
    if [[ -z ${result} ]]; then
      echo "Warning: Did not match first regex for path and package, trying to find by package name only"
      result=$(find -regextype posix-extended -regex "./${short_package_name}_.*_.*\.deb")
      if [[ -z ${result} ]]; then
        echo "Error: Failed to find ${package}"
        exit 1
      else
        echo "Found local file \"${result}\" by searching by filename only"
        package_upload_dir=$(echo ${package} | grep -o '^.*\/')
      fi
    else
      echo "Found local file \"${result}\" using path and filename."
    fi

    # Sed makes the output nicer, removes the "./" part
    confirmed_package_name=$(echo "$result" | sed 's|^./||')

    set +e
    iter=3
    status_code=""
    while [[ iter -gt 0 ]];
    do
      # -I Gets the headers only
      # -o sends the response to /dev/null
      # -w writes the http code to std out
      # -H is headers for authentication
      status_code=$(curl --retry 5 -I -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${CC_ARTIF_ACCESS_TOKEN}" "${ARTIFACTORY_BASE_URL}/api/storage/${debian_push_url}/${package_upload_dir}${confirmed_package_name}")
      if [[ ${status_code} -eq 404 || ${status_code} -eq 200 ]]; then
        break
      fi
      iter=$[iter-1]
    done
    set -e

    if [[ "${status_code}" -eq 200 ]]; then
      echo "WARNING: The package was found in ${debian_push_url}, skipping pushing over the already existing package!"
      exit 1
    elif [[ "${status_code}" -eq 404 ]]; then
      echo "The package was not found in artifactory already, continuing pushing to ${debian_push_url}"
      # the metadata is necessary as the debian packages are not automatically indexed in the repository, thus making it necessary to specify extra options so they are indexed.
      artifact_meta=';deb.distribution=bionic;deb.component=main;deb.architecture=amd64;deb.architecture=s390x' #TODO Update this code to be more dynamic and/or ensure values are correct

      # -X changes request type, in this case to PUT
      # -T is to upload a file
      # -H is for the headers, used to authenticate by passing the API key in
      safeRetryCommand curl --retry 5 -X PUT -T "${confirmed_package_name}" -H "Authorization: Bearer ${CC_ARTIF_ACCESS_TOKEN}" "${ARTIFACTORY_BASE_URL}/${debian_push_url}/${package_upload_dir}${confirmed_package_name}${artifact_meta}"

      # writes debian artifacts to build/build-versions
      # general usage is for extracting build information to automate hostOS pr
      # requires CI_BUILD_ROOT to be present and pointing to container build root
      if [[ ! -z "${CI_BUILD_ROOT:-}" ]]; then
        if [[ -d "${CI_BUILD_ROOT}"/build/build-versions ]]; then
          echo ${confirmed_package_name} >> "${CI_BUILD_ROOT}"/build/build-versions/"${short_package_name}.txt"
        fi
      fi
    else
      echo "ERROR: Unexpected status code (${status_code}) encountered"
      exit 1
    fi
  done
done
