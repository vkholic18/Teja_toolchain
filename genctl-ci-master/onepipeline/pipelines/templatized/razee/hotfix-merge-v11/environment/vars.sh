#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Empty export of gh-release (Required in some tasks)
export PATH_TO_GH_RELEASE=""

### Used in ICCR ###
export ONE_PIPELINE_SAVE_ARTIFACTS_FOR_ICCR="true"
export OPERATION="PUSH"

### USED IN HOTFIX PIPELINES ###
export RAZEE_HOTFIX="true"

### Used in upload to COS ###
export COS_UPLOAD_CONTENT_ROOT="hack/deploy/razee/"
export COS_UPLOAD_FILES_FILTER=""

### Used in LaunchDarkly ###
# TODO: Decide if this is the approach we want (In that case make relevant changes in Concourse pipelines for them to be like this or add the empty defaults in the task)
export LAUNCH_DARKLY_USE_IN_DEFAULT_RULE="false"
export LAUNCH_DARKLY_CREATE_VARIATION_ONLY="false"

### Used in signing ###
export CANDIDATE_FILES_SKIP_UPLOAD="false" # Since this is a razee template, we DO want to upload the candidate files, therefore skip=false

### Used in build ###
export SKIP_UNIT_TESTS="true"

### Mend SAST Information ###
export MEND_PRODUCT_NAME=$(yq -r '.mend_sast_info | select(. != null) | ."mend-product-name"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export MEND_USER_EMAIL=$(yq -r '.mend_sast_info | select(. != null) | ."mend-user-email"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export MEND_SECRET_GROUP=$(yq -r '.mend_sast_info | select(. != null) | ."mend-secret-group"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)

export PROCESS_BUILD_META_UPLOAD_PACKAGES_INCLUDE_METADATA="true"

# Used in inventory
export SKIP_ICR_IMAGES_FOR_INVENTORY_UPDATE="true"

export ICR_MIGRATION_MODE="true"

export SAVE_ARTIFACTS_FAIL_IF_NO_MANIFEST="true" # For razee we should always have manifest for images
