#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2021
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, WS_PATH, MZONE_NAME, BASTION_PRIVATE_KEY, BASTION_PRIVATE_KEY_ECDSA, BASTION_PRIVATE_KEY_RSA, BASTION_USERNAME, DAL_VAULT_KEY,
# GIT_PRIVATE_KEY, VAULT_GIT_CONFIG_USER_EMAIL, VAULT_GIT_CONFIG_USERNAME

# =============================================================================================


set -eux

############################################## Encapsulation of check-secrets.yaml ###############################################


: "${VAULT_GIT_CONFIG_USER_EMAIL:=}"
: "${VAULT_GIT_CONFIG_USERNAME:=}"
: "${WS_PATH:="workspace-repo"}"
: "${MZONE_NAME:=}"


# Get an mzone name from which we seek out the ssh details for a deploy server.
# If there isn't an mzone defined in the pipeline.yaml (or we can't get to pipeline.yaml)
# we fall back to mzone720a and therefore its deployer.

if [[ -f ${WS_PATH}/hack/ci/pipeline.yaml ]]; then
   MZONE_NAME=$(yq -r '.deployment.mzone_name | select(. != null)' ${WS_PATH}/hack/ci/pipeline.yaml)
fi

if [[ -z "$MZONE_NAME" ]]; then
   MZONE_NAME="720a"
fi

echo MZONE_NAME=${MZONE_NAME}

  # Second digit of mzone name tells us where the mzone is and thus what jumphost to use
REGIONDIGIT=${MZONE_NAME#*[[:digit:]]}
REGIONDIGIT=${REGIONDIGIT:0:1}

declare -ar VALID_REGIONS=( 1 2 3 4 )
if [[ ! "${VALID_REGIONS[@]}" =~ "${REGIONDIGIT}" ]]; then
  echo "Unsupported mzone: ${MZONE_NAME} (region ${REGIONDIGIT})"
  exit 1
fi


set +x  # so we do not log the vault key
export VAULT_KEY="${DAL_VAULT_KEY}"
set -x
export VAULT_CACERT="${PATH_TO_GENCTL_CI}/certificates/vault-dal-intermediary-ca.pem"


# because we're a script running in a yaml, our location will not be genctl/tasks/<script_yaml>
# and retrieving a relative path on a known location is not possible, we will derive our path based on
# our input of genctl-ci-repo

source ${PATH_TO_GENCTL_CI}/scripts/ssh_utils.sh
set +x
declare -r bastion_priv_key="/tmp/priv_key"
declare -r bastion_priv_key_ecdsa="/tmp/priv_key_ecdsa"
declare -r bastion_priv_key_rsa="/tmp/priv_key_rsa"
echo "${BASTION_PRIVATE_KEY}" > ${bastion_priv_key}
echo "${BASTION_PRIVATE_KEY_ECDSA}" > ${bastion_priv_key_ecdsa}
echo "${BASTION_PRIVATE_KEY_RSA}" > ${bastion_priv_key_rsa}
chmod 600 ${bastion_priv_key} ${bastion_priv_key_ecdsa} ${bastion_priv_key_rsa}
set -x
get_deployer_conn_path ssh_bastion ssh_deployer ${BASTION_USERNAME} ${bastion_priv_key} ${bastion_priv_key_ecdsa} ${bastion_priv_key_rsa} ${REGIONDIGIT}



# ensure failure on non-zero is not masked
# courtesy of Tal why we are forcing set -e
# https://unix.stackexchange.com/questions/383541/how-to-save-restore-all-shell-options-including-errexit
set -e

rm ${bastion_priv_key}
rm ${bastion_priv_key_ecdsa}
rm ${bastion_priv_key_rsa}
export BASTION=${ssh_bastion}
export DEPLOY_SERVER=${ssh_deployer}


# check and dont go any further if we could not locate a working pair
if [[ -z ${BASTION} || -z ${DEPLOY_SERVER} ]]; then
  echo "unable to locate a working bastion/deployer"
  exit 1
fi

export DEPLOY_SERVER_TARGET="${BASTION_USERNAME}@${DEPLOY_SERVER}"
export SSH_CONFIG_PARAMS="-o ServerAliveInterval=15"
if [[ -n "$BASTION" ]]; then
  export SSH_CONFIG_PARAMS+=" -J ${BASTION_USERNAME}@${BASTION}"
fi
echo DEPLOY_SERVER_TARGET="${DEPLOY_SERVER_TARGET}"
echo SSH_CONFIG_PARAMS="${SSH_CONFIG_PARAMS}"

MZONE_INV_FILE=${PATH_INVENTORY_REPO}/region/mzone${MZONE_NAME}.yml
echo mzone configuration file MZONE_INV_FILE=${MZONE_INV_FILE}

UNDERCLOUD=`yq -r ".undercloud" ${MZONE_INV_FILE}`
UNDERCLOUD_FILE=${PATH_INVENTORY_REPO}/region/undercloud/${UNDERCLOUD}.yml
export VAULT_IP=`yq -r ".services.vault.management_ip" ${UNDERCLOUD_FILE}`
echo VAULT_IP=${VAULT_IP}
export VAULT_PREFIX=`yq -r ".services.vault.prefix" ${UNDERCLOUD_FILE}`
echo VAULT_PREFIX=${VAULT_PREFIX}

eval "$(ssh-agent -s)"
ssh-add - <<< "${BASTION_PRIVATE_KEY}"
ssh-add - <<< "${BASTION_PRIVATE_KEY_ECDSA}"
ssh-add - <<< "${BASTION_PRIVATE_KEY_RSA}"

export WS=${WS_PATH}



################################################################################################################################
set -eux

SCRATCH=$(mktemp)
bail() {
        rm -f $SCRATCH
}

trap bail 0 1 2 3 6 9 15

echo "check_secrets.sh: ${PWD}"

unready="no"

set +x  # so we do not log the vault key
if [[ -z "${VAULT_KEY}" ]]; then
        echo "VAULT_KEY not set"
        unready="yes"
fi
set -x

if [[ -z "${VAULT_IP}" ]]; then
        echo "VAULT_IP not set"
        unready="yes"
fi

if [[ -z "${VAULT_PREFIX}" ]]; then
        echo "VAULT_PREFIX not set"
        unready="yes"
fi

if [[ ! -f "${VAULT_CACERT}" ]]; then
        echo "Vault certificate not found: ${VAULT_CACERT}"
        unready="yes"
fi

if [[ "$unready" == "yes" ]]; then
        exit 1
fi

set +x  # so we do not log the vault cert
export VAULT_CERT_PATH_RIAS=${VAULT_CACERT}
export VAULT_CERT_PATH_GENCTL=${VAULT_CACERT}
set -x

export VAULT_NAMESPACE="nextgen"
export INVAULT_NS_RIAS=${VAULT_NAMESPACE}
export INVAULT_NS_GENCTL=${VAULT_NAMESPACE}

export INVAULT_PATH_RIAS=${VAULT_PREFIX}
export INVAULT_PATH_GENCTL=${VAULT_PREFIX}

# Install pre-reqs
echo "check_secrets.sh: Installing requirements from requirements.txt"
python3 -m pip install -r genctl-ci-repo/scripts/check_secrets/requirements.txt

# Generate a time-limited vault token
rm -f .token
ssh -f -o ExitOnForwardFailure=yes ${SSH_CONFIG_PARAMS} -L 8200:${VAULT_IP}:8200 ${DEPLOY_SERVER_TARGET} sleep 10
set +x  # so we do not log the vault key
echo "${VAULT_KEY}" | curl --retry 5 -H "X-Vault-Namespace: ${VAULT_NAMESPACE}" --cacert ${VAULT_CACERT} --data @- --url https://127.0.0.1:8200/v1/auth/approle/login -s | jq -r .auth.client_token > .token
export VAULT_TOKEN_RIAS=$(cat .token)
export VAULT_TOKEN_GENCTL=${VAULT_TOKEN_RIAS}
set -x
if [ -s .token ]; then
    echo "Got vault token"
else
    echo "Unable to get vault token"
    exit 1
fi

echo "Sleeping to allow tunnel to collapse"
sleep 20

export VAULT_ADDR_RIAS="https://127.0.0.1:8200"
export VAULT_ADDR_GENCTL="https://127.0.0.1:8200"
ssh -f -o ExitOnForwardFailure=yes ${SSH_CONFIG_PARAMS} -L 8200:${VAULT_IP}:8200 ${DEPLOY_SERVER_TARGET} sleep 300

find ${WS}/hack/deploy/razee -type f -exec egrep '{{.*secretAsFile' /dev/null {} \; | sed -e 's,:.*,,' | sort -u > ${SCRATCH}

echo "Found secret references:"
cat ${SCRATCH}

echo "Searching vault:"
cat ${SCRATCH} | python3 genctl-ci-repo/scripts/check_secrets/check_secrets.py
