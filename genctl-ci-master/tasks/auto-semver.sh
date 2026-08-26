#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script creates a version tag after merge the PRs to master/dev-integration branches.

# The following environment variables need to be set before executing the script

# PATH_TO_GENCTL_CI, WORKSPACE_PATH 
# DEFAULT_BRANCH
# GITHUB_URL, GIT_PRIVATE_KEY, GITHUB_API_KEY, GITHUB_API_URL,
# VAULT_GIT_CONFIG_USER_EMAIL, VAULT_GIT_CONFIG_USERNAME

# The following environment variables can be set before executing the script, if not they will use default
# CHANGELOGGEN_VERSION, HOTFIX_BRANCH, HOTFIX_VERSION
# GO111MODULE, GOPRIVATE
# OVERRIDE_ORG_RESTRICTION, ENABLED_ORGS, SKIP_RELEASE, CHANGELOG_CONFIG_PATH, CREATE_TAG_MODE
# =============================================================================================
set -eu

# Set default values

export SKIP_AUTO_SEMVER=${SKIP_AUTO_SEMVER:-"false"} # By default run
export CHANGELOGGEN_VERSION=${CHANGELOGGEN_VERSION:-""}
export HOTFIX_BRANCH=${HOTFIX_BRANCH:-""}
export HOTFIX_VERSION=${HOTFIX_VERSION:-""}
export GO111MODULE=${GO111MODULE:-"on"}
export GOPRIVATE=${GOPRIVATE:-"github.ibm.com/*"}
export OVERRIDE_ORG_RESTRICTION=${OVERRIDE_ORG_RESTRICTION:-"false"}
export SKIP_RELEASE=${SKIP_RELEASE:-"false"}
export CHANGELOG_CONFIG_PATH=${CHANGELOG_CONFIG_PATH:-"changelog-config/config.json"}
export CREATE_TAG_MODE=${CREATE_TAG_MODE:-"semver"}

export CHECK_IF_NEED_TO_RUN_SEMVER=${CHECK_IF_NEED_TO_RUN_SEMVER:-"false"}

source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

source ${PATH_TO_GENCTL_CI}/scripts/retry.sh

source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

START=$(date +%s)
echo "CREATE_TAG_MODE is ${CREATE_TAG_MODE}"

# Skip if needed
generic_skip $SKIP_AUTO_SEMVER

# Check if the output directory exists (For example was created by concourse). If it does not exist, create it
OUTPUT_DIR=${CHANGELOG_CONFIG_PATH%/*}

if [[ -d ${OUTPUT_DIR} ]]
then
    echo "Output dir exists"
else
    echo "Output dir does not exist, need to create..."
    mkdir -p ${OUTPUT_DIR}
fi

# By default, we want to avoid running Auto-Semver in repos that are not production (For example: forks)
# For this, we check if the repo is from a production organization or not
# If the repo is NOT from a production organization, we will run Auto-Semver ONLY if an explicit flag is set
# (We enable this because sometimes is needed for development/testing purposes)

if ! repo_is_from_prod_org ${WORKSPACE_PATH}
then
    if [ "$OVERRIDE_ORG_RESTRICTION" == "true" ]; then
        echo "Repo is not a production repo, however, OVERRIDE_ORG_RESTRICTION is true, so proceeding to run Auto-Semver..."
    else
        echo "By default, Auto-Semver is not enabled for organizations that are not 'production'"
        echo "It might be the case that your repository is a fork..."
        echo "If you want to run Auto-Semver anyway, set OVERRIDE_ORG_RESTRICTION flag to true" 
        exit 0
    fi
fi

eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan $GITHUB_URL >> ~/.ssh/known_hosts

git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

if [[ ! -z "$HOTFIX_BRANCH" ]]; then

    # HOTFIX_VERSION will be empty for the non-razee pipelines
    if [[ -z "$HOTFIX_VERSION" ]]; then
        echo "This is a non-razee pipeline. Attempting to find the base tag for $HOTFIX_BRANCH ..."

        # Find the type of the pipeline -- Release-bundle or regular hotfix?
        # Check if its a release-bundle pipeline for the hotfix
        # Example 'HOTFIX_BRANCH: stable-<commit>'. Extract '<commit>' to get the genctl-release base commit
        parent_commit=${HOTFIX_BRANCH##*-}
        pushd ${WORKSPACE_PATH}
        git fetch --all --tags
        # Do not fail if the commit doesn't have the tag
        set +e
        parent_tag=$(git describe --all --exact-match $parent_commit)
        set -e

        # Empty 'parent_tag' = Either its a release-bundle with no tag for the parent commit or its a regular pipeline
        if [[ -z "${parent_tag}" ]]; then
            # To pull down master branch
            git config --add remote.origin.fetch +refs/heads/*:refs/remotes/origin/*
            git fetch --all
            parent_commit=$(git merge-base ${HOTFIX_BRANCH} origin/${DEFAULT_BRANCH})
            # Do not fail if the commit doesn't have the tag
            set +e
            parent_tag=$(git describe --all --exact-match $parent_commit)
            set -e
        fi

        if [[ ! -z "$parent_tag" ]]; then
            # If the commit has an associated tag, pass it further
            # 'parent_tag' will of the format `tags/<tag-number>`
            substring='tags/'
            if [[ "$parent_tag" == *"$substring"* ]]; then
                echo "Parent commit ${parent_commit} is tagged with ${parent_tag}"
                export HOTFIX_VERSION=${parent_tag##*/}
            else
                echo "No tag associated with ${parent_commit}. Base tag needed for semver. Exiting ..."
                exit 0
            fi
        else
            echo "Hotfixes require base tag version which doesn't exist. Exiting ..."
            exit 0
        fi
        echo "Hotfix branch: ${HOTFIX_BRANCH}"
        echo "Hotfix version: ${HOTFIX_VERSION}"
        echo "Forked commit on the stable branch: ${parent_commit}"
        echo "Tag on forked commit: ${parent_tag}"
        popd
    fi
fi


if [[ ! -z "$CHANGELOGGEN_VERSION" ]]; then
    echo "machine github.ibm.com login ${VAULT_GIT_CONFIG_USERNAME} password ${GITHUB_API_KEY}" > ~/.netrc
    go install github.ibm.com/genctl-cicd/changeloggen/cmd/changeloggen@${CHANGELOGGEN_VERSION}
fi

if [[ "${CHECK_IF_NEED_TO_RUN_SEMVER}" == "true" ]]
then
    echo "Will proceed to check if we need to run auto-semver at all..."
    
    pushd "${PATH_TO_WORKSPACE_REPO}"

    current_branch=$(git rev-parse --abbrev-ref HEAD)
    current_sha=$(git rev-parse HEAD)
    echo "Currently on branch: ${current_branch}; with SHA ${current_sha}"
    existing_tag=$(git tag --points-at HEAD)

    popd

    if [ ! -z "${existing_tag}" ]
    then
        echo "Found existing tag ${existing_tag}"
        
        gh auth login --hostname github.ibm.com --with-token <<< ${GITHUB_API_KEY}

        set +e
        gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        /repos/${PIPELINE_REPO_ORG}/${PIPELINE_REPO_NAME}/releases/tags/${existing_tag}
        release_exists=$?
        set -e

        if [[ "${release_exists}" -eq 0 ]]
        then
            echo "Both tag and release exists; no need to run autosemver..."
            exit 0
        else
            echo "Could not find release for tag ${existing_tag}"
        fi
    else
        echo "Could not find tag on branch: ${current_branch}; with SHA ${current_sha}"
    fi
fi


retry python3 -m pip install -q -r ${PATH_TO_GENCTL_CI}/scripts/versioning/requirements.txt
python3 ${PATH_TO_GENCTL_CI}/scripts/versioning/auto_semver.py

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Auto SemVersion took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"