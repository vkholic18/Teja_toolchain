#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

#artifact age since creation and never been downloaded
#export DAYS_PASSED_FOR_ZERO_DOWNLOADS="777"

#artifact age since last download downloaded
#export DAYS_PASSED_SINCE_LAST_DOWNLOAD="10000"

#NEVER-DOWNLOADED or OBSOLETE
#export QUERY_MODE="NEVER-DOWNLOADED"

#export CLEANUP_DRY_RUN="false"

#artifactory repository to scan
#export REPOS_TO_SCAN="wcp-genctl-sandbox-docker-local"

#export QUERY_LIMIT="15000"

#IMAGES-REPO or PACKAGES-REPO
#export ARTIFACT_TYPE= "IMAGES-REPO"

#optional, defines path in the REPOS_TO_SCAN for query
#export ARTIFACTS_PATH = "genctl/acadia"


export DAYS_PASSED_FOR_ZERO_DOWNLOADS=$(get_env "DAYS_PASSED_FOR_ZERO_DOWNLOADS")
export DAYS_PASSED_SINCE_LAST_DOWNLOAD=$(get_env "DAYS_PASSED_SINCE_LAST_DOWNLOAD")
export CLEANUP_DRY_RUN=$(get_env "CLEANUP_DRY_RUN")
export REPOS_TO_SCAN=$(get_env "REPOS_TO_SCAN")
export QUERY_LIMIT=$(get_env "QUERY_LIMIT")
export QUERY_MODE=$(get_env "QUERY_MODE")
export ARTIFACT_TYPE=$(get_env "ARTIFACT_TYPE")
export ARTIFACTS_PATH=$(get_env "ARTIFACTS_PATH")

