#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

export GO111MODULE="on"
export GOPRIVATE="github.ibm.com/*"
export MDS_CR_ASSIGNED_TO="iaasops1@us.ibm.com"
export META_DIR="${WORKSPACE}/ff-meta"
export TICKET_DIR="${WORKSPACE}/ticket"
export SNOW_CLI_VERSION="v1.7.2"
export PATH_TO_SERVICE_NOW_CLI="${WORKSPACE}/service-now-cli/service-now-cli"