# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Checks if a PR has a label, if it does exits 0, otherwise 1

#
#
# Env:
#    GHE_API_TOKEN: Token for Github API
#    GHE_API_URL: Url for the GitHub API
#    REPOSITORY_NAME: Name of the repository which configuration will be checked
#    LABEL_TO_SEARCH: The label that should appear
#    PR_NUMBER: Number of the PR that needs to be merged
#
# Use:
#    python3 check_pr_has_label.py


import github
import logging
import os
import sys


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
        'LABEL_TO_SEARCH'
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
        logger.error(f"PR with number {pr_number} does not exist or is not available/possible to merge it")
        exit(1)


def main():
    # Define logger and parse environment vars
    logger = set_up_logger()
    args = parse_env()

    # Set PR number in a variable to improve readability
    pr_num = args['pr_number']

    # Set label to search in a variable to improve readability
    lbl_to_srch = args['label_to_search']

    try:
        # Instantiate GitHub object
        gh = github.Github(
            login_or_token=args['ghe_api_token'],
            base_url=args['ghe_api_url']
        )

        # Get the repository
        repo = gh.get_repo(args['repository_name'])

        # Get the PR
        pr = get_pull_request_by_number(repo, int(pr_num))

    except Exception as e:
        logger.error(f"Failed on GHE operations: {e}")
        sys.exit(100)

    # Get the PR labels
    pr_labels = [l.name.lower() for l in pr.labels]

    # Show all the lables the PR has
    logger.info(f"PR {pr_num} has the following labels: {str(pr_labels)}")

    lbl_to_srch = lbl_to_srch.lower()
    # Check if the PR has the label and exit accordingly
    if lbl_to_srch in pr_labels:
        logger.info(f"Label {lbl_to_srch} appears in PR {pr_num} ")
        sys.exit(0)
    else:
        logger.error(f"Label {lbl_to_srch} does not appear in PR {pr_num} ")
        sys.exit(1)


if __name__ == "__main__":
    main()
