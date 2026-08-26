#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#


import sys
import json
import re
import os
import logging
import github
from shutil import copyfile


gh_token = os.environ['GHE_ACCESS_TOKEN']
gh_api_url = os.environ['GHE_API_URL']
pr_num_str = os.environ['PR_NUM']
global_repo_name = os.environ['COMPONENT']
global_repo_org = os.environ['ORG']
changed_globals_dir = os.environ['CHANGED_GLOBALS_DIR']
build_root = os.environ['build_root']

def setup_logger():
    """
    Configures logger and formatting
    Returns:
        logger: logger object
    """

    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    return logger

def validate_json(json_str):
    """
    Validates json syntax of inputted string
    Args:
        json_str: string of json to test
    Exception:
        SystemExit with code 1 if json is invalid
    """
    logger = logging.getLogger()

    try:
        json.loads(json_str)
    except ValueError:
        logger.error("global file is not valid JSON")
        sys.exit(1)

def validate_filetype(filename):
    """
    Validates filename json type
    Args:
        filename: string of validation fail
    """
    logger = logging.getLogger()
    type_regex = r'(^([a-zA-Z0-9-_ ]{2,80})\.(json)+$)'
    # ugly patch for CIGC-2857 to skip rias-global files for Toronto region
    skip_tor_type_regex = r'(tor([0-9]+)-[a-zA-Z]+\.(json)+$)'

    if re.match(type_regex, filename) and not re.search(skip_tor_type_regex, filename):
        return True
    else:
        logger.info(f"File {filename} not a valid global file type for dry-run test ")
        return False

def main():
    logger = setup_logger()
    gh = github.Github(
        login_or_token=gh_token,
        base_url=gh_api_url
    )
    repo = gh.get_repo(global_repo_org + '/' + global_repo_name)
    pr_num = int(pr_num_str)
    logger.info(f"Working with pr: {pr_num} ")
    pr = repo.get_pull(pr_num)
    pr_files=pr.get_files()

    for pr_file in pr_files:
        if pr_file.status != 'removed':
            filename=pr_file.filename
            base_filename = os.path.basename(filename)
            if not validate_filetype(base_filename):
                logger.info(f"Skip pr file {filename} ")
                continue
            global_full_path = build_root + '/workspace/' + filename
            logger.info(f"Global full path filename {global_full_path} ")
            #validate global file json format
            with open(global_full_path) as f:
                global_str = f.read()
            validate_json(global_str)
            logger.info(f"Valid json format for {filename} global file ")

            logger.info(f"Base global filename {base_filename} ")
            copyfile(global_full_path,
                build_root + '/' + changed_globals_dir + '/' + base_filename)

        else:
            logger.info(f"{pr_file.filename} was removed; skipping validation")

if __name__ == "__main__":
    main()