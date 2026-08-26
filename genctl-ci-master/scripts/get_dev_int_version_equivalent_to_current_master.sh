#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# This script implements a function that gets the dev-integration version "equivalent" to the current master
function get_dev_int_version_equivalent_to_current_master(){
    # This function is used to get the "equivalent" dev-integration version of the current master version
    # The reason for why we need this function and we can't just get the HEAD of dev-integration is scenarios like the following:
    
    # A PR was a merged to master (This means it passed BRTs/is "vetted")
    # A new PR to dev-integration is merged to dev-integration, no PR to master is open yet
    # At this point we have on dev-integration content that didn't run/pass BRTs yet, so we can't take this version
    # In the other hand, the "previous" dev-integration version that we already merged to master is what we want to get

    # Pre-requisites: This function assumes that the proper git SSH config is in place

    # Expected parameters:

    # $1 --> The path to the repo
    # $2 --> The name of the "master" branch (Usually master/main)

    # Outcome:

    # After succesfully running this function, we will have 4 environment variables:
    # RESULT_MASTER_SHA --> SHA of master version
    # RESULT_MASTER_SEMVER --> SemVer of master version (If present)
    # RESULT_DEV_INT_SHA --> SHA of the dev-integration version that is "equivalent" to the master one
    # RESULT_DEV_INT_SEMVER --> SemVer of the dev-integration version that is "equivalent" to the master one (If present)
    
    PATH_TO_REPO=$1
    REPO_MAIN_BRANCH=$2

    echo -e "${BGreen}Start process of getting equivalence between master and dev-integration...${NC}"

    # Move to the repo 
    pushd "${PATH_TO_REPO}"

    # Save the current branch
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

    # Checkout to the master/main branch
    git checkout "${REPO_MAIN_BRANCH}"

    # Get the tags
    git fetch --tags

    # Get the SHA and SemVer of master
    export RESULT_MASTER_SHA=$(git rev-parse HEAD)
    export RESULT_MASTER_SEMVER=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true

    # Now we should find the dev-integration version that is equivalent

    # In master branch, for each merge commit:
    # The first parent is the previous merge commit
    # The second parent is the HEAD of the dev-integration branch at the moment the merge was done --> This is what we need
    export RESULT_DEV_INT_SHA=$(git rev-parse HEAD^2)

    # Just to be sure we do a few validations
    # First we check the result is not the string HEAD^2 (This is what happens when the commit does not have two parents ex: it was squashed)
    if [ ${RESULT_DEV_INT_SHA} != "HEAD^2" ]
    then
        # Then we verify the result is a SHA that is present in dev-integration branch
        VERIFY_RESULT_DEV_INT_SHA_IS_IN_DEV_INT=$(git checkout dev-integration > /dev/null 2>&1 && git log | grep ${RESULT_DEV_INT_SHA}; git checkout - > /dev/null 2>&1)

        if [ ! -z "${VERIFY_RESULT_DEV_INT_SHA_IS_IN_DEV_INT}" ]
        then
            # Once we have the SHA, we use that to get the tag
            export RESULT_DEV_INT_SEMVER=$(git checkout ${RESULT_DEV_INT_SHA} > /dev/null 2>&1 && git describe --tags --exact-match --abbrev=0 2> /dev/null && git checkout - > /dev/null 2>&1)

            echo "Version from dev-integration with SHA ${RESULT_DEV_INT_SHA} and SemVer ${RESULT_DEV_INT_SEMVER} is equivalent to version with SHA ${RESULT_MASTER_SHA} and SemVer ${RESULT_MASTER_SEMVER} from ${REPO_MAIN_BRANCH}" 

            # Come back to previous branch
            git checkout "${CURRENT_BRANCH}"

            # Come back to previous dir
            popd

            echo -e "${BGreen}Finished process of getting equivalence between master and dev-integration...${NC}"
        else
            echo "SHA ${RESULT_DEV_INT_SHA} is not on dev-integration branch"
            
            # Come back to previous branch
            git checkout "${CURRENT_BRANCH}"

            # Come back to previous dir
            popd
            
            echo -e "${BRed}Something went wrong when getting equivalence between master and dev-integration...${NC}"

            exit 1

            
        fi
    else
        echo "Last commit to branch ${MASTER_BRANCH_NAME} is not a merge commit"

        # Come back to previous branch
        git checkout "${CURRENT_BRANCH}"

        # Come back to previous dir
        popd

        echo -e "${BRed}Something went wrong when getting equivalence between master and dev-integration...${NC}"

        exit 1
    fi
}

get_pr_merge_commit_sha() {    
    #   - Navigates (pushd) into the given Git repository path
    #   - Fetches the merge commit SHA for a given PR number
    #   - Exports the SHA as PR_MERGE_COMMIT_SHA environment variable
    #   - Returns back to the original directory        
    #
    # Usage:
    #   get_pr_merge_commit_sha <path_to_repo> <pr_number>
    #
	local PATH_TO_REPO="$1"
	local PULL_REQUEST_NUMBER="$2"

	# Validate input arguments
	if [[ -z "$PATH_TO_REPO" || -z "$PULL_REQUEST_NUMBER" ]]; then
		echo "Usage: get_pr_merge_commit_sha <path_to_repo> <pr_number>"
		return 1
	fi	

	# Move into repository directory (store current dir in stack)
	pushd "$PATH_TO_REPO"

	# Fetch merge commit SHA using GitHub CLI
	# --json mergeCommit → fetch merge commit object
	# --jq .mergeCommit.oid → extract only the SHA
	local MERGE_SHA
	# gh Login
	gh auth login --hostname github.ibm.com --with-token <<< ${GH_TOKEN}	
	
	MERGE_SHA=$(gh pr view "$PULL_REQUEST_NUMBER" \
		--json mergeCommit \
		--jq .mergeCommit.oid 2>/dev/null)

	# Validate that we received a valid SHA
	if [[ -z "$MERGE_SHA" || "$MERGE_SHA" == "null" ]]; then
		echo "Error: Unable to fetch merge commit SHA for PR #$PULL_REQUEST_NUMBER"
		popd
		return 1
	fi

	# Export as environment variable for downstream usage
	export PR_MERGE_COMMIT_SHA="$MERGE_SHA"

	# Return to original directory
	popd

	echo "PR_MERGE_COMMIT_SHA exported: $PR_MERGE_COMMIT_SHA"
}