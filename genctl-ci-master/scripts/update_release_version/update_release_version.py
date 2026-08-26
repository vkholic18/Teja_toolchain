# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: For each JIRA ticket involved in a release version
#              Updates the release version field with the format <workspace>:<release>
#
#
# Env:
#    CONFIG_FILE_PATH: Path to config file provided by AutoSemver
#    JIRA_USERNAME: The JIRA username
#    JIRA_PASSWORD: The JIRA password
#    JIRA_URL: The URL to the JIRA instance
#    JIRA_CERT_FILE: The path to the certificate used to connect to JIRA
#    DRY_RUN: Boolean indicating if is a dry run or not
#
# Use:
#    python3 update_release_version.py

import semver
import json
import logging
import os
import operator

# This is an internal use python package created in order to reuse code through our project
# Ensure that you 'pip installed' it before running this script
from ci_python_tools import jira_tools, general_tools

FIELD_MAPPING = {
    'release_version': 'customfield_10249'
}
FIELD_TO_UPDATE_NAME = 'release_version'
FIELD_TO_UPDATE_ID = FIELD_MAPPING[FIELD_TO_UPDATE_NAME]

def get_latest_version(versions):
    """
        Receives a list of strings in which each of them is a version in semver format

        Returns: A string with the latest version

        Example: See unit test for example
    """

    # Start by assuming that the latest version is the first element of the list
    latest_version = versions[0]

    # Iterate over the versions and compare with the latest using semver
    for version in versions:
        compare_result = semver.compare(version, latest_version)

        # If the version of this iteration is newer, then we consider it the latest
        if compare_result > 0:
            latest_version = version
    
    return latest_version

def get_workspaces_with_versions(str_to_process):
    """
        Receives a string that contains 'pairs' of workspace names and versions separated by comma

        Returns: A dictionary in which the key is the name of the workspace and the value is a list of versions

        Example: See unit test for example
    """
    # Create an empty dict that will hold the result
    result = dict()

    # Split comma to get the pairs
    pairs = str_to_process.split(',')
    
    # Iterate over the pairs 
    for pair in pairs:
        
        # Split to get the workspace and the version
        splitted_pair = pair.split(':')
        workspace = splitted_pair[0].strip()
        version = splitted_pair[1].strip()

        # If the workspace already exists in the dictionary just add the version (If it does not exist yet), if not create new entry
        if workspace in result:
            if version not in result[workspace]:
                result[workspace].append(version)
        else:
            result[workspace] = [version]

    return result

def clean_dict_workspaces_versions(workspaces_with_versions):
    """
        Receives A dictionary in which the key is the name of the workspace and the value is a list of versions

        Returns: A dictionary in which the key is the name of the workspace and the value is the latest version
                 In addition if we have both short and long versions it keeps only the key of the short one

        Example: See unit test for example
    """
    result = dict()

    for workspace in workspaces_with_versions:
        
        # Get the latest version
        latest_version = get_latest_version(workspaces_with_versions[workspace])

        # This is to avoid duplication of having in the JIRA twice same workspace (One with -workspace and one not)
        
        # First we verify that the workspace ends with -workspace
        # If it does not ends with -workspace
        # (Not all of them do, for example: https://github.ibm.com/riaas/regional-storage)
        if workspace.endswith('-workspace'):

            # If the workspace ends with -workspace then we "calculate" the short version by removing it
            short_workspace_name = workspace.replace('-workspace','')

            # If it appears already with the short version, then we keep the short version as key
            # If not the key is the long version
            # The value is always the latest version of the long name since is the one that we are running now
            if short_workspace_name in workspaces_with_versions:
                result[short_workspace_name] = latest_version
            else:
                result[workspace] = latest_version
        else:
            result[workspace] = latest_version
        
    return result

def last_version_only(str_to_process):
    """
        Receives a string that contains 'pairs' of workspace names and versions separated by comma

        Returns: A string in the same format that received but containing only the last version of each workspace

        Example: See unit test for example
    """
    # Create an empty string for the result
    result = ""

    # Convert the string to a dictionary of workspaces and versions
    workspaces_versions = get_workspaces_with_versions(str_to_process)

    # Clean
    clean_workspaces_versions = clean_dict_workspaces_versions(workspaces_versions)

    # Iterate over the workspaces, get the latest version of each one and add to result
    for workspace in clean_workspaces_versions:
        latest_version = clean_workspaces_versions[workspace]
        result = result + f"{workspace}: {latest_version}, "
    
    # Return (Without last character that is the last ", " )
    return result[:-2]

def main():
    # Define mandatory_args
    mandatory_args = [
        'CONFIG_FILE_PATH',
        'JIRA_USERNAME' ,
        'JIRA_PASSWORD' ,
        'JIRA_URL'  ,
        'JIRA_CERT_FILE'    ,
        'DRY_RUN'
    ]

    # Define logger and parse environment vars
    logger = general_tools.set_up_logger(logging.INFO)
    args = general_tools.parse_env(mandatory_args)
    
    # Set the JIRA details in variables for better readability
    jira_username = args['jira_username']
    jira_password = args['jira_password']
    jira_url = args['jira_url']
    jira_cert_file = args['jira_cert_file']
    
    # Open the file
    with open(args['config_file_path']) as f:
        config = json.load(f)

    # Get the information from the file
    repo_name = config['repo_name']
    tag = config['current_tag']
    issues_to_update = config['issues']

    # Login to JIRA and instantiate of JIRA object
    jira = jira_tools.login_jira(jira_username, jira_password, jira_url, jira_cert_file, retries=5)

    # For each issue (JIRA ticket), update the field appending 
    for issue_to_update in issues_to_update:
        
        # Some logging
        logger.info(f"Will try to update issue {issue_to_update}")
        
        # Get the issue; if it does not exist, show warning and continue the loop
        try:
            current_issue = jira.issue(issue_to_update)
        except:
            logger.warning(f"Issue {issue_to_update} does not exist")
            continue

        # Get the current release version content in order to append to it
        current_release_version = operator.attrgetter(f'fields.{FIELD_TO_UPDATE_ID}')(current_issue)

        # Set variable that will hold the content to update (Start it with what is being updated)
        content_to_update_release_version = f'{repo_name}: {tag}'

        # If current_release_version not None, means that there is some content already 
        # In this case we want to append by setting the previous content, a "," and new content
        if current_release_version:
            content_to_update_release_version = f'{current_release_version}, {content_to_update_release_version}'
        
        # Keep only one instance of each workspace
        content_to_update_release_version = last_version_only(content_to_update_release_version)

        # If the value we will set in the field is getting too long, trim "-workspace"
        if len(content_to_update_release_version) > 100:
            content_to_update_release_version = content_to_update_release_version.replace('-workspace','')
        
        # If at this point this is still too large, then truncate
        if len(content_to_update_release_version) > 255:
            content_to_update_release_version = content_to_update_release_version[:255]

        # Some logging
        logger.info(f"For issue {issue_to_update}, will try to set on field {FIELD_TO_UPDATE_NAME}, the following value: {content_to_update_release_version}")

        if args['dry_run'] == 'false':
            # Append content to the release version field
            current_issue.update(fields={FIELD_TO_UPDATE_ID: content_to_update_release_version})
        else:
            logger.info("This is a dry-run, no actual JIRA action will be performed")

if __name__ == "__main__":
    main()
