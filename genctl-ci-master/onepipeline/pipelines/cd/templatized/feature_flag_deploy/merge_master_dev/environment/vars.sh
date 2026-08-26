#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

export COS_UPLOAD_CONTENT_ROOT="scripts/configure_featureflags/"
export COS_UPLOAD_FILES_FILTER="^featureflags-config-(rias|riaasiam|riaasstorage|ops|rias-etcd|genctl)(-ns)?\.yaml$"
export PATH_TO_GENCTL_CD="${WORKSPACE}/genctl-cd"
export SLACK_DIR="${WORKSPACE}/slack_dir"
export TICKET_DIR="${WORKSPACE}/ticket"
export SLACK_GROUP="<!subteam^S8AP6G4SY|genesisiam>"
export PATH_TO_APISPEC_FEATURES_YAML="/spec/features.yaml"
export PATH_TO_API_SPEC_REPO="riaas/api-spec"
export FEATURES_API_DATA_FILTER="^features-api-config-rias\.yaml$"
