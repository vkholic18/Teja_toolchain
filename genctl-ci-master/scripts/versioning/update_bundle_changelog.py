# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020-2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#   Checks pre-integration files for new bundle versions, generates a
#   changelog, and updates the appropriate changelog GitHub page. 
#
# Env:
#    ENV_REPO_PATH: Path to environment git repository on the filesystem
#    GH_PAGE_REPO_PATH: Path to GH page git repository on the filesystem
#    GITHUB_API_KEY: Api key to access GitHub API
#
# Use:
#    python3 update_changelog.py
#

import logging
import os
import git
import yaml

from changelog_updater import update_changelog

# Constants
RELEASE_FILE_PATH="releases.yaml"


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
        'ENV_REPO_PATH',
        'GH_PAGE_ORG_REPO',
        'GITHUB_API_KEY',
        'GITHUB_API_URL'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args


def get_releases_files(release_repo_path):
    """
    Gets the changed releases file at current and last commit
    Args:
        release_repo_path: Path to environment git repository
    Returns:
        curr_env: Releases dict at current commit
        old_env: Releases dict at last commit
    """
    logger = logging.getLogger()
    rel_repo = git.Repo(release_repo_path)
    current_sha = rel_repo.head.object.hexsha

    curr_file_sha, old_file_sha = rel_repo.git.log(
        RELEASE_FILE_PATH, n=2, pretty="format:%H").splitlines()

    if curr_file_sha == current_sha:
        file_path = os.path.join(release_repo_path, RELEASE_FILE_PATH)
        with open(file_path) as f:
            curr_env = yaml.safe_load(f)

        logger.info(f"Getting file at {old_file_sha} for comparison")
        rel_repo.git.checkout(old_file_sha)
        if os.path.exists(file_path):
            with open(file_path) as f:
                old_env = yaml.safe_load(f)
        
        else:
            logger.error(f"{RELEASE_FILE_PATH} doesn't exist at {old_file_sha}")
            exit(1)
    
    else:
        logger.error(f"{RELEASE_FILE_PATH} not changed in this commit")
        exit(1)

    if not curr_env or not old_env:
        logger.error(f"Could not parse {RELEASE_FILE_PATH}")
        exit(1)
    else:
        return curr_env, old_env


def main():
    logger = set_up_logger()
    args = parse_env()
    logger.info(f"Args{args}")
    curr_env, old_env = get_releases_files(args['env_repo_path'])

    for comp_type, components in curr_env.items():
        if comp_type != "bundles":
            logger.error(f"Unknown component type, {comp_type}")

        for comp_name, meta in components.items():
            if comp_name not in old_env[comp_type].keys() or \
                meta['tag'] != old_env[comp_type][comp_name]["tag"]:

                logger.info(f"{comp_type}/{comp_name} changed") 

                branch = meta['branch'] if 'branch' in meta.keys() else 'N/A'
                name = meta['version'].strip('v') if 'version' in meta.keys() \
                    else meta['tag']

                update_changelog(
                    args['gh_page_org_repo'],
                    comp_type,
                    comp_name,
                    name,
                    meta['tag'],
                    branch,
                    args['github_api_url'],
                    args['github_api_key'],
                )


if __name__ == "__main__":
    main()
