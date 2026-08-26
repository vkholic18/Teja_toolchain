#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Used in build (Upload related) ###
export UPLOAD_PACKAGES_MODE="new" # In OnePipeline we use a new mode of processing packages
export UPLOAD="false" # In sdn-components template we don't deal with Docker images

export SKIP_UPLOAD_PACKAGES="true" # This is because components are pushed in the build stage
export PACKAGES_PATH_TO_USE_IN_ARTIFACT_FIELD_IN_JSON="vetted" # This is because SDN components have they own release flow and therefore, in the inventory creation we add entry with the vetted path

# Used in inventory
export SKIP_ICR_IMAGES_FOR_INVENTORY_UPDATE="true"

### Mend SAST Information ###
export MEND_PRODUCT_NAME=$(yq -r '.mend_sast_info | select(. != null) | ."mend-product-name"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export MEND_USER_EMAIL=$(yq -r '.mend_sast_info | select(. != null) | ."mend-user-email"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export MEND_SECRET_GROUP=$(yq -r '.mend_sast_info | select(. != null) | ."mend-secret-group"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
