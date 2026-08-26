#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2021
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
## startJenkinsPipeline.sh
##
## params
##   JENKINS_USERNAME:
##   JENKINS_API_KEY:
##   SERVICENOW_URL:
##   JOB_NAME:
##   JENKINS_URL: https://sys-wcp-genctl-team-cd-jenkins.swg-devops.com
##   QUEUE_TIMEOUT: 60  #60 seconds

retry_arg="--connect-timeout 3 --retry 10 --retry-max-time 120"

get_build_info() { local build_url=$1
    retry=0
    maxRetries=10
    interval=12
    until [ ${retry} -ge ${maxRetries} ]; do
        curl \
            -s -S --fail --connect-timeout 3 \
            --user "${JENKINS_USERNAME}:${JENKINS_API_KEY}" \
            "${build_url}api/json" && break
        retry=$((retry+1))
        sleep "${interval}"
    done
}

set -euo pipefail

# Support jobs in folders by replacing "folderName/jobName" -> "folderName/job/jobName"
classic_job_path="${JOB_NAME/////job/}"

printf "Using Jenkins API key: ****$(printf $JENKINS_API_KEY | tail -c 4)\n"


# for good explanation of curl retries and timeouts
# https://stackoverflow.com/questions/10568497/how-does-curl-retry-max-time-seconds-work
curl_arg="-s -S -o /dev/null --fail ${retry_arg} -D /tmp/jenkins_headers.txt --user ${JENKINS_USERNAME}:${JENKINS_API_KEY}"

# add pipeline parameters
# DATA_ARGS array is necessary to encapsulate data that include spaces in them
for param in "$@"; do
    DATA_ARGS+=(--data "$param")
done

curl ${curl_arg} "${DATA_ARGS[@]}" "${JENKINS_URL}/job/${classic_job_path}/buildWithParameters"

queue_url="$(cat /tmp/jenkins_headers.txt | sed -n "s/^location\: \(.*\).*$/\1/p" | sed 's/\r$//')api/json"

printf "Waiting in queue url: %s\n" "${queue_url}"
end_time=$(( $(date +%s) + $QUEUE_TIMEOUT ))
while true; do
    queue_resp=$(
        curl \
            -s -S --fail ${retry_arg} \
            --user "${JENKINS_USERNAME}:${JENKINS_API_KEY}" \
            $queue_url
        )
    printf "\n${queue_resp}\n"
    if [[ "${queue_resp}" == "" ]]; then
        continue # try again
    fi

    build_url=$(echo $queue_resp | jq -r .executable.url)
    if [[ "$build_url" != "null" ]]; then
        break
    fi

    if (( $(date +%s) > $end_time )); then
        printf "\nERROR: Timeout exceeded\n"
        exit 1
    fi

    printf "."
    sleep 1
done
printf "\nFound build url: %s\n" "${build_url}"

printf "Building\n"
while true; do
    build_resp="$(get_build_info $build_url)"

    if [[ "$(echo $build_resp | jq -r .building)" == "false" ]]; then
        post_deploy_failure="$(echo $build_resp | jq -r '.actions[] | select(.properties) | .properties.post_deploy_failure')"

        if [[ -n $post_deploy_failure ]]; then
            echo $post_deploy_failure > failed-task/task
            printf "\nBuild passed with issues\n"
            exit_code=0
            break
        elif [[ "$(echo $build_resp | jq -r .result)" == "SUCCESS" ]]; then
            printf "\nBuild passed\n"
            exit_code=0
            break
        else
            printf "\nBuild $(echo $build_resp | jq -r .result)\n"
            exit_code=1
            break
        fi
    elif [[ -z "$build_resp" ]]; then
        exit_code=1
        break
    fi

    printf "."
    sleep 5
done

if [[ -n "$build_resp" ]]; then
    printf "\n\nBuild logs:\n"
    curl \
        -s \
        --user "${JENKINS_USERNAME}:${JENKINS_API_KEY}" \
        "${build_url}logText/progressiveText?start=0"
fi
exit $exit_code