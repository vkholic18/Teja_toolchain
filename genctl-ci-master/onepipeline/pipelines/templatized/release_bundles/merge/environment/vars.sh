#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Used in prepare low_level_release_bundles ###
export PATH_TO_RELEASE_ENVIRONMENT=${WORKSPACE}/release-environment

export TWO_STEP_INVENTORY_UPDATE_MODE="true"
export TWO_STEP_INVENTORY_UPDATE_MODE_EXPLICIT_BRANCH_CREATION="true"

export ICR_BACKUP_RELEASE_BUNDLES_MODE="true"
export ICR_MIGRATION_MODE="true"

### Used in ICR backup ###
export PATH_TO_IMAGES_TO_COPY="" # We don't use the mode of list of images
export VERIFY_COPIED_IMAGES_CAN_BE_PULLED="true" # Used to make an additional verification that all the copied images can be pulled

# Used in inventory
export SKIP_ICR_IMAGES_FOR_INVENTORY_UPDATE="true"

### Mend SAST Information ###
export MEND_PRODUCT_NAME=$(yq -r '.mend_sast_info | select(. != null) | ."mend-product-name"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export MEND_USER_EMAIL=$(yq -r '.mend_sast_info | select(. != null) | ."mend-user-email"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export MEND_SECRET_GROUP=$(yq -r '.mend_sast_info | select(. != null) | ."mend-secret-group"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
