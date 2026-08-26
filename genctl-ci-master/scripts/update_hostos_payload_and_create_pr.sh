#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2020
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

set -eux
ls -l

bldRoot="$(pwd)"

#
# the below will be pulled into its own shell in the morning
#
cat ./${REPO_NAME}/hack/ci/version.txt

# load pr vars
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
python3 "${bldRoot}/genctl-ci-repo/scripts/update_payload_inventory.py" "${payload_yaml}" "${GROUP_NAME}" "${COMPONENT}" "$(cat ${bldRoot}/${REPO_NAME}/hack/ci/version.txt)"

##
# create a pr, to the hostos team, based off the above change
##
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

HOSTOS_PR_TITLE="chore: ${PR_TITLE}"
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

