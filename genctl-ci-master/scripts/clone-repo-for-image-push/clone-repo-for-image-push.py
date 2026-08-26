#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

"""
Description:
Read the file changed in the latest commit to https://github.ibm.com/genctl-cicd/one-pipeline-marina-reg-prod-sync.
Clone and prepare the workspace defined in the changed file.
"""

import os
import logging
import yaml
import re
import json
import git
from ci_python_tools import general_tools

# Globals
GITHUB_SSH_URL = 'git@github.ibm.com'
SYNC_REPO = 'genctl-cicd/one-pipeline-marina-reg-prod-sync'
PIPELINE_TYPE_FILE = 'image_sync_pipeline_type.txt'


def retrieve_updated_file(trigger_commit, sync_repo_path):
    """
    Get the file that changed in the latest commit
    """
    try:
        sync_repo = git.Repo(sync_repo_path)
        changed_files = list(sync_repo.commit(trigger_commit).stats.files.keys())

        num_files = len(changed_files)
        if num_files > 1:
            logger.error(f"Multiple files ({num_files}) modified in one commit. Only one allowed.")
            exit(1)

        if num_files < 1 or not changed_files[0].endswith('.json'):
            logger.error(f"File changed must be a json.")
            exit(1)

    except Exception as exception:
        logger.error(f'Exception retrieving the file changed in the latest commit')
        logger.error(exception)
        exit(1)

    # Return the file that was changed/added in the commit
    changed_file_path = f"{sync_repo_path}/{changed_files[0]}"
    logger.info(f'{changed_file_path} changed/added in this commit')
    return changed_file_path


def clone_repo(file_changed, clone_to, current_dir):
    """
    Clone the repo defined in the file based on the other parameters in the file
    """
    try:
        with open(file_changed, 'r') as f:
            data = json.load(f)

        repo_org = data['repo_org']
        repo_name = data['repo_name']
        repo_sha = data['sha']
        pipeline_type = data['pipeline_type']

        ssh_url = f'{GITHUB_SSH_URL}:{repo_org}/{repo_name}'

        logger.info(f'Cloning {repo_org}/{repo_name}...')
        repo = git.Repo.clone_from(ssh_url, clone_to, no_checkout=True)

        logger.info(f'Checking out commit sha {repo_sha}')
        repo.git.checkout(repo_sha)

        logger.info(f'Clone finished to {clone_to}')

        logger.info(f'Write pipeline_type to {PIPELINE_TYPE_FILE}')
        with open(os.path.join(clone_to, PIPELINE_TYPE_FILE), "w") as fp:
            fp.write(pipeline_type)

    except Exception as exception:
        logger.error(f'Exception cloning the workspace')
        logger.error(exception)
        exit(1)


def main():
    """
    Main function
    """
    global logger
    logger = general_tools.set_up_logger(logging.INFO)

    # Define mandatory args
    mandatory_args = [
        'TRIGGER_COMMIT',
        'WORKSPACE_REPO_PATH',
        'SYNC_REPO_PATH'
    ]

    # Parse environment variables
    args = general_tools.parse_env(mandatory_args)
    trigger_commit = args['trigger_commit']
    sync_repo_path = args['sync_repo_path']
    clone_to = args['workspace_repo_path']

    # Retrieve the file changed in the latest commit
    file_changed = retrieve_updated_file(trigger_commit, sync_repo_path)

    # Clone the repo to 'workspace-repo' which will be passed as an output to the 'copy-images' task
    current_dir = os.getcwd()
    clone_repo(file_changed, clone_to, current_dir)


if __name__ == "__main__":
    main()
