# =============================================================================================
# IBM Confidential
# (c) Copyright IBM Corp. 2021, 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
# Checks if deployment file labels contains a certain required label
#
# Environment:π
#   WORKSPACE_PATH: Relative path to the workspace on disk
#
# Use:
#    python3 validate_deployment_labels.py
#

import git
import json
import logging
import os
import re
import sys
from git_meta_label_injector import find_deployment_files, INDENT_SIZE, TMPL_PREFIX

kind_pattern = re.compile(r'^( +)?kind\: (?:Deployment|DaemonSet|StatefulSet|ReplicaSet)')
not_kind_pattern = re.compile(r'^( +)kind\: (?!Deployment|DaemonSet|StatefulSet|ReplicaSet)')
meta_pattern = re.compile(r'^( +)metadata\:')


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


def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        "WORKSPACE_PATH"
    ]

    missing_vars = list()
    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            missing_vars.append(var)

    if missing_vars:
        vars_str = ', '.join(missing_vars)
        logger.error(f"Missing required env variable(s), {vars_str}")
        exit(1)

    return args


def validate_deployment_labels(file_content, labels_to_validate):
    file_lines = file_content.split('\n')

    in_kind = False
    in_meta = False
    for index, line in enumerate(file_lines):
        # Detect if within desired kind
        if kind_pattern.match(line):
            in_kind = True
            existing_labels = list()
        elif not_kind_pattern.match(line):
            in_kind = False

        # Detect if within metadata section
        if in_kind and meta_pattern.match(line):
            in_meta = True

            # Determine size of indent
            meta_indent = len(line) - len(line.lstrip())
            meta_item_indent = meta_indent + INDENT_SIZE # Default

            for i in range (index + 1, len(file_lines)):
                meta_item = file_lines[i]

                if not meta_item.strip().startswith(TMPL_PREFIX):
                    curr_indent = len(meta_item) - len(meta_item.lstrip())
                    if curr_indent > meta_indent:
                        meta_item_indent = curr_indent
                        break
                    else:
                        break

            # Iterate through entire metadata section and search for labels
            for i in range(index + 1, len(file_lines)):
                if 'labels' in file_lines[i]:

                    # Iterate through labels to find existing ones
                    for j in range(i + 1, len(file_lines)):

                        if not file_lines[j].strip().startswith(TMPL_PREFIX):
                            curr_indent = len(file_lines[j]) -\
                                len(file_lines[j].lstrip())

                            if curr_indent > meta_item_indent:
                                existing_labels.append(
                                    file_lines[j].split(':')[0].strip())
                            else:
                                break
                    break

        elif not line.strip().startswith(TMPL_PREFIX) and in_meta and \
            not line.startswith(meta_item_indent * ' '):
            in_meta = False

        if in_meta and 'labels:' in line:
            for key in labels_to_validate:
                if key not in existing_labels:
                    return False

    return True

def main():
    logger = setup_logger()
    args = parse_env()
    repo_path = args['workspace_path']

    DEPLOYMENT_CONFIG_PATH = os.getenv('COS_UPLOAD_CONTENT_ROOT') or ""

    deploy_dir = os.path.join(repo_path, DEPLOYMENT_CONFIG_PATH)
    if not os.path.exists(deploy_dir):
        logger.warning(
            f"{DEPLOYMENT_CONFIG_PATH} does not exist in workspace; skipping")
        exit(0)
        
    deploy_files = find_deployment_files(deploy_dir, kind_pattern=kind_pattern)
    failed_deployments = list()
    for deploy_file in deploy_files:
        logger.info(f"Validating workspace_tag deployment label for {deploy_file}")
        with open(deploy_file, 'r') as f:
            deployment = f.read()

        if validate_deployment_labels(deployment, labels_to_validate=["workspace_tag"]) == False:
            failed_deployments.append(deploy_file)
            
    if failed_deployments:
        failed_msg = "\n".join(failed_deployments)
        logger.error("Failed files report:")
        logger.error(f"Deployment file missing required label workspace_tag:\n{failed_msg}")
        exit(1)
    else:
        logger.info("All checks have passed.")    

if __name__ == '__main__':
    main()
