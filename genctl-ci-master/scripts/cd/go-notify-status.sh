#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2021
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
## go-notify-status.sh
##  builds and sends a slack notification based on pipeline status


set -euo pipefail

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

if ! [[ -f slack-info-input/slack-handle ]]; then
    url=$(cat workspace-repo/.git/url)
    pr_env_suffix=${url#*com/}
    pr_env_path=${pr_env_suffix%%/pull*}

    pr_endpoint_url="${GH_API_ENDPOINT}/repos/${pr_env_path}/pulls/${url##*/}"
    gh_user=$(get_request_data ${pr_endpoint_url} $GHE_APIKEY | jq -r .user.login)

    gh_user_url="${GH_API_ENDPOINT}/users/${gh_user}"
    user_email=$(get_request_data ${gh_user_url} $GHE_APIKEY | jq -r .email)

    slack_user_url="https://slack.com/api/users.lookupByEmail?email=${user_email}"
    slack_user_id=$(get_request_data ${slack_user_url} ${SLACK_TOKEN} | jq -r .user.id)

    if [ $slack_user_id != "null" ]; then
        slack_handle="<@$slack_user_id>" 
    else
        slack_handle=${gh_user}
    fi

    echo $slack_handle > slack-info/slack-handle
else
    slack_handle=$(cat slack-info-input/slack-handle)
fi

if ! [[ -f slack-info-input/channel ]]; then
    channel="$(yq r workspace-repo/environment.yaml 'ops.slack_channel')"
    printf $channel > slack-info/channel
else
    channel=$(cat slack-info-input/channel)
fi

# get params
channel="$(yq r workspace-repo/environment.yaml 'ops.slack_channel')"
cr_number="$(jq -r .CRNumber ticket/data.json)"
cr_url="$(jq -r .CrURL ticket/data.json)"
pipeline_url="$(cat metadata/atc_external_url)/builds/$(cat metadata/build_id)"
cr_purpose="$(service-now-cli ${SNOW_CLI_FLAGS} -t ${MDS_SERVICENOW_IAM_APIKEY} read ${cr_number} | jq -r .purpose)"
user_impact="$(service-now-cli ${SNOW_CLI_FLAGS} -t ${MDS_SERVICENOW_IAM_APIKEY} read ${cr_number} | jq -r .impact)"
env_type="$(jq -r .TestEnvironmentType ticket/data.json)"
region_name="$(yq r workspace-repo/environment.yaml 'name')"

if [[ -f "failed-task/task" ]]; then
    STATUS="Deploy succeeded with issues"
fi

# Slack won't accept text message longer than 3000 characters
if (( ${#cr_purpose} > 2500 )); then
  cr_purpose="${cr_purpose:0:2499}
too long...truncated"
fi 

# set status icon for markdown
status_icon=""
slack_group=""
message_info=""
deploy_status=""
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

    "Deploy aborted")
        status_icon=":cancel_icon:"
        message_info="$status_icon *${STATUS}* ${slack_handle} ${SLACK_GROUP}"
        ;;
    
    "Deploy succeeded with issues")
        status_icon=":warning:"
        message_info="$status_icon *${STATUS}* ${slack_handle} ${SLACK_GROUP}"
        ;;
esac

# puts the message into a slack block kit json format https://api.slack.com/block-kit
get_slack_json(){ local message=$1
    echo "$(jq -c -n --arg message "$message" '{"blocks":[{"type": "section", "text": {"type": "mrkdwn","text": $message}}]}')"
}

printf "Posting to Slack channel #%s: %s\n" "${channel}" "${message_info}"

# use stage to determine thread params
if ! [[ -f slack-info-input/threadID ]] && [ "$STATUS" = "Pre-deploy started" ]; then
    messageJSON="$(get_slack_json "$message_info")"
    echo "$messageJSON" > slack-info/firstMessageJSON
    threadID=$(go-notify slack --channel=${channel} --token=${SLACK_TOKEN} --json="$messageJSON")
    if [[ ! -z "$threadID" ]]; then
        echo $threadID > slack-info/threadID
    fi
else
    if [[ -f slack-info-input/threadID ]]; then
        update_message_info="$status_icon *${STATUS}*"
        update_message="$(cat slack-info-input/firstMessageJSON | jq -c  --arg status "$update_message_info" '.blocks[].text=(.blocks[].text | .text |= sub(":arrow_forward: .Pre-deploy started."; $status))')"
        go-notify slack --channel=${channel} --token=${SLACK_TOKEN} --json="$update_message" --threadID=$(cat slack-info-input/threadID) --update
        go-notify slack --channel=${channel} --token=${SLACK_TOKEN} --json="$(get_slack_json "$message_info")" --threadID=$(cat slack-info-input/threadID)
    fi
fi

if [[ $env_type == "prod" || $env_type == "staging" ]]; then
    echo -n "" > cr_purpose
    printf "Change Feature Flags to new variation value\n" >> cr_purpose
    for projects in $(cat deploy-eyaml/environment.json | jq '.apps.feature_flags | keys | .[]'); do 
        projects=$(echo $projects | sed -e 's/^"//' -e 's/"$//') 
        for ff in $(cat deploy-eyaml/environment.json | jq --arg key $projects '.apps.feature_flags[$key] | keys | .[]'); do
            ff_name=$(jq -r ".apps.feature_flags.\"$projects\"[$ff]|(.name)"  deploy-eyaml/environment.json)
            rule_length=$(jq ".apps.feature_flags.\"$projects\"[$ff].rules | length" deploy-eyaml/environment.json)
            ff_variations=""
            if [[ $rule_length == 0 ]]; then
                ff_variations=$(jq -r ".apps.feature_flags.\"$projects\"[$ff].default.variation_value" deploy-eyaml/environment.json)
            fi
            for (( k=0; k<${rule_length}; k++ )); do
                ff_variations+=" "$(jq -r ".apps.feature_flags.\"$projects\"[$ff].rules[$k].variation_value" deploy-eyaml/environment.json)           
            done  
            printf "Feature Flag: %s           Variation: %s \n" $ff_name "${ff_variations}" >> cr_purpose
        done
    done

    if [[ "$STATUS" == "Pre-deploy started" ]]; then
        deploy_status="Starting"
    elif [[ "$STATUS" == "Deploy succeeded" ]]; then
        deploy_status="Completed"
    else    
        deploy_status=$STATUS
    fi

    message="Change Request: <${cr_url}|${cr_number}>
    CR purpose: \`\`\`$(cat cr_purpose)\`\`\`
    Region: ${region_name}
      User Impact: ${user_impact}
    Status: ${deploy_status}"

    if [[ $env_type == "prod"  ]]; then
       env_type="production"
    fi

    slack_channel="rm-"$env_type
    printf "Posting to Slack channel #%s: %s\n" "${slack_channel}" "${message}"
    messageJSON="$(get_slack_json "$message")"
    go-notify slack --channel=${slack_channel} --token=${SLACK_TOKEN} --json="$messageJSON"
fi