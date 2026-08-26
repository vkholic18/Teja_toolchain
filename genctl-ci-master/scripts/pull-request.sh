#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2020
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

set -eu

##
##  COMMANDS: 
##  
##  create - execute a given script to modify a repo, and then create a PR. return success if PR validation pass
##			usage: pull-request.sh create modified_repo_dir pr_id_dir
##				Input: modified_repo_dir, pr_title
##				Input/Output: pr_id_dir
##					for input - contains prtitle.txt file
##					for output - create prid file
##  merge - merge the PR and notify in slack
##			usage: pull-request.sh merge source_repo_dir pr_id_dir notify_dir
##				Input: source_repo_dir, pr_id_dir, notify_dir
##  fail - leave PR as-is, just notify in slack
##			usage: pull-request.sh fail notify_dir
##				Input: notify_dir
##  alertonly - leave PR as-is, just notify in slack
##			usage: pull-request.sh alertonly notify_dir
##				Input: notify_dir

COMMAND=$1
case "$COMMAND" in
"create")
	if [ $# -ne 3 ]; then
		echo "usage: pull-request.sh create modified_repo_dir pr_id_dir"
		exit 1
	fi

	DIR_MODIFIED_REPO=$2
	DIR_PR_ID=$3

	if [ ! -d "${DIR_MODIFIED_REPO}" ]; then
		echo 'missing directory'
		exit 1
	fi
	;;
"merge")
	if [ $# -ne 4 ]; then
		echo "usage: pull-request.sh merge source_repo_dir pr_id_dir notify_dir"
		exit 1
	fi

	DIR_SOURCE_REPO=$2
	DIR_PR_ID=$3
	DIR_NOTIFY=$4

	if [ ! -d "${DIR_SOURCE_REPO}" -o ! -d "${DIR_PR_ID}" -o ! -d "${DIR_NOTIFY}" ]; then
		echo 'missing directory'
		exit 1
	fi

	if [ ! -f "${DIR_PR_ID}/prid" ]; then
		echo 'pull request id file does not exist'
		exit 1
	fi

	PR_URL=$(cat "${DIR_PR_ID}/prid")

	;;
"fail")
	if [ $# -ne 3 ]; then
		echo "usage: pull-request.sh fail pr_id_dir notify_dir"
		exit 1
	fi

	DIR_PR_ID=$2
	DIR_NOTIFY=$3

	if [ ! -d "${DIR_PR_ID}" -o ! -d "${DIR_NOTIFY}" ]; then
		echo 'missing directory'
		exit 1
	fi

	if [ ! -f "${DIR_PR_ID}/prid" ]; then
		echo 'pull request id file does not exist'
		exit 1
	fi

	PR_URL=$(cat "${DIR_PR_ID}/prid")

	;;
"alertonly")
	if [ $# -ne 3 ]; then
		echo "usage: pull-request.sh alertonly pr_id_dir notify_dir"
		exit 1
	fi

	DIR_PR_ID=$2
	DIR_NOTIFY=$3

	if [ ! -d "${DIR_PR_ID}" -o ! -d "${DIR_NOTIFY}" ]; then
		echo 'missing directory'
		exit 1
	fi

	if [ ! -f "${DIR_PR_ID}/prid" ]; then
		echo 'pull request id file does not exist'
		exit 1
	fi

	PR_URL=$(cat "${DIR_PR_ID}/prid")

	;;
*)
	echo 'invalid command'
	exit 1
	;;
esac

PR_TITLE=$(cat "${DIR_PR_ID}/prtitle.txt")

case "${COMMAND}" in
"create")
	pushd "${DIR_MODIFIED_REPO}"
		git config --global --add hub.host github.ibm.com  # need this for `hub` cli to work
		git remote add upstream https://github.ibm.com/${GITHUB_ORG}/${GITHUB_REPO}.git
		git remote set-url upstream "${GITHUB_URI}:${GITHUB_ORG}/${GITHUB_REPO}.git"
		git push --force upstream
		PR_URL=$(hub pull-request --base "${BRANCH}" -m "${PR_TITLE}")
		echo "${PR_URL}" > ../"${DIR_PR_ID}"/prid
		head="$(git rev-parse HEAD)"
		set +ex
		hub ci-status --verbose "${head}" > /dev/null
		ci_status_exit_code=$?         
		set -e

        # if the repo does not have status checks enabled, allow to skip poll
        if [[ "${SKIP_STATUS_CHECK_POLL:-False}" == 'False' ]]; then
		echo Waiting for PR check pipeline to trigger
            while [ ${ci_status_exit_code} -ne 2 ]; do
                sleep 5
                set +e
                hub ci-status --verbose "${head}"
                ci_status_exit_code=$?
                set -e
            done
            # Check CI status every five seconds, terminate loop if it is no longer pending
            echo "Waiting for PR checks to complete"
            while [ ${ci_status_exit_code} -eq 2 ]; do
                sleep 5

                set +e
                hub ci-status --verbose "${head}"
                ci_status_exit_code=$?
                set -e
            done
            if [[ ${ci_status_exit_code} -eq 1 ]]; then
                echo "Checks failed, aborting"
                exit 1 # exit job as failure 
            fi
        fi
		set -x
    popd
	;;
"merge")
	pushd ./"${DIR_SOURCE_REPO}"
		git config --global --add hub.host github.ibm.com  # need this for `hub` cli to work
		PR_NUM=${PR_URL#*/pull/}
		hub api -XPUT repos/${GITHUB_ORG}/${GITHUB_REPO}/pulls/${PR_NUM}/merge \
		-f merge_method=squash -f commit_title="${PR_TITLE}"
	popd
	jq -n \
	--arg pr "$PR_URL" \
	'[
		{
		fallback: "Successful Merge",
		color: "#35D116",
		title: "${BUILD_PIPELINE_NAME}/${BUILD_JOB_NAME}",
		title_link: "${ATC_EXTERNAL_URL}/builds/${BUILD_ID}",
		text: "Successful Merge \($pr)",
		}
	]' > "${DIR_NOTIFY}"/message
	;;
"fail")
    jq -n \
    --arg pr "$PR_URL" \
    '[
      {
        fallback: "Failed PR",
        color: "#EA2D1A",
        title: "${BUILD_PIPELINE_NAME}/${BUILD_JOB_NAME}",
        title_link: "${ATC_EXTERNAL_URL}/builds/${BUILD_ID}",
        text: "Failed PR \($pr)",
      }
    ]' > "${DIR_NOTIFY}"/message
	;;
"alertonly")
    jq -n \
    --arg pr "$PR_URL" \
    '[
      {
        fallback: "Successful PR",
        color: "#35D116",
        title: "${BUILD_PIPELINE_NAME}/${BUILD_JOB_NAME}",
        title_link: "${ATC_EXTERNAL_URL}/builds/${BUILD_ID}",
        text: "Successful PR \($pr)",
      }
    ]' > "${DIR_NOTIFY}"/message
	;;
esac
