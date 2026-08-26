#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================

# The following environment variables need to be set before executing the script:

# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO, PATH_TO_RESOURCELOCK_REPO
# JIRA_URL
# LOCK_SOURCE, LOCK_DESTINATION

# In addition the following environment variables are optional, if they are not set, they take default value
LOCK_POOL=${LOCK_POOL:-"release-deploy-lock"}
LOGFILE=${LOGFILE:-"failed_mzones.log"}
ALERTS_SLACK_CHANNEL=${ALERTS_SLACK_CHANNEL:-"genctl-cicd-cluster-alerts"}
SKIP_CI=${SKIP_CI:-""}
LOCK_MZONE_FAILED=${LOCK_MZONE_FAILED:-""}
LOCK_MZONE_FAILURE_THRESHOLD=${LOCK_MZONE_FAILURE_THRESHOLD:-""}


function slack_failure_summary() {
    echo "$envName $mzoneName failed more than $LOCK_MZONE_FAILURE_THRESHOLD times"
    echo "$final_slack_message"
    payload_json="{\"channel\": \"$ALERTS_SLACK_CHANNEL\", \"text\": \"$slack_title\", \"attachments\": [{\"color\":\"danger\", \"text\": \"$final_slack_message\"}]}"
    curl --retry 5 --silent --output /dev/null --show-error --fail -X POST --data-urlencode "payload=$payload_json" $ALERTS_SLACK_WEBHOOK
}

envName=
metadata=

# Few required sources
source ${PATH_TO_GENCTL_CI}/scripts/rebase_and_retrieve_metadata.sh
source ${PATH_TO_GENCTL_CI}/scripts/retry.sh
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh


RELEASE_LOCK_DIRECTORY="${PATH_TO_RESOURCELOCK_REPO}/$LOCK_POOL"
initGit
getPipelineDetails
pushd $RELEASE_LOCK_DIRECTORY
rebase
popd
getMzone

# Check mzone failures only for release-deploy-lock
if [[ $LOCK_POOL == "release-deploy-lock" ]]; then
    # Check if the workspace-repo exists (Since it is optional input)
    if [[ -d "${PATH_TO_WORKSPACE_REPO}" ]]; then
        if repo_is_from_prod_org ${PATH_TO_WORKSPACE_REPO}
        then
            verify_number_of_failures=true        
        else
            verify_number_of_failures=false
        fi
    else
        if [[ ${IS_ONE_PIPELINE_RUN} == "false" ]]
        then
            # If no workspace then use concourse URL
            if [[ "$serverName" =~ concourse.*\.genctlci\.com ]]; then
                verify_number_of_failures=true 
            else
                verify_number_of_failures=false
            fi
        else
            verify_number_of_failures=false
        fi
    fi

    if [ "$verify_number_of_failures" = "true" ]; then
        echo "Will verify the number of failures for env $envName"
        mzone_failure_count=$(grep $envName $RELEASE_LOCK_DIRECTORY/$LOCK_MZONE_FAILED/failed_mzones.log | wc -l)
        echo "For env $envName there are $mzone_failure_count failures. The threshold is $LOCK_MZONE_FAILURE_THRESHOLD"
        if [[ $mzone_failure_count -gt $LOCK_MZONE_FAILURE_THRESHOLD ]]; then
            LOCK_DESTINATION=offline

            if [[ ${IS_ONE_PIPELINE_RUN} == "false" ]]
            then

                # Setting +e since we don't want to stop if there is any issue with slack notification/filing jira
                set +e
                # Create strings for Slack and Jira (Title is the same, and message gets added the JIRA after it is created)
                jira_title="$envName $mzoneName failed more than $LOCK_MZONE_FAILURE_THRESHOLD times"
                slack_title=":offline_: *${jira_title}*"
                slack_message=$(grep $envName $RELEASE_LOCK_DIRECTORY/$LOCK_MZONE_FAILED/failed_mzones.log | awk '{print $3}')
                
                ## File a JIRA ticket ##
                
                # Install requirements
                retry python3 -m pip install -q ${PATH_TO_GENCTL_CI}/tools/ci_python_tools
                
                # Define some environment variables
                export JIRA_CERT_FILE="${PATH_TO_GENCTL_CI}/certificates/jira.crt"
                export PROJECT_KEY="CIGC"
                export SUMMARY="${jira_title}"
                export DESCRIPTION="${slack_message}"
                export ISSUE_TYPE="Task"
                export ADDITIONAL_FIELDS_FILE="${PATH_TO_GENCTL_CI}/tools/mzone_offline_jira_additional_fields.json"
                
                # Run script that files the ticket
                python3 ${PATH_TO_GENCTL_CI}/scripts/create_jira_ticket/create_jira_ticket.py
                # Get the link to the recently created JIRA ticket
                link_to_jira_ticket=$(cat created_jira_ticket.txt)
                
                final_slack_message="A JIRA ticket was filed due to taking out mzone, see: ${link_to_jira_ticket}.            
                This is a list of the builds that caused to reach the threshold of failures: ${slack_message}"
                slack_failure_summary
                # Set back -e
                set -e
            else
                echo "Create JIRA for too many failures functionality is not implemented in OnePipeline"
            fi
            pushd $RELEASE_LOCK_DIRECTORY/$LOCK_MZONE_FAILED
            sed -i "/$envName $mzoneName/d" $LOGFILE
            git add $LOGFILE
            commitAndPush "$mzoneName moved to $LOCK_DESTINATION on $pipelineName/jobs/$jobName/builds/$buildName"
            popd
          fi
    else
        echo "Won't verify how many failures were or take mzone out in case of too many"
    fi
fi

if [[ ! -z $envName ]]
then
    pushd $RELEASE_LOCK_DIRECTORY
    git mv $LOCK_SOURCE/$envName $LOCK_DESTINATION/$envName
    commitAndPush "$pipelineName/$jobName build $buildName moving $envName to $LOCK_DESTINATION $SKIP_CI"
    popd
fi