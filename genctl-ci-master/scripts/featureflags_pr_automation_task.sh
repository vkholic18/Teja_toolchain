#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -eux

source ${PATH_TO_GENCTL_CI}/scripts/retry.sh
retry python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/configure_featureflags/requirements.txt
python3 ${PATH_TO_GENCTL_CI}/scripts/configure_featureflags/automate_api_spec_update.py
