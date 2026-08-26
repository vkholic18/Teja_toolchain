#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
set -u

# The following environment variables need to be set before executing this script:
# PATH_TO_GENCTL_CI
# GHE_API_URL, GHE_API_TOKEN, REPOSITORY_NAME
# PR_NUMBER

# In addition the label to check should be the first argument
export LABEL_TO_SEARCH=$1

# Source tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Execute
generic_python_execution ${PATH_TO_GENCTL_CI}/scripts/check_pr_has_label ${PATH_TO_GENCTL_CI}/scripts/retry.sh