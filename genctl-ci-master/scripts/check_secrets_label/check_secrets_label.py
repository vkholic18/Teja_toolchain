#!/usr/bin/env python3

##
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2019-2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================


import github
import logging
import os
import json
import sys
from ci_python_tools import general_tools


def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'GITHUB_ACCESS_TOKEN',
        'GHE_API_URL',
        'REPOSITORY_NAME',
        'LABEL_TO_SEARCH',
        'PR_HEAD',
        'SECRET_DIR',
        'BASE_WORKSPACE_DIR'
    ]

    args = general_tools.parse_env(required_vars)

    return args


def get_pull_request_by_head(repo, pr_head):
    """
    Gets the PR based on the PR number
    Returns:
        PR (PyGithub object)
    """
    # Get the logger
    logger = logging.getLogger()

    # Get the PRS
    open_prs = repo.get_pulls("open")

    for pr in open_prs:
        logger.info(f"PR HEAD {pr.head}, pr_head {pr_head}")
        if pr_head in str(pr.head):
            return pr

    logger.error(f"PR with head {pr_head} does not exist or is not available/possible to merge it")
    exit(1)

def check_for_secrets(repo, pr, modified_file, logger, base_dir):
    substring = "vault.hashicorp.com/agent-inject"

    try:
        file_contents = repo.get_contents(modified_file, pr.base.ref)
        current_secret_file = str(file_contents.decoded_content.decode())
         #logger.info(f"{current_secret_file}")
        #count number of secret substrings
        secret_temp_int = current_secret_file.count(substring)
    except (github.UnknownObjectException):
        print("New razee deployment file added")
        secret_temp_int = 0
    with open(base_dir + "/" + modified_file, "r") as f:
        data = f.read()
    #count number of secret substrings
    secret_temp_pr = data.count(substring)

    if secret_temp_int < secret_temp_pr:
            logger.info(f"PR introduces a secret to this deployment")
            return True

    return False


def main():
    # Define logger and parse environment vars
    logger = general_tools.set_up_logger(logging.INFO)
    args = parse_env()

    # Instantiate GitHub object
    gh = github.Github(
        login_or_token=args['github_access_token'],
        base_url=args['ghe_api_url']
    )

    # Set directory path secrets are stored in
    secret_dir = args['secret_dir']

    # Set label to search in a variable to improve readability
    lbl_to_srch = args['label_to_search']

    #Set pr_branch to confirm the correct pr
    pr_head = args['pr_head']

    # Get the repository
    repo = gh.get_repo(args['repository_name'])

    # Get the PR and base branch
    pr = get_pull_request_by_head(repo, pr_head)
    # Only check pr if base is dev-integration
    if pr.base.ref != "dev-integration":
        logger.info(f"PRs against {pr.base.ref} not required to pass secrets check")
        sys.exit(0)

    # repo.compare returns list of files changed in the PR
    results = repo.compare(pr.base.ref, pr.head.sha)

    secret_introduced = False
    # Only check nessecary deployment files
    for file in results.files:
        if secret_dir in str(file):
            if check_for_secrets(repo, pr, file.filename, logger, args['base_workspace_dir']):
                secret_introduced = True

    if not secret_introduced:
        logger.info(f"PR with HEAD {pr_head} does not introduce secrets")
        sys.exit(0)

    # Get the PR labels
    pr_labels = [l.name.lower() for l in pr.labels]

    # Show all the lables the PR has
    logger.info(f"PR with HEAD {pr_head} has the following labels: {str(pr_labels)}")

    lbl_to_srch = lbl_to_srch.lower()
    # Check if the PR has the label and exit accordingly
    if lbl_to_srch in pr_labels:
        logger.info(f"Label {lbl_to_srch} appears in PR with HEAD {pr_head} ")
        sys.exit(0)
    else:
        logger.error(f"Label {lbl_to_srch} does not appear in PR with HEAD {pr_head} ")
        sys.exit(1)


if __name__ == "__main__":
    main()