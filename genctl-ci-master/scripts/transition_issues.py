#!/usr/local/bin/python3
#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

"""
This script parses the slack-output/gitdiff.txt file for git commit hash and JIRA ticket numbers in git log messages.
JIRA issues that are found are automatically transitioned to the next status if status of the ticket and the input status provided by the user match. 
""" 

import sys  
import requests
import json
import re
import argparse

STATUS_LOOKUP = {
                "In Review": 461,
                "Merge": 471,
                "Build": 481,
                "Deploy": 491,
                "Integration Test": 501,
                "Staging Promotion": 511,
                "In Staging": 521,
                "Promote to Production": 531
                }

def get_projects(jira_url, credentials):
    """
     Check if JIRA is up running and we are able to authenticate successfully as Concourse user.
     Once authenticated get all active projects in JIRA.
        
    @return: List of all active jira projects
    """

    # Check if JIRA is down
    try:
        jira_check = requests.head(jira_url, headers={'Authorization': "Basic" + " " + credentials, 'Content-Type': 'application/json'})
        jira_check.raise_for_status()
    except requests.exceptions.RequestException as e:
        print("Exiting JIRA cannot be reached.")
        print(e)
        sys.exit(1)

    # JIRA projects rest endpoint
    project_url = "{}/rest/api/3/project".format(jira_url)
    project_list = []

    # Get jira projects
    try:
        projects = requests.get(project_url, headers={'Authorization': "Basic" + " " + credentials, 'Content-Type': 'application/json'})
        projects.raise_for_status()
    except requests.exceptions.RequestException as e:
        print(e)
        sys.exit(1)

    # Get project key from json        
    return [x['key'] for x in projects.json()]

def get_issues(filename):
    """ 
    Parse slack-output/gitdiff.txt file get all the JIRA tickets in the git commit logs.
    The regex matches jira issue e.g ci-123, CI-1234, CI2-1234
    
    @return: List containing all matching jira issues
    """

    # JIRA issue regex
    jira_pattern = re.compile('[aA-zZ0-9]+-[0-9]+')

    # Make sure file gets closed after being iterated
    try:
        with open(filename, 'r') as f:
            lines = f.read()
    except (IOError, OSError) as e:
        print(e)
        sys.exit(1)

    # Get JIRA all jira tickets from the commit and remove trailing or preceding whitespaces
    jira_ids = re.findall(jira_pattern, lines)
    jira_ids = [x.strip(' ') for x in jira_ids]
    return jira_ids

def transition_issues(jira_ids, project_list, jira_url, credentials, status):
    """
    Transition issue.
        
        STATUS 200 Application/json.Returns a full representation of an issue in JSON format.
        STATUS 404 Returned if the requested issue was not found, or the user does not have permission to view it.
        
        
        @param jira_ids: List containing jira issue ids
        @param project_list: List of active JIRA projects. 
        @param transition_details: Containing JIRA issue id used for transition 
        @return: transition_status
    """

    # jira_update_failed list capture jira updates that failed
    jira_update_failed = []

    # Update orda hash custom field in JIRA
    for jira in set(jira_ids):
        # Get the jira project key from the issue id. For example in issue id JIRA-123, JIRA is the project key  
        if jira.split("-")[0] in project_list:
            # Set issue setup url
            status_url = "{}/rest/api/3/issue/{}".format(jira_url, jira)
            try:
                issue_status = requests.get(status_url, headers={'Authorization': "Basic" + " " + credentials, 'Content-Type': 'application/json'})
                issue_status.raise_for_status()
            except requests.exceptions.RequestException as e:
                jira_update_failed.append(jira)
                continue

        # Check if jira issue status matches user input.
            if issue_status.json()['fields']['status']['name'] == status:
               # Set transition url
               transition_url = "{}/transitions".format(status_url)
               print("Enter")

               # Set payload for transitioning
               data = {
                       "update": {},
                       "transition": {
                         "id": STATUS_LOOKUP[status]
                       }
                      } 

               # transtion issue
               try:
                   response = requests.post(transition_url,data=json.dumps(data), headers={'Authorization': "Basic" + " " + credentials, 'Content-Type': 'application/json'})  
                   response.raise_for_status()
               except requests.exceptions.RequestException as e:
                     jira_update_failed.append(jira)

               # get new status
               try:
                   new_status = requests.get(status_url, headers={'Authorization': "Basic" + " " + credentials, 'Content-Type': 'application/json'})
                   print("Successfully transitioned {} status from {} to {}".format(jira, issue_status.json()['fields']['status']['name'], new_status.json()['fields']['status']['name']))
                   new_status.raise_for_status()
               except requests.exceptions.RequestException as e:
                   print(e)
 
            else:
               print("Skipping {} as issue status is {} and input status is {}".format(jira, issue_status.json()['fields']['status']['name'], status))

    # Set concourse build status to failed if any jira update failed           
    if not jira_update_failed:
        sys.exit(0)
    else:
        print("Failed to transition issues {}".format(jira_update_failed))  
    sys.exit(1)

def main():

    parser = argparse.ArgumentParser(description="Script to transition jira issues. Run the script as ./transition_issues.py -u http://cloudlab-jira.canlab.ibm.com:8080 -f slack-output/gitdiff.txt -c <base64 encoded credentials> -s Merge -e")
    parser.add_argument('-u', '--url', help="JIRA URL", required=True, dest="jira_url")
    parser.add_argument('-f', '--filename', help="location of slack-out/gitdiff.txt", required=True, dest="filename")
    parser.add_argument('-c', '--credentials', help="Credentials for connecting to JIRA", required=True, dest="credentials")
    parser.add_argument('-s', '--status', help="Status of the JIRA issue", choices=list(STATUS_LOOKUP.keys()),  required=True, dest="status")
    parser.add_argument('-e', '--enable', help="Enable the script to transition tickets", action="store_true", default=False, dest="enable")
    args = parser.parse_args()

    #JIRA issue and project rest endpoint.
    #Detailed info can be found here https://developer.atlassian.com/server/jira/platform/rest-apis/

    # Skip if script enable flag is not passed

    if args.enable == False:
        print("Skipping transtioning issues as -e/--enable flag is set to False")
        sys.exit(0)

    #Get all issues matching regex
    issues = get_issues(args.filename)

    #Get all active JIRA projects
    jira_projects = get_projects(args.jira_url, args.credentials)

    # Transition Issue
    transition_issues(issues, jira_projects, args.jira_url, args.credentials, args.status)

if __name__ == "__main__":
    # tranistion issues
    main()
