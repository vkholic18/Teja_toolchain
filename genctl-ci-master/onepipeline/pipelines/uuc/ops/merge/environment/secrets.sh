#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

export IBM_CLOUD_COS_API_KEY=$(get_env "cos-api-key")

export GHE_ACCESS_TOKEN=$(get_secret "ghe-access-token")

export ENABLE_TRIGGER_CREATION="$(get_env "ENABLE_TRIGGER_CREATION" "false")"

export INCLUDE_DEVELOPMENT="$(get_env "INCLUDE_DEVELOPMENT" "true")"
