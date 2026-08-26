#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2021
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##


# This script is used to push debian build packages to artifactory
# Needs to be called from the deb artifacts directory
# Required environment variables
# ARTIFACTORY_PATH - artifactory base host name
# ARTIFACTORY_GENERIC_REPO_PATH - artifactory debian repo to upload the artifact to
# CC_ARTIF_ACCESS_TOKEN - token to upload to artifactory

set -eu

if [ $# -ne 2 ]; then
	echo "usage: push_db_to_artifactory.sh requires 2 params, package_location, pkg_prefix"
	exit 1
fi

pkg_location=${1}
pkg_prefix=${2}

echo "Uploading packages..."

# Support multiple packages based with the local_disk_tools prefix
for pkg in ${pkg_prefix}; do
    pkg_name="$(basename ${pkg}_*.deb)"
    echo "Push deb package to artifactory REPO ${ARTIFACTORY_PATH}/${ARTIFACTORY_GENERIC_REPO_PATH}/${pkg_location}/${pkg_name} : $pkg_name"

    ARTIFACT_LOCAL_FILE_PATH="${pkg_name}"
    ARTIFACTORY_FILE_PATH="${ARTIFACTORY_PATH}/${ARTIFACTORY_GENERIC_REPO_PATH}/${pkg_location}/${pkg_name}"
    ARTIFACT_META=';deb.distribution=bionic;deb.component=main;deb.architecture=amd64'
    set +x # so we don't log anything
    curl --retry 5 --fail -X PUT -T "${ARTIFACT_LOCAL_FILE_PATH}" \
        -H "Authorization: Bearer ${CC_ARTIF_ACCESS_TOKEN}" \
        "${ARTIFACTORY_FILE_PATH}${ARTIFACT_META}"
    rc=$?
    set -x

    if [ $rc -ne 0 ]; then
        echo "ERROR: Curl failed! rc=$rc"
        exit 1
    fi
done
