#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2025
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##


function install_deb() {
    # Installs a deb package

    # Arguments expected:
    # 1 - full path of deb to install

    sudo dpkg -i ${1}
    check_last_cmd_error "Failed to install $1"

    sudo apt-get install -f
    check_last_cmd_error "Missing dependencies for installed packages"
    
    echo "Successfully installed $1"
}

function install_deb_on_container() {
    # Installs a deb package

    # Arguments expected:
    # 1 - container image name
    # 2 - full path of deb to install

    local container_name=${1}
    local deb_full_path=${2}

    # Make sure required arguments were passed in
    if [ "$#" -ne 2 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires 2 arguments but got $#. Please pass in the correct arguments."
        exit 1
    fi

    docker_exec $container_name "source .envrc; sudo dpkg -i ${deb_full_path}"
    check_last_cmd_error "Failed to install $deb_full_path"

    docker_exec $container_name "source .envrc; sudo apt-get install -f"
    check_last_cmd_error "Missing dependencies for installed packages"
    
    echo "Successfully installed $deb_full_path"
}