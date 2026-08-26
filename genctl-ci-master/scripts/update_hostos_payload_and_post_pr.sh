#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2021
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

if [[ $SKIP_UPDATE_HOSTOS = true ]]; then
    echo "Nothing to do, no update to hostos will be performed. Exiting..."
    exit 0
fi

set -eu
ls -l

bldRoot="$(pwd)"


# load pr vars
echo "loading pr environment variables"
cat ./pipe-data/pr.sh
source ./pipe-data/pr.sh

##
# cut a new branch off of hostos-upgrade-payloads-repo
##
cd hostos-upgrade-payloads-repo

git checkout -b "${PR_ID}-$(date +%Y-%m-%d_%H-%M-%S)"

payload_yaml="${bldRoot}/hostos-upgrade-payloads-repo/manifests/${PAYLOAD}.yml"
##
# update the payload manifest file
##
version_file="${bldRoot}/build/build-versions"

# Check if the directory exist
if [[ -d "${version_file}" ]]; then
    if [ "$(ls -A ${version_file})" ]; then
        echo "Folder not empty, continue."
    else    
        echo "Folder is empty,nothing to process, exiting,"
        exit 0
    fi
else
    echo "No version file exists, exiting..."
    exit 0
fi    

# Analyze package to seperate components
# Packages should be composed as <package-name>_<package_version>_<architecture>.deb
for version_file in "${version_file}"/*.txt; do 
    for package in $(cat "${version_file}"); do
        package_part_count=$(echo $package | awk -F _ '{ print NF }')
        if [[ "${package_part_count}" -eq 3 ]]; then
            echo "================= updating hostOS package ${package} ================="
            package_name=$(echo $package | awk -F _ '{ print $1 }')
            package_version=$(echo $package | awk -F _ '{ print $2 }')
            if [[ "${DYNAMIC_VERSIONING:-false}" == true ]]; then
                arch=$(echo $package | sed "s/^\(.*\)_\(.*\)_\(.*\).deb\$/\3/" | tr -d '"')
            else
                arch=""
            fi
            echo "update_payload_inventory payload arguments, \"payload-yaml=\"${payload_yaml}, \"group=\"${GROUP_NAME}"
            echo "update_payload_inventory script package arguments, \"package-name=\"${package_name}, \"package-version=\"${package_version}, \"architecture=\"${arch}"
            python3 "${bldRoot}/genctl-ci-repo/scripts/update_payload_inventory.py" "${payload_yaml}" "${GROUP_NAME}" "${package_name}" "${package_version}" "${arch}"
        else
            echo "skipping ${package}"
            echo "${package} should be formatted as following <package-name>_<package_version>_<architecture>.deb" 
        fi
    done
done


##
# create a pr, to the hostos team, based off the above change
##
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

SOURCE_PR_JIRA=$(echo $PR_TITLE | awk -F: '{print $1}')
SOURCE_PR_BODY=$(echo $PR_TITLE | awk -F: '{print $2}' | tr '[A-Z]' '[a-z]')

HOSTOS_PR_TITLE="chore: ${SOURCE_PR_JIRA}: ${SOURCE_PR_BODY}"
mkdir -p ../prid
echo "${HOSTOS_PR_TITLE}" > ../prid/prtitle.txt
# add new manifest file

git add "${payload_yaml}"
git commit -m "${HOSTOS_PR_TITLE}"
git push -u --all

cd "${bldRoot}" # we need to switch out as the script will break otherwise.

# BRANCH needs to be set prior and cannot be carried in without changing a bunch of
# code related to a recent commit 4e978133ffd2209645cea0b642b454265b5a085e
# BRANCH is pulled externally in the pull-request.sh script
# branch, as used by the context of the base branch of host-os-payloads repo
# this is carried in from the pipeline and into the calling yaml
SKIP_STATUS_CHECK_POLL='True' "${bldRoot}/genctl-ci-repo/scripts/pull-request.sh" create "${bldRoot}/hostos-upgrade-payloads-repo" prid
