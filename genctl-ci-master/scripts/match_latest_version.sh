#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2020
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# This script is intended to run when changes have been made to an image in artifactory, e.g. keylore:latest was updated
# This script gets the hash of the docker image, matches the tag of the other docker image (not latest) that matches it, and writes the result to a version.txt file
# This is intended to be a setup step, after which the change is pushed to the repository, thus generating a new git hash that is connected to a

## Variables
#ARTIFACTORY_SERVER
#ARTIFACTORY_REPO_PATH
#ARTIFACTORY_URL
#ARTIFACTORY_IMAGE_PATH
#ARTIFACTORY_USER
#CC_ARTIF_ACCESS_TOKEN
#CC_ARTIF_ACCESS_TOKEN
#REPOSITORY_DIRECTORY
#VERSION_FILE_PATH
#LATEST_TAG

set -eu # exit on error, exit on unset var

echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_URL} -u ${ARTIFACTORY_USER} --password-stdin

printf "Getting hash of tag \"${LATEST_TAG}\"... "
latest_hash=`docker manifest inspect ${ARTIFACTORY_URL}/${ARTIFACTORY_IMAGE_PATH}:${LATEST_TAG} -v | jq '.Descriptor.digest' -r`
echo "done"

printf "Getting image tags... "
# X-JFrog-Art-Api is what the api key must be passed in named as
get_result=$(curl --retry 5 -s -X GET --url "${ARTIFACTORY_SERVER}/api/docker/${ARTIFACTORY_REPO_PATH}/v2/${ARTIFACTORY_IMAGE_PATH}/tags/list" \
                  -H "Authorization: Bearer ${CC_ARTIF_ACCESS_TOKEN}" \
            )
printf "done\nProcessing results... "
all_image_tags=`echo "${get_result}" | jq '.tags[]' -r`
echo "done"

for image_tag in ${all_image_tags}
do
    # If the pairing is valid, continue, otherwise skip this tag
    if [[ ${image_tag} != ${LATEST_TAG} ]]; then
        printf "Comparing hash of tag \"${LATEST_TAG}\" to tag \"${image_tag}\" ... "
        # Getting the hash via docker's 'manifest inspect' command takes a bit of time, the actual comparison once we have the data is quick
        image_hash=`docker manifest inspect ${ARTIFACTORY_URL}/${ARTIFACTORY_IMAGE_PATH}:${image_tag} -v | jq '.Descriptor.digest' -r`
        if [[ ${image_hash} == ${latest_hash} ]]; then
            printf "\nImage hash of tag \"${image_tag}\" matched!\n"
            pushd ${REPOSITORY_DIRECTORY}
            version_file=${VERSION_FILE_PATH}
            echo "version file's current contents: "
            cat ${version_file}
            printf "Writing \"${image_tag}\" to \"${version_file}\"... "
            echo "${image_tag}" > ${version_file}
            printf "done\n"

            # Setup git to be able to add/commit files
            git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
            git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

            git add ${version_file}
            git commit -m "Updated ${VERSION_FILE_PATH}" | true # prevents pipeline from failing if no new docker image was uploaded to artifactory - necessary so orda bumps can happen in release for changes to the repository
            popd
            cp -R workspace-repo/. repo-updated
            echo "Ready to commit changes to git repository. "
            exit 0
        else
            echo "${image_tag}'s hash (${image_hash}) didn't match ${LATEST_TAG}'s hash (${latest_hash}), continuing"
        fi
    fi
done
echo "Failed to find an image that matched the tag \"${LATEST_TAG}\" in the repository"
exit 1
