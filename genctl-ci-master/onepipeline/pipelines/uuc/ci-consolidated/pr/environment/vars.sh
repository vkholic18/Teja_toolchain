#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Used in check pr title and commits ###
export WORKSPACE_ROOT="NO_NEED_LOCAL_PARSING" 

# The save artifacts in PR to master of razee deals only with the first image
export SAVE_ARTIFACTS_ONLY_FIRST_IMAGE_MODE="true"
export SAVE_ARTIFACTS_SKIP_PACKAGES="true"

# Extract the endpoint, this gives us stuff like eu-gb, us-south, etc
ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)

export ICR_MIGRATION_MODE="true"

# Gets used for all common utilities for CI/CD
export PATH_TO_CICD_UTILS="${WORKSPACE}/${CI_CD_UTILS_REPO_NAME}"

#mend-sast related secrets
export MEND_PRODUCT_NAME=$(yq -r '.mend_sast_info | select(. != null) | ."mend-product-name"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export MEND_USER_EMAIL=$(yq -r '.mend_sast_info | select(. != null) | ."mend-user-email"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export MEND_SECRET_GROUP=$(yq -r '.mend_sast_info | select(. != null) | ."mend-secret-group"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)

export RUN_STATIC_SCAN_IN_PR=$(yq -r '.run_static_scan_in_pr | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)

