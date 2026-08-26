#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
# Script to validate the PR title with a modified Conventional Commit format.
#
# Unit test:
# test_check_pr_title.py

import argparse
import pygit2
import yaml
import re
import os
import sys
from github import Github
from github.GithubException import BadCredentialsException

# Constants
RELATIVE_PIPELINE_CONFIG_PATH = 'hack/ci/pipeline.yaml'

def check(string):
    type_regex = r'(feat|fix|docs|refactor|chore|vuln)'  # TYPE
    compatibility_issue_regex = r'(!)?'  # ! (Optional)
    scope_regex = r'(?:\((\w+)\))?: '  # SCOPE (Optional)
    jira_regex = r'((?:[A-Z0-9]+-\d+)(?:,\s?[A-Z0-9]+-\d+)*): '  # JIRA
    jira_regex_case_insensitive = r'((?:[a-zA-Z0-9]+-\d+)(?:,\s?[a-zA-Z0-9]+-\d+)*): '  # JIRA
    subject_regex = r'(\S.*)'  # SUBJECT

    if re.match(r'Merge branch \'master', string):
        return True, ""
    elif re.match(type_regex + compatibility_issue_regex + scope_regex + jira_regex + subject_regex, string):
        return True, ""
    elif re.match(type_regex + compatibility_issue_regex, string) is None:
        return False, "TYPE"
    elif re.match(type_regex + compatibility_issue_regex + scope_regex, string) is None:
        return False, "SCOPE"
    elif re.match(type_regex + compatibility_issue_regex + scope_regex + jira_regex, string) is None:
        if re.match(type_regex + compatibility_issue_regex + scope_regex + jira_regex_case_insensitive, string) is not None:
            print("The JIRA Ticket contained lowercase characters in the project field. "
                  "JIRA ticket characters must be uppercase.")

        return False, "JIRA"
    else:
        return False, "SUBJECT"


syntax_desc = """
Expected PR Title/Commit message Format:
TYPE[!][(SCOPE)]: JIRA: SUBJECT

Where:
[]      : Indicates an optional component.
TYPE    : Is one of the following:
            feat     : new feature
            fix      : bug fix
            docs     : documentation only change
            refactor : code change that neither fixes a bug nor adds a feature
            chore    : changes to the build or auxiliary tools, libraries, etc.
            vuln     : a fix to address a specific security vulnerability
!       : (Optional) Indicates a compatibility issue.
SCOPE   : (Optional) Indicates the area of project.
JIRA    : JIRA ticket ID. This may be a comma-separated list.
SUBJECT : Succinct description of the change.
"""

parser = argparse.ArgumentParser(description='Validate the PR matches the Conventional Commit format.')
parser.add_argument('-w', '--workspace-root', dest='ws_root', default='workspace-pr',
                    help='The path to the workspace root')
parser.add_argument('-t', '--token', dest='token', default='', required=True,
                    help='GitHub token to access API')
parser.add_argument('-a', '--api-uri', dest='api_uri', required=False, default="https://github.ibm.com/api/v3",
                    help='The base URI for the Github API')
# Optional argument; will use value passed in, otherwise will read from the .git/url file
parser.add_argument('-p', '--pull-request', dest='pull_request', required=False,
                    help='Specify the PR number')
# The following parser arguments are designed to be used for testing,
# as the code is written such that the below vars are automatically obtained during execution in Concourse
parser.add_argument('-o', '--workspace-org', dest='ws_org', required=False,
                    help='Specify the workspace organization')
parser.add_argument('-r', '--workspace-repo', dest='ws_repo', required=False,
                    help='Specify the workspace repository')
args = parser.parse_args()


def get_pr_info():
    """
    Gets some specific info based on the pull request cloned locally
    :return: remote url; commit hash of the head commit; pr number
    """
    pygit2_local_repo = pygit2.Repository(args.ws_root)

    # Check for variable being set/passed in. if not set, follow the normal process
    # otherwise run a bit differently to allow testing/running outside of Concourse
    if args.pull_request is None:
        try:
            with open(args.ws_root + '/.git/url') as f:
                pr_url = f.read()
                # Find all matches for numbers of length 1 or longer, putting each result into a list
                pr_regex_result = re.findall('[0-9]+', pr_url)
                # get the last number in the list, as the PR number is at the end of the string.
                pr_number = int(pr_regex_result[len(pr_regex_result)-1])
        except FileNotFoundError as fnferr:
            print(f"Error: {fnferr}")
            sys.exit(fnferr.errno)
        except OSError as oserr:
            print(f"Error: {oserr}")
            sys.exit(oserr.errno)
    else:
        pr_number = int(args.pull_request)

    return pygit2_local_repo.remotes["origin"].url, pygit2_local_repo.head.target.hex, pr_number

def is_check_all_commits():
    """
    Check in hack/ci/pipeline.yaml whether validate all comments property is enabled
    :return: True if property exist and set to True, otherwise return False
    """
    full_pipeline_config_path = args.ws_root + '/' + RELATIVE_PIPELINE_CONFIG_PATH
    # Verify the pipeline.yaml file exists
    if os.path.exists(full_pipeline_config_path):

        # Open and load the content
        with open(full_pipeline_config_path, 'r') as stream:
            ci = yaml.safe_load(stream)

            # If the content is not None and there is a key 'pr' on it
            if ci and 'pr' in ci:

                    # Get the PR section
                    pr_section = ci['pr']

                    # If the PR section is not None and there is check_commits under it, check if the value is True and return accordingly
                    if pr_section and 'check_commits' in pr_section:
                            if pr_section['check_commits'] == True:
                                print("Validating all commits format")
                                return True
    return False


def parse_remote_url(remote_url: str):
    """
    Takes in a git remote and parses out the workspace org and the workspace repo, and returns both
    :param remote_url: the value of a pre-defined git remote
    :return: workspace_org, workspace_repo
    """
    # Check if vars (for testing) are set, and use those if so.
    if args.ws_repo is not None and args.ws_org is not None:
        workspace_org = args.ws_org
        workspace_repo = args.ws_repo
    else:
        workspace_org = remote_url[remote_url.index(':')+1:remote_url.index('/')]
        workspace_repo = remote_url[remote_url.index('/')+1:remote_url.index('.git')]
    return workspace_org, workspace_repo


# If this script starts execution and runs the code to obtain the information from the remote PR
# after another commit has been pushed to the PR, then the state of the PR (in code) will not align with the state of
# the PR that was pulled down by Concourse, so a check needs to be added to ensure this code runs against only commits
# that were available for the state of the PR in Concourse
if __name__ == '__main__':

    # First verify if we will need to explicitly check each commit
    check_all_commits = is_check_all_commits()
    print(f"check all commits: {check_all_commits}")

    # Assume by default that the title is valid, that we will check commits, and that the commits checked are valid
    pr_title_valid = True
    commits_checked = True
    commits_valid = True

    # Get the parameters we need
    # If as the Workspace root we got the string 'NO_NEED_LOCAL_PARSING' then assume we got everything we need as arguments
    if args.ws_root == 'NO_NEED_LOCAL_PARSING':
        pr_number = int(args.pull_request)
        workspace_org = args.ws_org
        workspace_repo = args.ws_repo
    else:
        # Local parsing to get what we need
        remote_url, head_commit_hash, pr_number = get_pr_info()
        workspace_org, workspace_repo = parse_remote_url(remote_url)
    
    github = Github(base_url=args.api_uri, login_or_token=args.token)
    
    # Some info
    print(f"Will proceed to get PR number {pr_number} from repo {workspace_repo} in organization {workspace_org}")

    try:
        github_pr = github.get_repo(workspace_org + "/" + workspace_repo).get_pull(pr_number)
    except Exception as err:
        print(f"Error: {err}")
        sys.exit(1)

    # Always validate the PR Title to ensure it fits the correct format.
    print("Validate PR Title")
    pr_title = github_pr.title
    print(f"--- PR Title:\n{pr_title}\n")
    result, component = check(pr_title)
    if result:
        print("### PR title validation successful.")
    else:
        pr_title_valid = False

    # Get a list of all the commits that are not merge commits
    non_merge_commits = [commit for commit in github_pr.get_commits() if len(commit.parents) == 1]

    if check_all_commits:
        # If need to check all commits, do it (This logic checks all commits no matter if we find one invalid)
        for commit in non_merge_commits:
            commit_message = commit.commit.message
            print(f"--- Verify that the following commit message is valid: \n{commit_message}\n")
            result, component = check(commit_message)
            if result:
                print("###     OK\n")
            else:
                print("### NOT OK\n")
                commits_valid = False
            print(f"--- Explicitly required to check all commits, so trying to move on to the next commit... \n")

        print(f"Finished checking all the commits, the result of the check of commits is {commits_valid} \n")
    else:
        # The logic at this point is: if we have more than one commit then we do not check commits and we use only the PR title; if there is one commit then we check it
        if len(non_merge_commits) > 1:
            print("There is more than one non-merge commit and it was NOT explicitly required to check all commits, so in this case we do not check any commit")
            commits_checked = False
        else:
            if non_merge_commits:
                print("There is only one non-merge commit; will check it:")
                commit_message = non_merge_commits[0].commit.message
                print(f"--- Verify that the following commit message is valid: \n{commit_message}\n")
                result, component = check(commit_message)
                if result:
                    print("###     OK\n")
                else:
                    print("### NOT OK\n")
                    commits_valid = False
            else:
                print("Seems there are no commits in the PR, something must be wrong...")
                sys.exit(1)

    print("\n ########## CHECK SUMMARY ########## \n")
    print(f" PR Title is OK: {pr_title_valid} \n")
    if commits_checked:
        print(f"Commit messages are OK: {commits_valid} \n")

    if pr_title_valid and commits_valid:
        print("Check passed succesfully")
    else:
        print(f"{syntax_desc}\n ")
        sys.exit(1)
