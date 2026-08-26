#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021-22
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

import logging
import sys
import re
from jira import JIRA

def login_jira(jira_username, jira_password, jira_base_url, jira_cert_file, retries=5):
    """
    Log in to JIRA
    """
    try:
        jira = JIRA(options={'server':jira_base_url, "rest_api_version": "3", 'verify':True}, basic_auth=(jira_username, jira_password))
    except Exception as e:
        print(f'Failed connecting to JIRA: {e}')
        sys.exit(1)
    return jira

def create_jira_ticket(jira, jira_key, jira_base_url, summary, description, issue_type, additional_fields={}):
    """
    Build the issue json and create a JIRA issue

    This is a generic method; the mandatory parameters are the fields that are "basic" and usually required in most projects
    In addition, there is the additional_fields parameter which should be a dictionary that we can use for adding additional fields (Ex: custom fields that might vary between tickets)
    """
    issue_json = {
       'project': {
          'key': jira_key
       },
       'summary': summary,
       'description': description,
       'issuetype': {
          'name': issue_type
       }
    }

    # Add the additional fields
    issue_json.update(additional_fields)

    try:
        new_issue = jira.create_issue(fields=issue_json)
        new_issue_key = new_issue.key
        print('Created JIRA: ' + jira_base_url + '/browse/' + new_issue_key)
    except Exception as e:
        print(e)
        sys.exit(1)
    return new_issue

def validate_key(jira, key):
    """
    Validate the passed JIRA key
    """
    try:
        # Initialize 'valid_key', otherwise if a JIRA error occurs, 'valid_key' will have no value and 'return valid_key' will cause 'UnboundLocalError'.
        valid_key = ""
        valid_key = jira.project(key)
    except Exception as e:
        print(e)
    return valid_key

def search_open_issues(jira, jira_project, search_string, exact_match_args=None):
    """
    Search all open jiras which contain the <search_string>. Look for exact match if <exact_match_args> passed
    Return the list of matching keys
    """
    keys = list()
    try:
        matching_issues = jira.search_issues(f'project = {jira_project} and status != Closed and {search_string}')

        if exact_match_args:
            # Find exact matches for the <exact_match_args> ending in any of [\s:,.] or end-of-line in the JIRA description
            # Example: <exact_match_args> = image_name in anchore
            for match in matching_issues:
                if re.search(r"{}([\s:,.]|$)".format(exact_match_args), match.fields.description, re.IGNORECASE):
                    keys.append(match.key)
        else:
            keys = [match.key for match in matching_issues]

    except Exception as e:
        print(e)
        sys.exit(1)

    return keys if bool(keys) else ''

def get_summary(jira, issue_key):
    """
    Return summary of a JIRA ticket
    """
    try:
        issue = jira.issue(issue_key)
        summary = issue.fields.summary
    except Exception as e:
        print(e)
        sys.exit(1)
    return summary

def close_issue(jira, jira_base_url, issue_key, comment, cve_id):
    """
    Close a JIRA issue
    """
    try:
        jira.add_comment(issue_key, comment)
        issue = jira.issue(issue_key)

        # 451 = transition id for 'Close'
        jira.transition_issue(issue, '451')
        print(f'Closed JIRA for {cve_id}: ' + jira_base_url + '/browse/' + issue_key)
    except Exception as e:
        print(e)
        sys.exit(1)

def is_jira_approved(jira, issue_key, authorized_approvers):
    """
    Checks if the JIRA ticket is approved by a custom list of approvers
    """
    approved = False
    try:
        issue = jira.issue(issue_key)

        for field_name in issue.raw['fields']:
            # 'customfield_19400' = Approver field in JIRA
            # Is the ticket "approved"?
            if field_name == 'customfield_19400' and issue.raw['fields'][field_name] is not None:
                jira_approver_email = issue.raw['fields'][field_name]['emailAddress']
                # Is it approved by someone in the authorized_approvers list?
                for approver in authorized_approvers:
                    if jira_approver_email.lower() == approver['email'].lower():
                        approved = True
                        break

    except Exception as e:
        print(e)
        sys.exit(1)

    return approved
