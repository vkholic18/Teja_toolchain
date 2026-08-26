#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Used in check pr title and commits ###
export WORKSPACE_ROOT="NO_NEED_LOCAL_PARSING"

### Used in build (Upload related) ###
export UPLOAD_PACKAGES_MODE="new" # In OnePipeline we use a new mode of processing packages

export ICR_MIGRATION_MODE="true"

export PROCESS_BUILD_META_UPLOAD_PACKAGES_INCLUDE_METADATA="true"

### Mend SAST Information ###
export MEND_PRODUCT_NAME=$(yq -r '.mend_sast_info | select(. != null) | ."mend-product-name"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export MEND_USER_EMAIL=$(yq -r '.mend_sast_info | select(. != null) | ."mend-user-email"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export MEND_SECRET_GROUP=$(yq -r '.mend_sast_info | select(. != null) | ."mend-secret-group"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)

### In order to optionally run static scan in PR ###
export RUN_STATIC_SCAN_IN_PR=$(yq -r '.run_static_scan_in_pr | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
