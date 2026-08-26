#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2021, 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
## go-notify-generic.sh
##  builds and sends a slack notification


set -euo pipefail

# Set default values - For go-notify slack notifications
export GO111MODULE=${GO111MODULE:-"on"}
export GOPRIVATE=${GOPRIVATE:-"github.ibm.com/*"}
export IS_ONE_PIPELINE_RUN=${IS_ONE_PIPELINE_RUN:-"false"}

slack_channel=""
promotion_pr_branch=""

# Overrides for OnePipeline
if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
  # Source one-pipeline utils
  # WORKSPACE = /workspace/app = root directory
  source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh
  source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

  export SLACK_NOTIFY_REPO="${WORKSPACE}/promotion-repo"
  export PR_URL="${PR_HTML_URL}"

elif [[ -e ./pipe-data/pr.sh ]]; then
    . pipe-data/pr.sh
    echo "Git Environment:"
    env | grep ^PR_
    export SLACK_NOTIFY_REPO="slack-notify-repo"
fi

export promotion_pr_branch=${PR_BRANCH}
echo PROMOTION_PR_BRANCH: ${promotion_pr_branch}

if [[ -z "$promotion_pr_branch" ]]; then
  echo "Failed to find promotion_pr_branch. Can't send the slack message"
  exit 0
fi

pr_branch_name_partial="PROMOTION-BRANCH"  # works with both PROMOTION-BRANCH-* and OPS-PROMOTION-BRANCH-*

if [[ "${promotion_pr_branch}" == *"${pr_branch_name_partial}"* ]]; then
  echo "This PR is from a valid branch that will kick off tests."
else
  echo "The branch is not going to run tests. Skipping slack notification."
  exit 0
fi

eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

if [[ ! -e go-notify ]]; then
    echo "Cloning go-notify repo"
    mkdir go-notify
    git clone git@github.ibm.com:genctl-cicd/go-notify.git go-notify
    cd go-notify
    git checkout tags/${GO_NOTIFY_VERSION}
    echo "building and installing go-notify"
    go install
    cd ..
else
  echo "go-notify already exists"
fi

if ! [[ -f slack-info-input/channel ]]; then
    slack_channel="$(yq -r '.ops.slack_channel | select(. != null)' ${SLACK_NOTIFY_REPO}/master_environment.yaml)"
else
    slack_channel=$(cat slack-info-input/channel)
fi

# set status icon for markdown
status_icon=$SLACK_ICON
promotion_pr_title=${PR_TITLE}

if [[ "${promotion_pr_title}" == *OPS-PROM* ]] ; then
    echo "OPS-PROMOTION branch "
    message_info="$status_icon *${STATUS_OPS}* $status_icon
    ${PR_URL}"
else
    echo "PROMOTION branch "
    message_info="$status_icon *${STATUS}* $status_icon
    ${PR_URL}"
fi


# puts the message into a slack block kit json format https://api.slack.com/block-kit
get_slack_json(){ local message=$1
    echo "$(jq -c -n --arg message "$message" '{"blocks":[{"type": "section", "text": {"type": "mrkdwn","text": $message}}]}')"
}

printf "Posting to Slack channel #%s: %s\n" "${slack_channel}" "${message_info}"

messageJSON="$(get_slack_json "$message_info")"
go-notify slack --channel=${slack_channel} --token=${SLACK_TOKEN} --json="$messageJSON"
