#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2020
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

set -eu

if [ $# -ne 3 ]; then
	echo "usage: pull-request-hostos-upgrade-payloads.sh  dir-source-repo dir-manifest-source dir-genctl-ci-repo"
	exit 1
fi

DIR_SOURCE_REPO=$1
DIR_MANIFEST_SOURCE=$2
DIR_GENCTL_CI_REPO=$3

if [ ! -d $DIR_SOURCE_REPO -o ! -d $DIR_MANIFEST_SOURCE -o ! -d $DIR_GENCTL_CI_REPO ]; then
	echo 'missing directory'
	exit 1
fi

pip install 'pipenv==2020.11.15'
# pipenv install needs LANG defined
export LANG=en_US.UTF-8
export LC_ALL=C
pipenv install --python 3.8 'PyYAML==6.0.1'

if [ ${MANIFEST_TYPE} == "sdn" ]; then
  MANIFEST_FILE=sdn-release-manifest.json
fi

if [ ${MANIFEST_TYPE} == "pds" ]; then
	MANIFEST_FILE=pds-release-manifest.json
fi

# convert manifest json from cloudnet to yaml that hostos expects
#  first strip out sdn custom keys from json
cat ${DIR_MANIFEST_SOURCE}/${MANIFEST_FILE} | jq -r 'del(.payload_manifest.payload_custom)' > manifest.json
pipenv run python -c 'import json; import yaml; print(yaml.safe_dump(json.loads(open("manifest.json").read()), sort_keys=False))' > manifest.yaml

eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"
JIRA_TICKET=`jq -r '.payload_manifest.payload_custom.sdn_release_ticket' ${DIR_MANIFEST_SOURCE}/${MANIFEST_FILE}`
PR_INFO=`jq -r '.payload_manifest.payload_custom.sdn_release_info' ${DIR_MANIFEST_SOURCE}/${MANIFEST_FILE}`
PR_TITLE="chore: ${JIRA_TICKET}: ${PR_INFO}"
echo $PR_TITLE > prid/prtitle.txt
# add new manifest file
git clone ${DIR_SOURCE_REPO} ${DIR_SOURCE_REPO}-updated # duplicate git repo files for update
pushd ./${DIR_SOURCE_REPO}-updated

	git checkout -b ${JIRA_TICKET}-$(date +"%Y-%m-%d_%H-%M-%S" )

	# Run one more grooming script for pds manifest file
	if [ ${MANIFEST_TYPE} == "pds" ]; then
		pipenv install -r ../${DIR_GENCTL_CI_REPO}/scripts/yaml-merge-override/requirements.txt
	  pipenv run python ../${DIR_GENCTL_CI_REPO}/scripts/yaml-merge-override/yaml-merge-override.py -b ${MANIFEST_TARGET} -n ../manifest.yaml -o ../out.yaml
		cp ../out.yaml ../manifest.yaml
		export SKIP_STATUS_CHECK_POLL="True"
	fi

	cp ../manifest.yaml ${MANIFEST_TARGET}

	git add . && git commit -m "${PR_TITLE}"
	git push -u --all
popd
BRANCH="${BRANCH}" genctl-ci-repo/scripts/pull-request.sh create ${DIR_SOURCE_REPO}-updated prid
