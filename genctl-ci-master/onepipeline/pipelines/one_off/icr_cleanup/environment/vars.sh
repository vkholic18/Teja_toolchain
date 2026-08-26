#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Secrets are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

export BUILD_META_PATH=$(get_env BUILD_META_PATH)
export TARGET_REPO=$(get_env TARGET_REPO)
export DRY_RUN=$(get_env DRY_RUN)
export COMMIT_MESSAGE= $(get_env commit_message)
export THRESHOLD_DAYS=$(get_env THRESHOLD_DAYS)
export NAMESPACE=$(get_env NAMESPACE)
export TEMPLATE=$(get_env TEMPLATE)
export ICR_REGISTRY=$(get_env ICR_REGISTRY)
