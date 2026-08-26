# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Verifies that a PR head details are as expected
#              Useful when we want to ensure that PRs come from a specific org/repo/branch

#   If as expected, exit 0
#   If not, prints the details and exit 1
#
#
# Env:
#    GHE_API_TOKEN: Token for Github API
#    GHE_API_URL: Url for the GitHub API
#    REPOSITORY_NAME: Name of the repository in which the PR sits
#    PR_NUMBER: The number of the PR from that we should verify its origin
#    EXPECTED_PR_HEAD_ORG_AND_REPO: The org and repo that the PR is expected to come from
#    Note: EXPECTED_PR_HEAD_ORG_AND_REPO Sometimes might be the same than REPOSITORY_NAME, but not necessarily
#    EXPECTED_PR_HEAD_BRANCH: The branch that the PR is expected to come from
#    VERIFY_PR_HEAD_PARTIAL_MATCH: true or false indicating if we make a partial match or not
# Use:
#    python3 verify_pr_head.py


import github
import logging
import os
import sys
import distutils.util


def set_up_logger():
    """
    Configures logger and formatting
    Returns:
        Logger object
    """
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

    return logger


def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'GHE_API_TOKEN',
        'GHE_API_URL',
        'REPOSITORY_NAME',
        'PR_NUMBER',
        'EXPECTED_PR_HEAD_ORG_AND_REPO' ,
        'EXPECTED_PR_HEAD_BRANCH'   ,
        'VERIFY_PR_HEAD_PARTIAL_MATCH'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args


def get_pull_request_by_number(repo, pr_number):
    """
    Gets the PR based on the PR number
    Returns:
        PR (PyGithub object)
    """
    # Get the logger
    logger = logging.getLogger()

    # Get the PRS
    pr_numbers = [pr.number for pr in repo.get_pulls()]

    # If the PR exist return it, if not exit 1
    if pr_number in pr_numbers:
        return repo.get_pull(pr_number)
    else:
        logger.error(f"PR with number {pr_number} does not exist ")
        exit(1)


def main():
    # Define logger and parse environment vars
    logger = set_up_logger()
    args = parse_env()

    # Instantiate GitHub object
    gh = github.Github(
        login_or_token=args['ghe_api_token'],
        base_url=args['ghe_api_url']
    )

    # Set PR number in a variable to improve readability
    pr_num = args['pr_number']

    # Set the expected PR head ORG and REPO in a variable to improve readability
    expected_pr_head_org_and_repo = args['expected_pr_head_org_and_repo']

    # Set the expected PR expected_pr_head_branch branch in a variable to improve readability
    expected_pr_head_branch = args['expected_pr_head_branch']

    # Set the flag of partial match in a variable (As boolean) to improve readability
    verify_pr_head_partial_match = bool(distutils.util.strtobool(args['verify_pr_head_partial_match']))

    # Get the repository
    repo = gh.get_repo(args['repository_name'])

    # Get the PR
    pr = get_pull_request_by_number(repo, int(pr_num))

    # Get the actual PR ORG and REPO
    actual_pr_org_and_repo = pr.head.repo.url.split(args['ghe_api_url'])[1].split('/repos/')[1]

    # Compare
    if expected_pr_head_org_and_repo != actual_pr_org_and_repo:
        logger.error(
            f"PR was expected to come from repo {expected_pr_head_org_and_repo} but it actually comes from {actual_pr_org_and_repo}")
        sys.exit(1)

    # Get the actual PR head branch
    actual_pr_head_branch = pr.head.ref

    # Compare
    if verify_pr_head_partial_match:
        if expected_pr_head_branch not in actual_pr_head_branch:
            logger.error(f"PR was expected to come from a branch that starts with the following: {expected_pr_head_branch}; but it actually comes from branch which name is {actual_pr_head_branch}")
            sys.exit(1)
    else:
        if expected_pr_head_branch != actual_pr_head_branch:
            logger.error(f"PR was expected to come from branch {expected_pr_head_branch} but it actually comes from branch {actual_pr_head_branch}")
            sys.exit(1)



if __name__ == "__main__":
    main()
