#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Aliases are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

### Used in check PR has label ###
export GHE_API_URL=${IBM_GITHUB_API_URI_BASE}
export REPOSITORY_NAME=${ORG_AND_REPO}
export PR_NUMBER=${PR_ID}


export PATH_TO_SDN_DEVOPS_REPO=${PATH_TO_WORKSPACE_REPO}

