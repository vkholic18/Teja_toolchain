#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2020
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

## Description
## When a user deletes a hotfix config file from the hotfix repo, this script will delete the associated pipelines, if they exist

set -x

# Find only the deleted files in the latest commit, ignore the rest
function find_deleted_hotfixes_in_latest_commit {
    latest_commit=$(git rev-parse --verify HEAD)

    # If the latest_commit does not have a deleted file, quit
    delete_in_latest_commit=$(git log --diff-filter=D --summary | grep $latest_commit)
    [[ -z $delete_in_latest_commit ]] && echo "No hotfix config deleted in the latest commit" && exit 0

    hotfix_files_deleted=$(git log -1 --diff-filter=D --summary | grep "delete mode" | awk '{print $4}')
}

# Parse the deleted hotfix files and get which pipelines were created off of those configs
function find_deleted_hotfix_pipelines {
    deletion_candidates=""
    # Get the contents of the deleted hotfix config file
    git show $latest_commit | grep '^-' | awk '/'$hotfix'/{flag=1; next} /vetted_versions/{flag=0} flag' | sed 's/^-//' > $temp_dir/$hotfix

    # Replace tabs (if they exist) with spaces to be a valid yaml
    sed -i 's/\t/  /g' $temp_dir/$hotfix

    # Find the major components name and sha
    major_component_name=$(cat $temp_dir/$hotfix | yq -r .major_component.name)
    major_component_sha=$(cat $temp_dir/$hotfix | yq -r .major_component.sha)
    major_component_short_sha=$(git rev-parse --short $major_component_sha)

    # Process major component pipelines
    if [[ ! -z $(grep "sha: $major_component_sha" *.yaml) ]]; then
        echo "Pipeline for $major_component_sha is still in use. Skip delete."
    else
        echo "Deleting $major_component_name pipeline for $major_component_sha"
        deletion_candidates+="$major_component_name.*hotfix-$major_component_short_sha "
    fi

    # Find how many minor_components exist
    minor_components_count=$(cat $temp_dir/$hotfix | yq -r '.minor_components[] | length' | wc -l)

    # Loop through the minor components
    for ((i=0;i<$minor_components_count;i++)); do
        minor_component_name=$(cat $temp_dir/$hotfix | yq -r .minor_components[$i].name | awk -F "/" '{print $2}')
        minor_component_sha=$(cat $temp_dir/$hotfix | yq -r .minor_components[$i].sha)
        minor_component_short_sha=$(git rev-parse --short $minor_component_sha)

        # Process minor component pipelines
        if [[ ! -z $(grep "sha: $minor_component_sha" *.yaml) ]]; then
            echo "Pipeline for $minor_component_sha is still in use. Skip delete."
        else
            echo "Deleting $minor_component_name pipeline for $minor_component_sha"
            deletion_candidates+="$minor_component_name.*hotfix-$minor_component_short_sha "
        fi
    done
}

# Login to concourse
function fly_login() {
    wget "$CONCOURSE_SERVER_URL/api/v1/cli?arch=amd64&platform=linux" -O fly
    chmod u+x ./fly
    set +x
    ./fly login -c $CONCOURSE_SERVER_URL \
      -k \
      -t $CONCOURSE_TARGET_NAME \
      -n $CONCOURSE_TEAM_NAME \
      -u $CICD_PIPELINE_DEPLOYMENT_USERNAME \
      -p $CICD_PIPELINE_DEPLOYMENT_PASSWORD
    set -x
}

# Destroy the pipeline if it exists in concourse
function destroy_pipeline_if_exists() {
    for pipeline in $deletion_candidates
    do
        pipelines_to_be_deleted=""
        pipelines_to_be_deleted=$(./fly -t $CONCOURSE_TARGET_NAME pipelines | grep $pipeline | awk '{print $1}')
        if [[ ! -z $pipelines_to_be_deleted ]]; then
            append_pipeline_to_summary
            # There can be more than one pipeline match (e.g. for merge and PR pipelines)
            for delete in $pipelines_to_be_deleted
            do
              echo "fly destroy $delete"
              ./fly -t $CONCOURSE_TEAM_NAME destroy-pipeline --non-interactive -p $delete
            done
        else
            echo "$pipeline does not exist"
        fi
    done
}

# Create a summary of deleted pipelines
function append_pipeline_to_summary() {
    total_pipelines_deleted+="$pipelines_to_be_deleted "
}

# Print/slack the final deletion summary
function slack_summary() {
    [[ -z $total_pipelines_deleted ]] && { echo "No pipelines deleted" ; exit 0; }
    deleted_summary=$(echo $total_pipelines_deleted | sed "s/ /\n/")
    echo "Total pipelines deleted summary: $deleted_summary"
    slack_message="*Deleted hotfix pipelines on commit $latest_commit:*"
    payload_json="{\"channel\": \"#$SLACK_CHANNEL\", \"text\": \"$slack_message\", \"attachments\": [{\"color\":\"danger\", \"text\": \"$deleted_summary\"}]}"
    curl --retry 5 -X POST --data-urlencode "payload=$payload_json" $SLACK_WEBHOOK
}

# Main function
temp_dir=$(pwd)
pushd hotfix-repo
find_deleted_hotfixes_in_latest_commit
for hotfix in $hotfix_files_deleted
do
    find_deleted_hotfix_pipelines
    popd
    fly_login
    echo "Pipelines eligible for deletion: $deletion_candidates"
    destroy_pipeline_if_exists
    pushd hotfix-repo
done
slack_summary
