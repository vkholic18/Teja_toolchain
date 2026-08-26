#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================


### Used in build ###
export SKIP_UNIT_TESTS="true"

# auto merge
export PR_NUMBER=$(get_env "PR_URL" | grep -o '[^/]*$') ## See if we can move this to one_pipeline utils
export PR_SHA=$(load_repo app-repo commit) ### See if we can move this to one_pipeline utils
export APPROVE_BEFORE_MERGE="true"

export PROCESS_BUILD_META_UPLOAD_PACKAGES_INCLUDE_METADATA="true"