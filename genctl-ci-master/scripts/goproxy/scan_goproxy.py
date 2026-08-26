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
It scans all the developer repositories and flags the ones which do not use GOPROXY.
Controlled by genctl-ci/scripts/goproxy/config.yaml
"""
import logging
import argparse
import sys
import os
import re
import yaml
import git

# This is an internal use python package created in order to reuse code through our project
# Ensure that you 'pip installed' it before running this script
from ci_python_tools import jira_tools, general_tools

def setup_logger():
    """
    Configures logger and formatting
    """
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    stdout_handler = logging.StreamHandler(sys.stdout)
    logger.addHandler(stdout_handler)
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

    global logger
    logger = setup_logger()

    # Setup variables
    args = parse_args()
    scan_dir = args.reponame
    scan_repo_url = args.github_url
    jira_username = args.username
    jira_password = args.password
    jira_cert_file = args.cert
    jira_base_url = args.jira_url
    goproxy_doc = 'https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/docs/goproxy.md'

    config_path = os.path.dirname(sys.argv[0])
    config_file = config_path + '/config.yaml'
    scan_config = load_config(config_file)

    if scan_config['create_jira_ticket']:
        logger.info('-' * 80)
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
                description = (f"GOPROXY from TaaS Artifactory is required in {scan_repo_url}.\n"
                                "Part of the Service Framework ARCH014 requirement is to use the GOPROXY from TaaS Artifatory. This also requires moving to Go Modules for all projects.\n"
                                f"Instructions can be found in {goproxy_doc}.\n"
                                "We apologize if this Jira item was generated for the wrong project. Please reassign this item to the correct project.\n"
                                "If have any further questions please contact Zack Grossbart.")

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
            logger.error(f"No JIRA Ids found in the {scan_dir}'s commit message. Can't create JIRA ticket")
            sys.exit(1)
        logger.info('-' * 80)
    else:
        logger.info("JIRA ticket creation disabled. Not creating JIRA tickets.")

if __name__ == "__main__":
    main()
