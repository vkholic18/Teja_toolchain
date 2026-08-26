#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Used in prepare hostos release bundle ###
export PATH_TO_RELEASE_ENVIRONMENT=${WORKSPACE}/release-environment

### Used in deploy dal ###
export DEPLOY_ALL="true"
export DEPLOY_COMPONENT_ONLY="true"
export SIMPLE_DEPLOY_DAL_GHE_CHECK_LABEL="$(echo "${COMPONENT}" | tr '[:lower:]' '[:upper:]')_BRT"

### Used in check pr title and commits ###
export WORKSPACE_ROOT="NO_NEED_LOCAL_PARSING"

# Since this template is for PR WITHOUT smoke, we set this to false #
export KEEP_LOCK_AFTER_SUCCESFULL_DEPLOY="false"

# Extract the endpoint, this gives us stuff like eu-gb, us-south, etc
ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)
# TODO: PIPELINE_ID when we are in a subpipeline does not have value (Possible solution: Set the whole message in the parent pipeline ?)
export MULTIPLE_LOCKS_COMMIT_MSG="${ORG_AND_REPO} ${PIPELINE_TYPE} run ${BUILD_NUMBER} - 1P_INFO: ${PIPELINE_ID}/${PIPELINE_RUN_ID}/${ENDPOINT}"

export DEFAULT_UNDERCLOUD_FILE="ngdc_dal09-qz4-undercloud-hypervisor"

export ENV_TYPE="dev"
export DEPLOYMENT_ZONE=""
export LOGICAL_ZONE="Any"
export LOGICAL_REGION="SCMZR-QZ4-DAL"

export ATTRIBUTE_KEY=""
export ATTRIBUTE_VALUE="vpc_qz4_env1_sdn_attributes"

export ICR_MIGRATION_MODE="true"

### In order to optionally run static scan in PR ###
export RUN_STATIC_SCAN_IN_PR=$(yq -r '.run_static_scan_in_pr | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)

### Mend SAST Information ###
export MEND_PRODUCT_NAME=$(yq -r '.mend_sast_info | select(. != null) | ."mend-product-name"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export MEND_USER_EMAIL=$(yq -r '.mend_sast_info | select(. != null) | ."mend-user-email"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
export MEND_SECRET_GROUP=$(yq -r '.mend_sast_info | select(. != null) | ."mend-secret-group"' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
