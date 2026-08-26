#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Source tekton api utils
source "${PATH_TO_GENCTL_CI}/onepipeline/utils/tekton_api_utils.sh"

# Source lock utils
source ${PATH_TO_GENCTL_CI}/tools/lock_and_queue_utils/lock.sh

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}" 

# Come back
popd

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

export WORKSPACE_REPO_NAME=${PIPELINE_REPO_NAME}
export PATH_TO_WORKSPACE_REPO="${WORKSPACE}/${WORKSPACE_REPO_NAME}"

pushd ${PATH_TO_WORKSPACE_REPO}

export ISSUE_URL="$(jq '.issue.url' '/trigger-payload/payload.json')"
export ISSUE_API_URL=$(echo ${ISSUE_URL:1:-1}  | sed 's|\(.*\)/.*|\1|')  
export ISSUE_NUMBER="$(jq '.issue.number' '/trigger-payload/payload.json')"

ISSUE_INFO=$(curl -s -X GET --location --header "Authorization: Bearer ${GITHUB_TOKEN}" --header "Accept: application/json" "${ISSUE_API_URL}/${ISSUE_NUMBER}")

ISSUE_TITLE=$(echo $ISSUE_INFO | jq -r '.title')
ISSUE_CREATOR=$(echo $ISSUE_INFO | jq -r '.user.login')
export LOCK_NAME=$(echo $ISSUE_TITLE | cut -d ' ' -f4)
echo $LOCK_NAME
echo $ISSUE_CREATOR

source "${PATH_TO_GENCTL_CI}/onepipeline/utils/iam_utils.sh"

eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"


check_last_commit_age() {
  LAST_COMMIT_DATE=$(git log -1 --pretty=format:%ad)
  LAST_COMMIT_DATE=${LAST_COMMIT_DATE%%+*}
  LAST_COMMIT_DATE_SEC=$(date -d "$LAST_COMMIT_DATE" +%s)
  CURRENT_DATE_SEC=$(date +%s)
  TIME_DIFF=$(( (CURRENT_DATE_SEC - LAST_COMMIT_DATE_SEC) / 86400 ))
  echo "commit was done: $TIME_DIFF day ago"
  if [ $TIME_DIFF -ge 1 ]; then
    export LAST_COMMIT_OLDER_THAN_DAY=true
  else
    export LAST_COMMIT_OLDER_THAN_DAY=false
  fi
}

check_last_commit_age_for_master() {
  LAST_COMMIT_DATE=$(git log -1 --pretty=format:%ad)
  LAST_COMMIT_DATE=${LAST_COMMIT_DATE%%+*}
  LAST_COMMIT_DATE_SEC=$(date -d "$LAST_COMMIT_DATE" +%s)
  CURRENT_DATE_SEC=$(date +%s)
  TIME_DIFF=$(( (CURRENT_DATE_SEC - LAST_COMMIT_DATE_SEC) / 86400 ))
  echo "commit was done: $TIME_DIFF day ago"
  if [ $TIME_DIFF -ge 1 ]; then
    export LAST_COMMIT_OLDER_THAN_DAY=true
  else
    export LAST_COMMIT_OLDER_THAN_DAY=false
  fi
}

#function to release lock because of MASCD pipeline
function release_mascd_lock(){
    echo "Proceeding to release MASCD Lock...."
    #example of the commit msg:
    #PREVIOUS_COMMIT_MSG="Lock rias-ng-us-south-dal-dev25-etcd released by MASCD user releasing locking for PipelineID: 07c73fb3-87bb-46f8-aa15-d2fb8b70f69b and PipelineRunID: dc4d119e-0682-4f2d-9939-d3820c464a84"
    PIPELINE_INFO="${PREVIOUS_COMMIT_MSG#*PipelineID: }"
    export PIPELINE_ID=$(echo $PIPELINE_INFO | cut -d ' ' -f1)
    export PIPELINE_RUN_ID=$(echo $PIPELINE_INFO | cut -d ' ' -f4)
    export ENDPOINT="us-south"
    if [ -n "$PIPELINE_ID" ] && [ -n "$PIPELINE_RUN_ID" ] && [ -n "$ENDPOINT" ]; then
        echo "Pipeline ID received"
        if is_uuid $PIPELINE_ID; then
            echo "$PIPELINE_ID is a valid UUID."
        else
            echo "$PIPELINE_ID is not a valid UUID."
            exit 1
        fi
        if is_uuid $PIPELINE_RUN_ID; then
            echo "$PIPELINE_RUN_ID is a valid UUID."
        else
            echo "$PIPELINE_RUN_ID is not a valid UUID."
            exit 1
        fi
    else
        echo "One of PIPELINE_ID, PIPELINE_RUN_ID and/or ENDPOINT is not received"
        exit 1
    fi

    BASE_URL="api.${ENDPOINT}.devops.cloud.ibm.com"
    echo $BASE_URL
    get_pipeline_status

    if [ $PIPELINE_STATUS = "failed" ] || [ $PIPELINE_STATUS = "cancelled" ]; then
        echo "Proceeding to release lock!"
        release_the_lock_brt
        add_comment_to_github_issue "Lock has been successfully released!"
        close_github_issue
    elif $LAST_COMMIT_OLDER_THAN_DAY; then
        release_the_lock_brt
        add_comment_to_github_issue "Found stale MASCD lock, released it!"
        close_github_issue
    else
        echo "Pipeline status is other than failed, can not release lock"
        echo "Please reach out to #vpc-ci-onepipeline channel"
        add_comment_to_github_issue "Pipeline status is other than the valid ones, it maybe running, can not release lock, Please reach out to #vpc-ci-onepipeline channel"
    fi
}

function release_the_lock_brt(){
    git checkout ${LOCK_NAME}
    # Export variables required for the script
    export PATH_TO_BRT_LOCKS="${PATH_TO_WORKSPACE_REPO}/${MASCD_BRT_POOL}"
    export COMMIT_MSG="the user ${ISSUE_CREATOR} through request raised via issue:#${ISSUE_NUMBER}"
    release_lock "${PATH_TO_BRT_LOCKS}" ${LOCK_NAME} "${COMMIT_MSG}" 360 10 
}

function release_the_lock_mzone(){
    git checkout ${LOCK_NAME}
    # Export variables required for the script
    export PATH_TO_BRT_LOCKS="${PATH_TO_WORKSPACE_REPO}/${FOLDER_NAME}"
    export COMMIT_MSG="the user ${ISSUE_CREATOR} through request raised via issue:#${ISSUE_NUMBER}"
    release_lock "${PATH_TO_BRT_LOCKS}" ${LOCK_NAME} "${COMMIT_MSG}" 360 10 
}

#function to get status of pipeline
function get_pipeline_status(){
    PIPELINE_STATUS=$(curl -s -X GET --location --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" --header "Accept: application/json" "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${PIPELINE_RUN_ID}?includes=definitions" | jq -r '.status')
    export $PIPELINE_STATUS
}

#function to close github issue
function close_github_issue(){
    curl -s -X POST "${ISSUE_API_URL}/${ISSUE_NUMBER}" -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Content-Type: application/json"  -d '{"state": "closed"}' -o /dev/null
}
  
#function to add comment to github issue
function add_comment_to_github_issue(){
    COMMENT="${1}"
    curl -s -X POST "${ISSUE_API_URL}/${ISSUE_NUMBER}"/comments -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Content-Type: application/json" -d "{\"body\": \"$COMMENT\"}" -o /dev/null
}

function is_uuid() {
  UUID_TO_TEST=$1
  if [[ $UUID_TO_TEST =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    return 0
  else
    return 1
  fi
}

#function to find failed dynamic scan
function check_dynamic_scan_run(){
    LIMIT=4
    pipeline_runs=$(curl -s -X GET --location --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" --header "Accept: application/json" "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs?trigger.name=taas-worker-trigger&limit=${LIMIT}")
    for i in {0..3}; do
        run_info=$(jq -r ".pipeline_runs[$i]" <<< "$pipeline_runs")
        status=$(jq -r ".pipeline_runs[$i].status" <<< "$pipeline_runs")
        build_number=$(jq -r ".pipeline_runs[$i].build_number" <<< "$pipeline_runs")
        echo "checking for ${build_number} build_number and the status is ${status}"
        if echo "$run_info" | grep -q "dynamic-scan-as-subpipeline"; then
            echo "Found possible dynamic scan pipeline that would have acquired the lock!"
            if [ $status = "failed" ] || [ $status = "cancelled" ] || [ $status = "error" ]; then
                echo $build_number
                release_the_lock_brt
                add_comment_to_github_issue "Lock was acquired by dynamic scan pipeline with build number: ${build_number}"
                close_github_issue
                exit 0
            elif [ $status = "running" ]; then
                echo $build_number
                add_comment_to_github_issue "Lock is acquired by dynamic scan pipeline with build number: ${build_number} and is still running, will not proceed to release the lock!"
                exit 1
            elif [ $status = "succeeded" ]; then
                echo $build_number
                add_comment_to_github_issue "Lock is acquired by dynamic scan pipeline with build number: ${build_number} and is successful, but may have not released the lock, please check with #vpc-ci-onepipeline team!"
                exit 1
            fi
        fi
    done
}

#function to release lock acquired by CI BRT Pipelines
function release_ci_brt_lock(){
    echo "Proceeding to release CI BRT Lock...."
    #example of the commit msg:
    #PREVIOUS_COMMIT_MSG="Lock rias-ng-us-south-dal-dev25-etcd acquired by genctl-cicd/hypersync-integration-workspace pr run 82 - 1P_INFO: c9c9200b-4a27-481e-bcb7-0b1223900e82/d74ad2ac-c3cb-4944-991a-454e5cec3199/eu-gb"
    ONE_PL_INFO="${PREVIOUS_COMMIT_MSG#*1P_INFO: }"
    export PIPELINE_ID=$(echo "$ONE_PL_INFO" | cut -d '/' -f1)
    export PIPELINE_RUN_ID=$(echo "$ONE_PL_INFO" | cut -d '/' -f2)
    export ENDPOINT=$(echo "$ONE_PL_INFO" | cut -d '/' -f3)
    if [ -n "$PIPELINE_ID" ] && [ -n "$PIPELINE_RUN_ID" ] && [ -n "$ENDPOINT" ]; then
        echo "Pipeline ID, pipeline_run_id received"
        if is_uuid $PIPELINE_ID; then
            echo "$PIPELINE_ID is a valid UUID."
        else
            echo "$PIPELINE_ID is not a valid UUID."
            exit 1
        fi
        if is_uuid $PIPELINE_RUN_ID; then
            echo "$PIPELINE_RUN_ID is a valid UUID."
        else
            echo "$PIPELINE_RUN_ID is not a valid UUID."
            exit 1
        fi
    else
        echo "One of PIPELINE_ID, PIPELINE_RUN_ID and/or ENDPOINT is not received"
        exit 1
    fi

    BASE_URL="api.${ENDPOINT}.devops.cloud.ibm.com"
    get_pipeline_status

    if $LAST_COMMIT_OLDER_THAN_DAY; then
        release_the_lock_brt
        add_comment_to_github_issue "Found stale BRT lock, released it!"
        close_github_issue
    elif [ $PIPELINE_STATUS = "failed" ] || [ $PIPELINE_STATUS = "cancelled" ]; then
        echo "Proceeding to release the lock!"
        release_the_lock_brt
        add_comment_to_github_issue "Lock has been successfully released!"
        close_github_issue
    elif [ $PIPELINE_STATUS = "succeeded" ]; then
        echo "Checking failed dynamic scan runs"
        check_dynamic_scan_run
    else
        echo "Pipeline status is other than the valid ones, can not release lock"
        echo "Please reach out to #vpc-ci-onepipeline channel"
        add_comment_to_github_issue "Pipeline status is other than the valid ones, can not release lock, Please reach out to #vpc-ci-onepipeline channel"
        exit 1
    fi
    
}

#function to release lock acquired by CI BRT Pipelines
function release_ci_mzone_lock(){
    echo "Proceeding to release CI MZONE Lock...."
    #example of the commit msg:
    #PREVIOUS_COMMIT_MSG="Lock mzone7474 acquired by cloudnet/sdn-devops pr run 4362 - 1P_INFO: 24856cf5-3613-4b89-98a8-8babbb46eccd/a27ac74f-f1f7-4c17-94a6-6d9c9221343d/eu-gb"
    ONE_PL_INFO="${PREVIOUS_COMMIT_MSG#*1P_INFO: }"
    export PIPELINE_ID=$(echo "$ONE_PL_INFO" | cut -d '/' -f1)
    export PIPELINE_RUN_ID=$(echo "$ONE_PL_INFO" | cut -d '/' -f2)
    export ENDPOINT=$(echo "$ONE_PL_INFO" | cut -d '/' -f3)
    if [ -n "$PIPELINE_ID" ] && [ -n "$PIPELINE_RUN_ID" ] && [ -n "$ENDPOINT" ]; then
        echo "Pipeline ID, pipeline_run_id received"
        if is_uuid $PIPELINE_ID; then
            echo "$PIPELINE_ID is a valid UUID."
        else
            echo "$PIPELINE_ID is not a valid UUID."
            exit 1
        fi
        if is_uuid $PIPELINE_RUN_ID; then
            echo "$PIPELINE_RUN_ID is a valid UUID."
        else
            echo "$PIPELINE_RUN_ID is not a valid UUID."
            exit 1
        fi
    else
        echo "One of PIPELINE_ID, PIPELINE_RUN_ID and/or ENDPOINT is not received"
        exit 1
    fi

    BASE_URL="api.${ENDPOINT}.devops.cloud.ibm.com"
    get_pipeline_status

    if $LAST_COMMIT_OLDER_THAN_DAY; then
        release_the_lock_mzone
        add_comment_to_github_issue "Found stale lock, released it!"
        close_github_issue
    elif [ $PIPELINE_STATUS = "failed" ] || [ $PIPELINE_STATUS = "cancelled" ]; then
        echo "Proceeding to release the lock!"
        release_the_lock_mzone
        add_comment_to_github_issue "Lock has been successfully released!"
        close_github_issue
    else
        echo "Pipeline status is other than the valid ones, can not release lock"
        echo "Please reach out to #vpc-ci-onepipeline channel"
        add_comment_to_github_issue "Pipeline status is other than the valid ones, can not release lock, Please reach out to #vpc-ci-onepipeline channel"
        exit 1
    fi
    
}


if [[ "$ISSUE_TITLE" == *mzone* ]]; then
    git checkout master
    export FOLDER_NAME=$(echo $ISSUE_TITLE | cut -d ' ' -f6)

    PREVIOUS_COMMIT_MSG=$(git log -1 --format=%s -- $FOLDER_NAME/claimed/$LOCK_NAME)
    echo $PREVIOUS_COMMIT_MSG
    echo "here!!"
    export PREVIOUS_COMMIT_MSG=$PREVIOUS_COMMIT_MSG

    check_last_commit_age_for_master
    release_ci_mzone_lock

    popd

else
    git checkout ${LOCK_NAME}

    PREVIOUS_COMMIT_MSG=$(git log -1 --format=%s)
    echo $PREVIOUS_COMMIT_MSG
    echo "here!!"
    export PREVIOUS_COMMIT_MSG=$PREVIOUS_COMMIT_MSG

    check_last_commit_age

    if [[ "$PREVIOUS_COMMIT_MSG" =~ "MASCD" ]]; then
        release_mascd_lock
    else
        release_ci_brt_lock
    fi
    popd
fi
