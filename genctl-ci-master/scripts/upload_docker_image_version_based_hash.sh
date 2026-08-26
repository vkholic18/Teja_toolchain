#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2020
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# This script is intended to be run after the "match_latest_version.sh" file has run, and the changes produced by that
# have been pushed to master, thus generating a new git hash.

# This script references the version.txt file's contents (updated in the aforementioned script) to pull down that docker image.
# It then re-tags the pulled image with the git hash corresponding to the repository, and pushes it to our space in artifactory.

## Variables
#ARTIFACTORY_PULL_URL
#ARTIFACTORY_PULL_PATH
#ARTIFACTORY_PULL_USER
#ARTIFACTORY_PULL_PASS

#ARTIFACTORY_PUSH_URL
#ARTIFACTORY_PUSH_PATH
#ARTIFACTORY_PUSH_USER # required when $ARTIFACTORY_PUSH_URL != $ARTIFACTORY_PULL_URL
#ARTIFACTORY_PUSH_PASS # required when $ARTIFACTORY_PUSH_URL != $ARTIFACTORY_PULL_URL

#REPOSITORY_DIRECTORY
#VERSION_FILE_PATH

set -eu # exit on error, unset var

echo "Reading tag from version file "
# We will pull down the image based on the tag contained inside the version file.
version_file=${REPOSITORY_DIRECTORY}/${VERSION_FILE_PATH}
matched_image_tag=`cat ${version_file}`
echo "Determining architecture (if one was defined)"
# architecture_append relies on the image being named something in the form of {tag-base}{"-"}{architecture} e.g. "1.2.1-amd64"
set +e # allow error for grep, that way we can say what the problem is in logging
architecture_append=`echo ${matched_image_tag} | grep -oP "\-.*"`
if [[ "${architecture_append}" == "" ]]; then
    echo "Error: The image did not have an architecture provided in the tag \"${matched_image_tag}\""
    exit 1
fi
set -e # Re-enable exit on error, now that we've handled the possible grep error
echo "Getting git hash for the repository... "
# Get the git hash of the just-updated repository.
pushd ${REPOSITORY_DIRECTORY} >> /dev/null
git_hash=`git rev-parse --verify HEAD`
popd >> /dev/null

echo "Git hash value is \"${git_hash}\""

echo "Docker login(s)"
echo ${ARTIFACTORY_PULL_PASS} | docker login ${ARTIFACTORY_PULL_URL} -u ${ARTIFACTORY_PULL_USER} --password-stdin
if [[ ${ARTIFACTORY_PULL_URL} != ${ARTIFACTORY_PUSH_URL} ]]; then
    echo ${ARTIFACTORY_PUSH_PASS} | docker login ${ARTIFACTORY_PUSH_URL} -u ${ARTIFACTORY_PUSH_USER} --password-stdin
fi
echo "Completed docker login(s)"

echo "Pulling \"${ARTIFACTORY_PULL_URL}/${ARTIFACTORY_PULL_PATH}:${matched_image_tag}\""
docker pull ${ARTIFACTORY_PULL_URL}/${ARTIFACTORY_PULL_PATH}:${matched_image_tag}
printf "Re-tagging image... "
docker tag ${ARTIFACTORY_PULL_URL}/${ARTIFACTORY_PULL_PATH}:${matched_image_tag} ${ARTIFACTORY_PUSH_URL}/${ARTIFACTORY_PUSH_PATH}:${git_hash}${architecture_append}
printf "done\nImage to push: \n"
echo "${ARTIFACTORY_PUSH_URL}/${ARTIFACTORY_PUSH_PATH}:${git_hash}${architecture_append}"
echo "Pushing image"
docker push ${ARTIFACTORY_PUSH_URL}/${ARTIFACTORY_PUSH_PATH}:${git_hash}${architecture_append}
echo "done"

echo "Proceeding to create and upload manifest" # This is needed for the release job which utilizes the manifest to get images.
echo "Creating manifest"
manifest_name="${ARTIFACTORY_PUSH_URL}/${ARTIFACTORY_PUSH_PATH}:${git_hash}"
manifest_params="${manifest_name} ${ARTIFACTORY_PUSH_URL}/${ARTIFACTORY_PUSH_PATH}:${git_hash}${architecture_append}"
echo "done creating manifest, now pushing manifest."
docker manifest create ${manifest_params}
docker manifest push ${manifest_name}
echo "done"
