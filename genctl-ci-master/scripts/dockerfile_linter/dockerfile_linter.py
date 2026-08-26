#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

"""
Description:
This script ensures compliance with ARCH004.
It scans all the Dockerfiles in a repository and identifies the non-compliant pieces.
Controlled by genctl-ci/scripts/dockerfile_linter/config.yaml
"""

import logging
import argparse
import sys
import os
import re
from pathlib import Path
import yaml
import git

# This is an internal use python package created in order to reuse code through our project
# Ensure that you 'pip installed' it before running this script
from ci_python_tools import jira_tools, general_tools

def setup_logger(output_log):
    """
    Configures logger and formatting
    """
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')

    output_file_handler = logging.FileHandler(output_log)
    stdout_handler = logging.StreamHandler(sys.stdout)
    logger.addHandler(output_file_handler)
    logger.addHandler(stdout_handler)
    output_file_handler.setFormatter(formatter)
    stdout_handler.setFormatter(formatter)

    return logger

def parse_args():
    """
    Parse the arguments passed when calling this file.
    """
    parser = argparse.ArgumentParser(description="Parser to take required and optional values for the script")
    parser.add_argument('-d', '--dir', help="Location of the repo to be scanned", required=True, dest="reponame")
    parser.add_argument('-l', '--url', help="Repo GitHub URL", required=True, dest="github_url")
    parser.add_argument('-u', '--username', help="Jira Username", required=True, dest="username")
    parser.add_argument('-p', '--password', help="Jira Password", required=True, dest="password")
    parser.add_argument('-j', '--jira-url', help="Jira URL (with port)", required=True, dest="jira_url")
    parser.add_argument('-e', '--cert-file', help="The full path to the certificate", required=True, dest="cert")

    args = parser.parse_args()
    return args

def load_config(config_file):
    """
    Reads config.yaml to determine what to scan
    """
    with open(config_file) as f:
        scan_config = yaml.safe_load(f)
    return scan_config

def find_dockerfile(scan_dir):
    """
    Find all the Dockerfiles in the repo
    """
    dockerfiles_to_scan = []
    for path in Path(scan_dir).rglob('*ockerfile*'):
        dockerfiles_to_scan.append(str(path))
    return dockerfiles_to_scan

def prune_dockerfiles_list(dockerfiles_list):
    """
    Skip checking USER directive for Dockerfiles using genctl-scratch image
    *** CURRENTLY DISABLED ***
    """
    regex_pattern = '^FROM.*genctl/genctl-scratch.*$'
    dockerfiles_list_pruned = dockerfiles_list.copy()

    for dockerfile in dockerfiles_list:
        all_from_lines = []
        with open(dockerfile, 'r') as file:
            for line in file:
                # Only scan lines starting with 'FROM'
                if line.startswith("FROM"):
                    all_from_lines.append(line)

        # If all lines match the regex, that means all the images are scratch based. Remove this Dockerfile from dockerfiles_list_pruned
        r = re.compile(regex_pattern)
        if all(r.match(line) for line in all_from_lines):
            dockerfiles_list_pruned.remove(dockerfile)

    return dockerfiles_list_pruned

def find_dockerfile_run_as_root(dockerfiles_list):
    """
    Finds the Dockerfiles which either have no defined USER (hence running as root)
    Or have the last USER as root
    """
    logger.info('-' * 80)
    logger.info("SCAN FOR ROOT USER")
    logger.info('-' * 80)

    regex_pattern = '^USER.*$'
    dockerfile_with_root = []

    for dockerfile in dockerfiles_list:
        textfile = open(dockerfile, 'r')
        filetext = textfile.read()
        textfile.close()

        # Is there a 'USER xyz' defined?
        matches = re.findall(regex_pattern, filetext, re.MULTILINE)
        # If 'USER xyz' found
        if matches:
            # Find the last user as that is used to run the docker container
            last_user = matches[-1]
            if last_user == "USER root":
                dockerfile_with_root.append(dockerfile)
        else:
            dockerfile_with_root.append(dockerfile)

    if dockerfile_with_root:
        logger.error("Dockerfiles using root: ")
        for file in dockerfile_with_root:
            logger.error(file)
    else:
        logger.info("No root user found - Scan successful")

    logger.info('-' * 80)
    return dockerfile_with_root

def find_dockerfile_with_invalid_images(dockerfiles_list, trusted_images):
    """
    Find the Dockerfiles which use the untrusted images not listed in the config.yaml
    """
    logger.info('-' * 80)
    logger.info("SCAN FOR NON-TRUSTED IMAGES")
    logger.info('-' * 80)

    dockerfile_with_invalid_image = []

    for dockerfile in dockerfiles_list:
        with open(dockerfile, 'r') as file:
            for line_num, line in enumerate(file, 1):
                # Filter out lines starting with 'FROM' which do not have the trusted images
                if line.startswith(('FROM', 'from')):
                    if not any(word in line for word in trusted_images):
                        if dockerfile not in dockerfile_with_invalid_image:
                            dockerfile_with_invalid_image.append(dockerfile)
                            logger.error(dockerfile)
                        logger.error(str(line_num) + ': ' + line.rstrip())

    if not dockerfile_with_invalid_image:
        logger.info("No non-trusted images found - Scan successful")

    logger.info('-' * 80)
    return dockerfile_with_invalid_image

def find_dockerfile_with_invalid_imports(dockerfiles_list, trusted_imports):
    """
    Find the Dockerfiles which import from any untrusted sources
    """
    logger.info('-' * 80)
    logger.info("SCAN FOR NON-TRUSTED THIRD-PARTY IMPORTS")
    logger.info('-' * 80)

    dockerfile_with_non_trusted_imports = []
    regex_https= 'https://'
    regex_imports = ['wget', 'curl', 'git clone']
    regex_go = 'go get'

    for dockerfile in dockerfiles_list:
        with open(dockerfile, 'r') as file:
            for line_num, line in enumerate(file, 1):
                # Ignore the comments and FROM statements - they are already covered in the image scan
                if not (line.lstrip().startswith('#') or line.lstrip().startswith(('FROM', 'from'))):
                    # Extract the lines with (https:// + regex_imports) or with (regex_go)
                    if (any (word in line for word in regex_imports) and (regex_https in line)) or (regex_go in line):
                        # Now extract the lines that do no have trusted sources
                        if not any(word in line for word in trusted_imports):
                            # Append and log Dockerfile name only once
                            if dockerfile not in dockerfile_with_non_trusted_imports:
                                dockerfile_with_non_trusted_imports.append(dockerfile)
                                logger.error(dockerfile)
                            logger.error(str(line_num) + ': ' + line.rstrip())

    if not dockerfile_with_non_trusted_imports:
        logger.info("No non-trusted imports found - Scan successful")

    logger.info('-' * 80)
    return dockerfile_with_non_trusted_imports

def find_potential_jira_ids(scan_dir):
    """
    Map a github repo to its associated jira project key
    """
    jira_ids = []
    jira_ids_temp = []
    repo = git.Repo(scan_dir)
    # 5 commits seem enough to find a valid JIRA id
    latest_five_commits = list(repo.iter_commits(max_count=5))

    for commit in latest_five_commits:
        commit_message = commit.message
        # Look for all pattern matches like CIGC-1234
        regex_pattern = '([A-Z][A-Z0-9]+-[0-9]+)'
        jira_ids_temp = re.findall(regex_pattern, commit_message)

        if jira_ids_temp:
            jira_ids.extend(jira_ids_temp)
    return jira_ids

def build_jira_vars(scan_config):
    """
    Prepares JIRA variables to create a JIRA issue
    """
    summary = scan_config['jira_issue_params']['summary']
    issue_type = scan_config['jira_issue_params']['issue_type']
    epic_link = scan_config['jira_issue_params']['epic_link']
    due_date = scan_config['jira_issue_params']['due_date']
    return summary, issue_type, epic_link, due_date

def main():
    """
    Main function
    """

    # Setup variables
    args = parse_args()
    scan_dir = args.reponame
    scan_repo_url = args.github_url
    jira_username = args.username
    jira_password = args.password
    jira_cert_file = args.cert
    jira_base_url = args.jira_url

    output_log = 'scan_output.log'
    # Create an empty log file to save the scan output for later use in the JIRA issue's description
    try:
        open(output_log, 'w').close()
    except OSError:
        print('Failed creating the output log file')
        sys.exit(1)

    # Set up the logger to write to a file
    global logger
    logger = setup_logger(output_log)

    # Find all the Dockerfiles to scan
    dockerfiles_list = find_dockerfile(scan_dir)
    if not dockerfiles_list:
        logger.info(f"No Dockerfile to scan in {scan_repo_url}. Aborting ...")
    else:
        # Add exception for Dockerfiles using genctl-scratch image to not scan for the USER directive --- CURRENTLY DISABLED
        # dockerfiles_list_pruned = prune_dockerfiles_list(dockerfiles_list)
        dockerfile_with_root = []
        dockerfile_with_invalid_image = []
        dockerfile_with_non_trusted_imports= []

        config_path = os.path.dirname(sys.argv[0])
        config_file = config_path + '/config.yaml'
        scan_config = load_config(config_file)

        logger.info('-' * 80)
        logger.info(f"Processing {scan_repo_url}")
        if scan_config['scan_root_user']:
            # dockerfile_with_root = find_dockerfile_run_as_root(dockerfiles_list_pruned)
            dockerfile_with_root = find_dockerfile_run_as_root(dockerfiles_list)
        if scan_config['scan_non_trusted_images']:
            dockerfile_with_invalid_image = find_dockerfile_with_invalid_images(dockerfiles_list, scan_config['trusted_sources'] )
        if scan_config['scan_non_trusted_imports']:
            dockerfile_with_non_trusted_imports = find_dockerfile_with_invalid_imports(dockerfiles_list, scan_config['trusted_sources'])

        # If any errors during scanning, fail the task
        if dockerfile_with_root or dockerfile_with_invalid_image or dockerfile_with_non_trusted_imports:
            logger.error("*{color:#DE350B}Dockerfile linting failed. Error report above{color}*")
            logger.info("More details - https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/scripts/dockerfile_linter/dockerfile_linter.md")

            with open(output_log, 'r') as f:
                description = f.read()

            if scan_config['create_jira_ticket']:
                jira_ids = find_potential_jira_ids(scan_dir)
                if jira_ids:
                    jira = jira_tools.login_jira(jira_username, jira_password, jira_base_url, jira_cert_file, retries=5)
                    valid_key = ""
                    # Check which JIRA Id is valid and use that to file a ticket
                    for jira_id in jira_ids:
                        jira_key = jira_id.split("-")[0]
                        valid_key = jira_tools.validate_key(jira, jira_key)
                        if valid_key:
                            break
                        else:
                            logger.info(f"{jira_key} is not a valid JIRA project key. Trying the next one ...")

                    if valid_key:
                        # Put together JIRA paramaters
                        summary, issue_type, epic_link, due_date = build_jira_vars(scan_config)
                        description += "\nWe apologize if this Jira item was generated for the wrong project.  Please reassign this item to the correct project. If you have any issues, please contact Zack Grossbart.\n"

                        # Create the additional fields dict
                        additional_fields = {
                            "customfield_10006": epic_link,
                            "customfield_11400": due_date
                        }
                        
                        # Create JIRA ticket
                        jira_tools.create_jira_ticket(jira, jira_key, jira_base_url, summary, description, issue_type, additional_fields)
                    else:
                        logger.info("No valid JIRA Ids found in the last 5 commits. Can't create JIRA ticket")

                else:
                    logger.error(f"No JIRA Ids found in the {scan_dir}'s commit messages. Can't create JIRA ticket")
                    sys.exit(1)
            else:
                logger.info("JIRA ticket creation disabled. Not creating JIRA tickets.")

        logger.info("Scanning completed")
        logger.info('-' * 80)

if __name__ == "__main__":
    main()
