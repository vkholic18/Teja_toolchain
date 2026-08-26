# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Adds a check to a specific commit
# Useful for when we want to work with a new check, but the actual task that posts it, didn't run yet
# (And we would prefer avoid running it due to different reasons)
# The check is created in success status

#
#
# Env:
#    GHE_API_TOKEN: Token for Github API
#    GHE_API_URL: Url for the GitHub API
#    REPOSITORY_NAME: Name of the repository which configuration will be checked
#    COMMIT_TO_ADD_CHECK: The SHA of the commit where the check will be added (Accepts also branch name)
#    CHECK_NAME: The name of the check that will be added (The script adds the prefix concourse-ci)
#
# Use:
#    python3 add_github_check.py


import github
import logging
import os


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
        'COMMIT_TO_ADD_CHECK',
        'CHECK_NAME'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args


def main():
    # Define logger and parse environment vars
    logger = set_up_logger()
    args = parse_env()

    # Instantiate GitHub object
    gh = github.Github(
        login_or_token=args['ghe_api_token'],
        base_url=args['ghe_api_url']
    )

    # Get the repository
    repo = gh.get_repo(args['repository_name'])

    # Get the commit
    commit = repo.get_commit(sha=args['commit_to_add_check'])

    # Create the status check
    commit.create_status(state="success", context=f"concourse-ci/{args['check_name']}")


if __name__ == "__main__":
    main()
