#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -o pipefail

# source required properties
source $PATH_TO_PIPELINE/environment/vars.sh
source $PATH_TO_PIPELINE/environment/secrets.sh

python3 -m pip install -r ${PATH_TO_WORKSPACE}/scripts/backup_sm/requirements.txt
# start copy
set +x
python3 ${PATH_TO_WORKSPACE}/scripts/backup_sm/backup_sm.py --cloud-apikey ${IBMCLOUD_KEY} --src-secrets-manager-endpoint-url ${SRC_SM_ENDPOINT} --dest-secrets-manager-endpoint-url ${DEST_SM_ENDPOINT} --auto-approve
