#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -eux

if [[ "$VALIDATE_FF_CONFIG" != "true" ]]; then
  echo "Validate featureflags config not enabled"
  exit 0
fi

source ${PATH_TO_GENCTL_CI}/scripts/retry.sh
retry python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/configure_featureflags/requirements.txt
python3 ${PATH_TO_GENCTL_CI}/scripts/configure_featureflags/validate_data.py --env-yaml-path ${PATH_TO_WORKSPACE_PR}/environment.yaml --service-flags-path ${PATH_TO_WORKSPACE_PR}/service-flags/