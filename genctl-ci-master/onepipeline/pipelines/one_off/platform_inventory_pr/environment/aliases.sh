#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Aliases are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

### Used for searching cra setup ###
export WORKSPACE_PATH=${PATH_TO_WORKSPACE_REPO}

export CC_GIT_SHA=$(load_repo app-repo commit)
export TR_ARTIFACTORY_ACCESS_TOKEN=${CC_ARTIF_ACCESS_TOKEN}
export TR_ARTIFACTORY_LOGIN=${ARTIFACTORY_USER}
