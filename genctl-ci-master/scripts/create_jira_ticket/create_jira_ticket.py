# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Creates a JIRA ticket and generates a txt file containing a link to it
#
#
# Env:
#
#    JIRA_USERNAME: The JIRA username
#    JIRA_PASSWORD: The JIRA password
#    JIRA_URL: The URL to the JIRA instance
#    JIRA_CERT_FILE: The path to the certificate used to connect to JIRA
#    PROJECT_KEY: The key of the project which will the JIRA will be created for, for example CIGC
#    SUMMARY: The content of the summary field for the JIRA that will be created
#    DESCRIPTION: The content of the description field for the JIRA that will be created
#    ISSUE_TYPE: The issue type of the JIRA that will be created
#    ADDITIONAL_FIELDS_FILE: Path to a JSON file containing all the additional fields for the JIRA that will be created
#    
# Use:
#    python3 create_jira_ticket.py

import sys
import json
import logging
import os
import operator

# This is an internal use python package created in order to reuse code through our project
# Ensure that you 'pip installed' it before running this script
from ci_python_tools import jira_tools, general_tools

def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    # Define mandatory_args
    mandatory_args = [
        'JIRA_USERNAME' ,
        'JIRA_PASSWORD' ,
        'JIRA_URL'  ,
        'JIRA_CERT_FILE'    ,
        'PROJECT_KEY'   ,
        'SUMMARY'   ,
        'DESCRIPTION'   ,
        'ISSUE_TYPE' 
    ]
    
    # Parse mandatory args
    args = general_tools.parse_env(mandatory_args)

    # Add the ADDITIONAL_FIELDS_FILE which is not mandatory
    if 'ADDITIONAL_FIELDS_FILE' in os.environ.keys() and not os.environ['ADDITIONAL_FIELDS_FILE'] == '':
        args['additional_fields_file'] = os.environ['ADDITIONAL_FIELDS_FILE']

    return args

def main():
    # Define logger and parse environment vars
    logger = general_tools.set_up_logger(logging.INFO)
    args = parse_env()
    
    # Set the JIRA details in variables for better readability
    jira_username = args['jira_username']
    jira_password = args['jira_password']
    jira_url = args['jira_url']
    jira_cert_file = args['jira_cert_file']

    # Set the JIRA issue details in variables for better readability
    project_key = args['project_key']
    summary = args['summary']
    description = args['description']
    issue_type = args['issue_type']

    # Declare additional fields as empty dict
    additional_fields = dict()

    # Load the additional fields if any
    if 'additional_fields_file' in args:
        with open(args['additional_fields_file']) as af:
            additional_fields = json.load(af)

    # Login to JIRA and instantiate of JIRA object
    jira = jira_tools.login_jira(jira_username, jira_password, jira_url, jira_cert_file, retries=5)

    # Create ticket
    new_issue = jira_tools.create_jira_ticket(jira,project_key,jira_url,summary,description,issue_type,additional_fields)

    # Create a text file containing a link to the new ticket
    with open("created_jira_ticket.txt", "w") as f:   
        f.write(f"{jira_url}/browse/{new_issue.key}")
        
if __name__ == "__main__":
    main()