#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

export PR_NUMBER=$(get_env "PR_URL" | grep -o '[^/]*$') ## See if we can move this to one_pipeline utils
export PR_SHA=$(load_repo app-repo commit) ### See if we can move this to one_pipeline utils
