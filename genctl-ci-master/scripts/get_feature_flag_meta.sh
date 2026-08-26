#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -eux

# Make sure we are in the root directory
pushd ${WORKSPACE}

# Create directory ff-meta to save meta.json
export META_DIR="${WORKSPACE}/ff-meta"
[[ ! -d ${META_DIR} ]] && mkdir -p ${META_DIR}

cp ${PATH_TO_GENCTL_CI}/onepipeline/pipelines/cd/templatized/release_bundle_deploy/pr_master/environment/ff-meta.json ${META_DIR}/meta.json

if [ $? -ne 0 ]; then
    printf "\nFailed to copy ff-meta.json:\n"
    exit 1
fi

cat ff-meta/meta.json

popd
