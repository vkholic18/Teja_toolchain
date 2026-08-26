#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2025
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##


# This file will be used for general overhead functions.


function check_last_cmd_error() {
    # Arguments expected:
    # 1 - message sent to standard out when failure encountered

    rc=$?
    if [ -z "$1" ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 1 argument but got $#. Please pass in the correct arguments."
        exit 1
    fi
    if [ $rc -ne 0 ]; then
        echo "ERROR: $1 rc=$rc"
        exit 1
    fi
}


function exit_if_var_not_set() {
    # Check whether an environment variable is set

    # Arguments expected:
    # 1 - Name of environment variable to check (note: not the variable itself)

    # The ${!1:-} checks the actual variable, compared to ${1} which is the variable name.
    # So for: `exit_if_var_not_set potato_salad`, when `potato_salad` wasn't set would result in echoing out "potato_salad not set, can not proceed!"
    if [ -z "${!1:-}" ]; then
        echo "${1:-"No variable name was specified /"} not set, can not proceed!"
        exit 1
    fi
}

function checkout_git_hash() {
    # Checkout git hash - this ensures builds are checked out to git hash triggerred by pipeline job
    # Arguments expected:
    # 1 - git hash that triggerred concourse

   # Make sure required arguments were passed in
   if [ "$#" -ne 1 ]; then
      echo "ERROR: ${FUNCNAME[0]} requires 1 argument but got $#.  Please pass in the correct arguments."
      exit 1
   else
      local git_hash=$1
   fi

   # Run checkout of git hash passed in
   echo "Checkout ${git_hash} triggerred by pipeline..."
   git checkout $git_hash
   check_last_cmd_error "git checkout failed! $git_hash!"
}

# Fetch (for PRs) and checkout a specific git hash
function fetch_and_checkout() {
    exit_if_var_not_set "CC_GIT_SHA"
    # If this is for a PR, we need to fetch it before we can checkout
    if [ -n "$CC_PR_ID" ]; then
        echo "Fetch PR ${CC_PR_ID}..."
        git fetch origin +refs/pull/${CC_PR_ID}/merge
    fi
    checkout_git_hash $CC_GIT_SHA
}

# Ensure submodules are updated with concourse hash
function initialize_submodules(){
   echo "Ensure submodules are synced and updated..."
   git submodule sync --recursive

   check_last_cmd_error "git submodule sync command failed!"
   git submodule update --init --recursive
   check_last_cmd_error "git submodule update command failed!"
}

function check_yq_installed(){
    # Check whether yq is already installed
    orig_opts=$-
    set +e  # Don't exit on error; we're checking whether yq is installed
    which yq
    export yq_installed_rc=$?
    if [[ $orig_opts =~ .*e.* ]]; then
        set -e # re-enable exiting on error
    fi
}

function install_yq(){

    check_yq_installed

    if [[ ${yq_installed_rc} == 0 ]]; then
        echo "yq is already installed"
        if [[ "$(yq --version)" =~ .*mikefarah.* ]]; then
            echo "Removing mikefarah/yq"
            if [[ ! "$(which yq)" =~ .*snap.* ]]; then
                echo "Unable to remove mikefarah/yq not installed by snap"
                exit 1
            fi
            sudo snap remove yq
            check_yq_installed
        fi
    fi

    if [[ ${yq_installed_rc} == 0 ]]; then
        echo "yq is already installed"
    elif [[ ${yq_installed_rc} == 1 ]]; then
        echo "Installing yq python dependencies"
        sudo apt-get update
        sudo apt-get install python3-pip python3-setuptools python3-wheel
        echo "Pip installing yq..."
        python3 -m pip install "yq<4.0.0"
    else
        # We shouldn't run into this scenario, but just in case...
        echo "Error: Unexpected error code ${yq_installed_rc} when checking yq installation"
        exit 1
    fi

    # is this still needed?
    if which pyenv; then
        export PATH="$PATH:$(pyenv prefix)/bin"
    fi
}

function validate_metadata_file(){
    # Checks that the metadata file conforms to a set of requirements (The file exists, an upload is defined for one or more arch)
    # Requires that yq is installed
    # Arguments expected:
    # 1: The path to the directory with the build metadata file in yaml format. May be absolute or relative.

    # Set var value to $1, or if unset, set to "hack/ci"
    path_to_file_dir=${1:-"hack/ci"}

    build_meta_file="build-meta.yaml"

    # Verify that the file defining build metadata exists
    if [[ -f "${path_to_file_dir}/${build_meta_file}" ]]; then
        echo "${build_meta_file} file found in repository!"
        # Verify that there is at least one image to upload for at least one architecture/group (non-zero)
        if [[ $(yq -r '{images}[]' ${path_to_file_dir}/${build_meta_file} -y -w 512 | grep -v ": null$") ]]; then
            echo "Success; An image was defined for one or more architecture(s)";
        else
            echo "Error encountered; The \"${build_meta_file}\" file did not contain any values for any architecture under images. "
            exit 1
        fi
    else
        echo "Error: Did not find a ${build_meta_file} file under the repository's ${path_to_file_dir} directory"
        exit 1
    fi
}

function update_version_meta(){
    # Runs a python script which updates version.json and the deployment labels in the deployment file(s) with git data
    # Args:
    #    1: Path to the genctl-cicd/common repository on the filesystem
    if [[ -z $1 ]]; then
        path_cicd_common_repo=${PATH_TO_GENCTL_COMMON_REPO}
    else
        path_cicd_common_repo=$1
    fi

    export REPO_PATH=./
    export VERSION_JSON_PATH=version.json
    export DEPLOYMENT_CONFIG_PATH=hack/deploy

    echo "Updating version.json and deployment labels with git metadata"
    python3 -m pip install --upgrade pip
    python3 -m pip install -r ${path_cicd_common_repo}/python/version-meta/requirements.txt
    python3 ${path_cicd_common_repo}/python/version-meta/version-meta.py
}