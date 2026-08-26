#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2025
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/common/common_funcs.sh

# # Check if genctl-ci was cloned, if so try to load the process_build_meta.sh functions.
# if [[ -e ${PATH_TO_GENCTL_CI}/scripts/process_build_meta.sh ]]; then
#   echo "Checking yq installation..."
#   install_yq
#   echo "Loading process_build_meta.sh functions..."
#   source ${PATH_TO_GENCTL_CI}/scripts/process_build_meta.sh
#   echo "Finished loading process_build_meta.sh functions"
# else
#   # Repository's build process probably isn't cloning genctl-ci, and probably only cloning common.
#   echo "Unable to find process_build_meta.sh file, skipping loading process_build_meta.sh functions"
# fi

# Setup
ENV_BUILD_ROOT=${PWD}
OS_RELEASE=$(awk -F= '/^NAME/{print $2}' /etc/os-release)

# Differentiate between ubuntu and redhat trust set
if [[ $OS_RELEASE =~ "Ubuntu" ]]; then
  CERT_PATH='/usr/local/share/ca-certificates'
  ENV_PKG_ARCH=`dpkg --print-architecture`
else
  CERT_PATH='/etc/pki/ca-trust/source/anchors/'
  [[ $(uname -m) =~ "x86_64" ]] && ENV_PKG_ARCH="amd64" || ENV_PKG_ARCH="s390x"
fi

# Setup multiple ways to identify architecture used by different software
ENV_OS_ARCH=`uname -m`
[[ $(uname -m) =~ "x86_64" ]] && ENV_CR="docker" || ENV_CR="podman"
if [[ "$ENV_CR" == "podman" ]]; then
  if [ `which podman` ]; then
      ENV_DOCKER_ARCH=`podman version | awk -F'[:/ ]+' '/^OS\/Arch:/ {print $4; exit}'`
  fi
fi
if [[ "$ENV_CR" == "docker" ]]; then
  if [ `which docker` ]; then
      ENV_DOCKER_ARCH=`docker version -f '{{.Client.Arch}}'`
  fi
fi
if [ `which go` ]; then
    ENV_GO_ARCH=`go env GOHOSTARCH`
fi
echo "ENV_CR: ${ENV_CR} and ENV_DOCKER_ARCH: ${ENV_DOCKER_ARCH}"
# source the other utilities for easier access
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/common/artifact_utils.sh
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/common/log_utils.sh
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/common/docker_utils.sh
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/common/install_utils.sh
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/common/meta_utils.sh
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/common/parameter_utils.sh

# login into docker if the creds were provided
function login_docker() {
  if [[ -z "${DOCKER_TOKEN:-}" ]] || [[ -z "${DOCKER_USERNAME:-}" ]]; then
    echo "Docker credentials have not been set."
  else
      # docker is guaranteed installed. earlier we always for an artifactory login
      echo "${DOCKER_TOKEN}" > .dtoken
      cat .dtoken | docker login -u "$DOCKER_USERNAME" --password-stdin
  fi
}

login_docker

# Copy ibm_certs and install them
mkdir -p ${CERT_PATH}
sudo cp -f ${PATH_TO_GENCTL_CI}/onepipeline/scripts/common/ibm_certs/* ${CERT_PATH}
[[ $OS_RELEASE =~ "Ubuntu" ]] && sudo /usr/sbin/update-ca-certificates || sudo /usr/bin/update-ca-trust

# if we are running in a docker - we are running in a ci docker so skip this
# if [[ ! -f /bin/entrypoint.sh ]]; then
#     # restart the daemon after making importing new certs. on some versions of docker this is required
#     # in order for the daemon to recognize new os certs
#     echo "reloading docker..."
#     sudo systemctl daemon-reload
#     sudo systemctl restart docker
# fi

# add specific TD hosts to resolve locally instead of relying on external dns
echo "Add host entries to hosts table..."
set -x

SAVED_OPTS=$(set +o)
set +e

echo "testing for anchore connectivity..."
curl --connect-timeout 5 -I https://anchore.genctlci.com

if [[ $? -ne 0 ]]; then
    echo '9.114.87.105 anchore.genctlci.com' | sudo tee -a /etc/hosts
fi

eval "${SAVED_OPTS}"


set +x