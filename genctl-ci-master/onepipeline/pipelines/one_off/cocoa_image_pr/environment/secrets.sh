#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================


export CC_GITHUB_TOKEN=$(get_env "CC_GITHUB_TOKEN")
export CC_PRIVATE_KEY=$(get_env "CC_PRIVATE_KEY")
export TR_ARTIFACTORY_ACCESS_TOKEN=$(get_env "TR_ARTIFACTORY_ACCESS_TOKEN")
export TR_ARTIFACTORY_LOGIN=$(get_env "TR_ARTIFACTORY_LOGIN")
export ART_API_KEY=$(get_env "TR_ARTIFACTORY_ACCESS_TOKEN")