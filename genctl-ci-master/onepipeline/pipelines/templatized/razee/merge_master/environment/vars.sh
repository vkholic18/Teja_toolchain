#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Empty export of gh-release (Required in some tasks)
export PATH_TO_GH_RELEASE=""

### Used in retag ###
export PATH_TO_IMAGES_TO_COPY="" # We don't use the mode of list of images
export VERIFY_COPIED_IMAGES_CAN_BE_PULLED="true" # Used to make an additional verification that all the copied images can be pulled

### Used in upload to COS ###
export COS_UPLOAD_CONTENT_ROOT="hack/deploy/razee/"
export COS_UPLOAD_FILES_FILTER=""

### Used in LaunchDarkly ###
export LAUNCH_DARKLY_USE_IN_DEFAULT_RULE="true"
# TODO: Decide if this is the approach we want (In that case make relevant changes in Concourse pipelines for them to be like this or add the empty defaults in the task)
export LAUNCH_DARKLY_CREATE_VARIATION_ONLY="false"


export TWO_STEP_INVENTORY_UPDATE_MODE="true"

export ICR_MIGRATION_MODE="true"

# Used in inventory
export SKIP_ICR_IMAGES_FOR_INVENTORY_UPDATE="true"