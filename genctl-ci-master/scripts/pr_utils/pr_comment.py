# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: GHE PR common functions

#
#
# Env:
#    GHE_API_TOKEN: Token for Github API
#    GHE_API_URL: Url for the GitHub API
#    WORKSPACE_REPO_NAME: Name of the repository to pull the PR data from
#    WORKSPACE_REPO_ORG: Name of the origanization to pull the PR data from
#    MESSAGE: The message to post on PR
#    PR_ID: Number of the PR that needs to be merged
#

#
# Args:
#    MESSAGE: The message to post on PR
#

# Use:
#    python3 pr_comment.py -msg "${MESSAGE}"

# Post a message as a comment on a GitHub PR

###############################################################################
# I M P O R T S
###############################################################################

import argparse
import logging
import os
import sys

import github

###############################################################################
# F U N C T I O N S
###############################################################################
def parse_args():
    """
    Parse the arguments passed when calling this file
    """
    parser = argparse.ArgumentParser(
        description="Parser to take required and optional values for the script")
    parser.add_argument('-msg', '--message', help="Message to post on PR",
                        required=True, dest="message")
    args = parser.parse_args()
    return args

def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = {}

    required_vars = [
        'GHE_API_TOKEN',
        'GHE_API_URL',
        'WORKSPACE_REPO_NAME',
        'WORKSPACE_REPO_ORG',
        'PR_ID'
    ]

    for var in required_vars:
        if var in os.environ and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            sys.exit(1)

    return args


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


###############################################################################
# M A I N
###############################################################################


def main():
    """
    Main function
    """
    set_up_logger()
    args = parse_args()
    env_args = parse_env()

    # set up ghe
    gh_obj = github.Github(
        login_or_token=env_args['ghe_api_token'],
        base_url=env_args['ghe_api_url']
    )
    gh_ws = f"{env_args['workspace_repo_org']}/{env_args['workspace_repo_name']}"
    gh_repo = gh_obj.get_repo(gh_ws)
    gh_pr = gh_repo.get_pull(int(env_args['pr_id']))
    gh_pr.create_issue_comment(str(args.message))


if __name__ == "__main__":
    main()
