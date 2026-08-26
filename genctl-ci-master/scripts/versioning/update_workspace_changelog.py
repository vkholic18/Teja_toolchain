# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#   Updates workspace changelog with latest version from AutoSemver
#
# Env:
#    CONFIG_FILE_PATH: Path to config file provided by AutoSemver
#    GH_PAGE_REPO_PATH: Path to GH page git repository on the filesystem
#
# Use:
#    python3 update_workspace_changelog.py
#

import logging
import os
import json

from changelog_updater import update_changelog


# Constants
COMPONENT_TYPE="workspaces"


def set_up_logger():
    """
    Configures logger and formatting
    """
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)


def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'CONFIG_FILE_PATH',
        'GH_PAGE_ORG_REPO',
        'GITHUB_API_URL',
        'GITHUB_API_KEY'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args


def main():
    set_up_logger()
    args = parse_env()

    with open(args['config_file_path']) as f:
        config = json.load(f)

    update_changelog(
        args['gh_page_org_repo'],
        COMPONENT_TYPE,
        config['repo_name'],
        config['current_tag'],
        config['current_tag'],
        config['branch'],
        args['github_api_url'],
        args['github_api_key'],
        issues=config['issues']
    )



if __name__ == "__main__":
    main()
