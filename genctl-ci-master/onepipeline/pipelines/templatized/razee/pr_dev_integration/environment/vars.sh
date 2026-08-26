#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Empty export of gh-release (Required in some tasks)
export PATH_TO_GH_RELEASE=""

### Used in validate razee files ###
export IS_DEV_INTEGRATION="true"

### Used in check pr title and commits ###
export WORKSPACE_ROOT="NO_NEED_LOCAL_PARSING" 

### Used in go vetting ###
export PACKAGES="github.ibm.com/genctl/..."  

### Used in razee check duplicate keys ###
export EXIT_ON_TASK_FAILURE_RAZEE_CHECK_DUPLICATE_KEYS="false" # Should give us similar effect than Concourse 'try'

### Used in anti-patterns ###
export EXIT_ON_TASK_FAILURE_ANTI_PATTERNS="false" # Should give us similar effect than Concourse 'try'

### Used in upload to COS ###
export COS_UPLOAD_CONTENT_ROOT="hack/deploy/razee/"
export COS_UPLOAD_FILES_FILTER=""

### In order to optionally run static scan in PR ###
export RUN_STATIC_SCAN_IN_PR=$(yq -r '.run_static_scan_in_pr | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export RUN_STATIC_SCAN_IN_PR_TO_DEV_INT=$(yq -r '.run_static_scan_in_pr_to_dev_int | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)

export ICR_MIGRATION_MODE="true"

### Mend SAST Information ###
export MEND_PRODUCT_NAME=$(yq -r '.mend_sast_info | select(. != null) | ."mend-product-name"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export MEND_USER_EMAIL=$(yq -r '.mend_sast_info | select(. != null) | ."mend-user-email"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export MEND_SECRET_GROUP=$(yq -r '.mend_sast_info | select(. != null) | ."mend-secret-group"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
