#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script verifies that the last commit of the default branch has a tag

# This is intended to be used in razee flow, right at the beginning of the merge to dev-integration pipeline
# with the goal of detecting situations in which the previous merge to master didn't run or properly created a version

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO, PIPELINE_RUN_BRANCH
# DEFAULT_BRANCH

set -eu

echo "Will temporarily switch to branch ${DEFAULT_BRANCH} to verify if there is tag (SemVer) for the latest commit of that branch"
echo "After this, we will come back to the original branch ${PIPELINE_RUN_BRANCH}"

# Move to workspace
pushd "${PATH_TO_WORKSPACE_REPO}"

# Checkout to default branch
git checkout "${DEFAULT_BRANCH}"

# Get SHA of HEAD in the default branch
DEFAULT_BRANCH_SHA=$(git rev-parse HEAD)

# Print some info
echo "Currently on branch: ${DEFAULT_BRANCH}, SHA is ${DEFAULT_BRANCH_SHA}"

# Get SemVer
DEFAULT_BRANCH_SEMVER=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true

# If we don't have a SemVer it could be that this is a new pipeline and the merge to master never ran yet
# To verify this, we check if there is any tag
if [[ -z "${DEFAULT_BRANCH_SEMVER}" ]]
then
    # We assume that this is a new pipeline
    NEW_PIPELINE="true"

    # Check if there is any tag
    IS_THERE_ANY_TAG=$(git tag --sort='creatordate' --merged)

    # If there is a tag then we assume this is NOT a new pipeline
    if [[ "${IS_THERE_ANY_TAG}" ]]
    then
        NEW_PIPELINE="false"
    fi
fi

# Come back to original branch
git checkout "${PIPELINE_RUN_BRANCH}"

# Come back directory
popd

# Check if we have SemVer, if not exit with error
if [[ ! -z "${DEFAULT_BRANCH_SEMVER}" ]]
then
    echo "Found SemVer ${DEFAULT_BRANCH_SEMVER} for branch ${DEFAULT_BRANCH} - SHA ${DEFAULT_BRANCH_SHA}"

    if [[ ${DEFAULT_BRANCH_SEMVER} != *"dev"* ]];
    then
        echo "Everything seems OK with SemVer for branch ${DEFAULT_BRANCH}" 
    else
        echo "SemVer ${DEFAULT_BRANCH_SEMVER} contains dev, this is not OK"
        echo "Will exit with error..."
        exit 1
    fi
else
    echo "No SemVer"
    if [[ "${NEW_PIPELINE}" == "true" ]] 
    then
        echo "There was no SemVer on branch ${DEFAULT_BRANCH}; however seems there were no tags at all so we assume this is a new pipeline..."
    else
        echo "Seems that last merge to master pipeline didn't run/did not create properly a tag"
        echo "Please fix the status of the master branch"
        exit 1
    fi
fi
