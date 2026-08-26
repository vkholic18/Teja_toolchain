#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2024
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

## Inherited from genctl-ci/scripts/cd/go-notify-status.sh

set -euo pipefail

export PATH_TO_ENVIRONMENT_FILE=$1

CURRENT_PATH="$PWD"
cd ${PATH_TO_WORKSPACE_REPO}
latest_commit_id=$(git rev-parse HEAD)

curl -L \
-H "Accept: application/vnd.github.groot-preview+json" \
-H "Authorization: token $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: 2022-11-28" \
"https://github.ibm.com/api/v3/repos/${WORKSPACE_REPO_ORG}/$WORKSPACE_REPO_NAME/commits/$latest_commit_id/pulls" \
-o ${SLACK_DIR}/pr_data.json

cd ${CURRENT_PATH}

get_request_data() { local url=$1 api_key=$2

    response=$(curl -s --request GET \
    -L "${url}" \
    -H "Authorization: Bearer $api_key" \
    -w "%{http_code}" \
    -o 'out.json'
    )

    if [[ "$response" == "200" ]]; then
        cat out.json
    else
        >&2 echo "WARNING: Could not retrieve data from $url"
    fi
}

# puts the message into a slack block kit json format https://api.slack.com/block-kit
get_slack_json(){ local message=$1
    echo "$(jq -c -n --arg message "$message" '{"blocks":[{"type": "section", "text": {"type": "mrkdwn","text": $message}}]}')"
}

if ! [[ -f ${SLACK_DIR}/slack-handle ]]; then
    gh_user=$(jq -r '.[].user.login' ${SLACK_DIR}/pr_data.json)

    gh_user_url="${GH_API_ENDPOINT}/users/${gh_user}"
    user_email=$(get_request_data ${gh_user_url} $GITHUB_TOKEN | jq -r .email)

    slack_user_url="https://slack.com/api/users.lookupByEmail?email=${user_email}"
    slack_user_id=$(get_request_data ${slack_user_url} ${SLACK_TOKEN} | jq -r .user.id)

    if [ $slack_user_id != "null" ]; then
        slack_handle="<@$slack_user_id>"
    else
        slack_handle=${gh_user}
    fi

    echo $slack_handle > ${SLACK_DIR}/slack-handle
else
    slack_handle=$(cat ${SLACK_DIR}/slack-handle)
fi

# Send slack to channel defined in environment.yaml. E.g. ipops-monitoring
if ! [[ -f ${SLACK_DIR}/channel ]]; then
    channel=$(yq -r '.ops.slack_channel' "${PATH_TO_ENVIRONMENT_FILE}")
    printf $channel > ${SLACK_DIR}/channel
else
    channel=$(cat ${SLACK_DIR}/channel)
fi

cr_number=$(jq -e '.[].number' ${TICKET_DIR}/data.json 2>/dev/null || echo "")
cr_purpose="$(jq -e '.[].purpose' ${TICKET_DIR}/data.json 2>/dev/null || echo "")"


cr_url="https://${SERVICENOW_URL}/nav_to.do?uri=change_request.do?sys_id=${cr_number}"
pipeline_url="${PIPELINE_RUN_URL}"

if ! [[ -f ${SLACK_DIR}/threadID ]] && [ "$STATUS" = "Feature flags deployment failed" ]; then
    status_icon=":x:"
    message_info="$status_icon *${STATUS}* for ${WORKSPACE_REPO_NAME} ${slack_handle} ${SLACK_GROUP}""
    Pipeline url: ${pipeline_url}"
    printf "Posting to Slack channel #%s: %s\n" "${channel}" "${message_info}"
    if [[ -n $cr_number ]]; then
      message_info="${message_info}""
      CR# <${cr_url}|${cr_number}>"
    fi
    messageJSON="$(get_slack_json "$message_info")"
    go-notify slack --channel=${channel} --token=${SLACK_TOKEN} --json="$messageJSON"
    exit 1
fi

# Slack won't accept text message longer than 3000 characters
if (( ${#cr_purpose} > 2500 )); then
  cr_purpose="${cr_purpose:0:2499}
too long...truncated"
fi

# set status icon for markdown
status_icon=""
message_info=""
case ${STATUS} in
    "Pre-deploy started")
        status_icon=":arrow_forward:"
        message_info="${status_icon} *${STATUS}*
Author: ${slack_handle}
Pipeline job is $pipeline_url
CR# <${cr_url}|${cr_number}>
CR purpose: \`\`\`${cr_purpose}\`\`\`"
        ;;

    "Deploy succeeded")
        status_icon=":white_check_mark:"
        message_info="$status_icon *${STATUS}* ${slack_handle}"
        ;;

    "Deploy failed")
        status_icon=":x:"
        message_info="$status_icon *${STATUS}* ${slack_handle} ${SLACK_GROUP}"
        ;;


esac


printf "Posting to Slack channel #%s: %s\n" "${channel}" "${message_info}"

# use stage to determine thread params
if ! [[ -f ${SLACK_DIR}/threadID ]] && [ "$STATUS" = "Pre-deploy started" ]; then
    messageJSON="$(get_slack_json "$message_info")"
    echo "$messageJSON" > ${SLACK_DIR}/firstMessageJSON
    threadID=$(go-notify slack --channel=${channel} --token=${SLACK_TOKEN} --json="$messageJSON")
    if [[ ! -z "$threadID" ]]; then
        echo $threadID > ${SLACK_DIR}/threadID
    fi
else
    if [[ -f ${SLACK_DIR}/threadID ]]; then
        update_message_info="$status_icon *${STATUS}*"
        update_message="$(cat ${SLACK_DIR}/firstMessageJSON | jq -c  --arg status "$update_message_info" '.blocks[].text=(.blocks[].text | .text |= sub(":arrow_forward: .Pre-deploy started."; $status))')"
        go-notify slack --channel=${channel} --token=${SLACK_TOKEN} --json="$update_message" --threadID=$(cat ${SLACK_DIR}/threadID) --update
        go-notify slack --channel=${channel} --token=${SLACK_TOKEN} --json="$(get_slack_json "$message_info")" --threadID=$(cat ${SLACK_DIR}/threadID)
    fi
fi
