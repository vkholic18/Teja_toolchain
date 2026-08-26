#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2020
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# This script finds all the repos which CI builds and which make it to production.
# It also finds the reviewers with "push" permissions on those repos.
# A custom script for cloudlab and genctl orgs.

set -eux

if [ $# -ne 1 ]; then
    echo 
    echo "Usage: $0 \"github oauth token\" "
    exit 1
fi

trap 'rm -f *.tmp' EXIT

export orgs=( cloudlab genctl )
export params_file=../params/pipeline-params.yaml
export date=$(date +"%Y%m%d-%H-%M-%S")
export reviewers_report=reviewers-$date.csv
export github_api="https://github.ibm.com/api/v3"

set +x
export oauth_token=$1
export header="Authorization: token ${oauth_token}"
set -x

echo "Repository,Reviewers Count,Reviewers" >>  $reviewers_report

# Get all repos in cloudlab and genctl orgs
for org in ${orgs[@]}
do
    echo Processing $org
    for page_num in 1 2 3
    do
        curl --retry 5 --silent -H "$header" "$github_api/orgs/$org/repos?per_page=100&page=$page_num" | jq -r '.[]|.html_url'>> $org.tmp
    done
    echo "Repos count in $org" $(cat $org.tmp | wc -l)
done

cat *.tmp > merged_repos.tmp
echo "Total repos to process: " $(cat merged_repos.tmp | wc -l)

# Get all repo names in params file
grep "repo-name" $params_file | awk -F ":" '{print $2}' | sed -e 's/^[[:space:]]*//' | tr -d "'" > params.tmp

# Find cloudlab and genctl repos that exist in CI params file
# Filter out repos belonging to genctl-cicd, cloudnet, pivotalservices, integration-testing, riaas
for repo in $(cat params.tmp)
do
    if grep -q "\/$repo$" merged_repos.tmp; then
        found_repo=$(grep "\/$repo$" merged_repos.tmp)
        echo $found_repo >> filtered_repos.tmp
    fi
done

# Replace space with newline, in case there are multiple repos with the same name falling on same line
sed -i 's/ /\n/g' filtered_repos.tmp

# Delete repos which are not in CI but got picked up due to their names
sed -i '/.*genctl-ci$/d' filtered_repos.tmp
sed -i '/.*integration-testing$/d'  filtered_repos.tmp
sed -i '/.*cloudlab\/orda$/d' filtered_repos.tmp
sed -i '/.*cloudlab\/regional-image$/d' filtered_repos.tmp
sed -i '/.*cloudlab\/shared-workspace$/d' filtered_repos.tmp

# Format to prepare for the next step
sort filtered_repos.tmp -o filtered_repos.tmp
sed 's/https:\/\/github.ibm.com\///g' filtered_repos.tmp > filtered_repos_formatted.tmp

# Process each repo and find its reviewers who have the "push" permission
for final_repo in $(cat filtered_repos_formatted.tmp)
do
    collaborator_list_reviewers=""
    pages_to_traverse=""

    # Find number of pages to traverse (GitHub pagination)
    pages_to_traverse=$(curl --retry 5 -H "$header" -I "$github_api/repos/$final_repo/collaborators?per_page=100" | grep "rel=" | grep -o "&page=[0-9]")
    last_page=$(echo $pages_to_traverse | cut -d"=" -f 3)

    # Find all the reviwers with "push" permissions
    for (( page_num=1; page_num<=$last_page; page_num++ ))
    do
        collaborator_list_reviewers+=$(curl --retry 5 -H "$header" -s "$github_api/repos/$final_repo/collaborators?per_page=100&page=$page_num" | jq -r '.[] | select(.permissions.push==true) | .login')
        collaborator_list_reviewers+=" "
    done
    
    # Count number of reviewers
    count_reviewers=$(echo "$collaborator_list_reviewers" | wc -w)

    # Replace spaces with commas for csv compatible format
    collaborator_list_reviewers=$(echo $collaborator_list_reviewers | sed 's/ /, /g')

    # Populate data into csv report
    echo $final_repo,$count_reviewers,\"$collaborator_list_reviewers\" >> $reviewers_report
    echo >> $reviewers_report
done

echo "Done"
