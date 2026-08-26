# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Automatically merges the PR if all the following are true:
#        The pipeline is a hotfix
#        The current commit is the latest commit of the PR
#        The PR branch is up to date with the base branch
#        The PR can be merged (e.g. no merge conflicts)
#
# Env:
#    HOTFIX_BRANCH: The name of the hotfix branch
#    REPO_PATH: Path to the git repository on the filesystem
#    GH_API_URL: Github API url
#    GH_TOKEN: GitHub API token
#
# Use:
#    python3 auto_merge_pr.py
#

import github
import logging
import os
import re
from tenacity import retry, stop_after_attempt, wait_fixed

# Constants
# From https://github.com/jtarchie/github-pullrequest-resource#additional-files-populated
PR_URL_FILE_PATH = '.git/url'
SHA_FILE_PATH = '.git/head_sha'


def set_up_logger():
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
        'HOTFIX_BRANCH',
        'REPO_PATH',
        'GH_API_URL',
        'GH_TOKEN'
    ]

    missing_vars = list()
    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            missing_vars.append(var)

    if missing_vars:
        logger.error("Missing the following required env variables: " +\
            ', '.join(missing_vars))
        exit(1)

    return args

def parse_pr_url(repo_path):
    """
    Parses PR url from filesystem for org/repo and pr number
    Args:
        repo_path: Path to the repo on the filesystem
    Returns:
        org_repo: The org_name/repo_name where the PR is open
        pr_num: The PR number
    """
    with open(os.path.join(repo_path, PR_URL_FILE_PATH)) as f:
        url = f.read()

    regex = re.compile(r'https:\/\/[^\/]+\/(.+)\/pull\/([0-9]+)')
    match = regex.match(url)

    org_repo = match.group(1)
    pr_num = int(match.group(2))

    return org_repo, pr_num

@retry(stop=stop_after_attempt(5), wait=wait_fixed(2))
def is_latest_commit(repo_path, pr):
    """
    Checks if the commit currently being tested is the latest in the PR
    Args:
        repo_path: Path to the repo on the filesystem
        pr: Github PR object
    Returns:
        boolean, whether commit is latest 
    """
    with open(os.path.join(repo_path, SHA_FILE_PATH)) as f:
        current_sha = f.read().strip()

    latest_commit = pr.get_commits().reversed[0]
    latest_sha = latest_commit.sha

    return current_sha == latest_sha

@retry(stop=stop_after_attempt(5), wait=wait_fixed(2))
def is_branch_up_to_date(pr, repo):
    """
    Checks if PR branch is up to date with latest base branch commit
    Args:
        pr: Github PR object
        repo: Github repo object
    Returns:
        boolean, whether branch is up to date
    """
    base_branch_name = pr.base.ref
    base_branch = repo.get_branch(base_branch_name)
    latest_base_sha = base_branch.commit.sha

    pr_base_sha = pr.base.sha

    return pr_base_sha == latest_base_sha

@retry(stop=stop_after_attempt(5), wait=wait_fixed(2))
def delete_branch(repo, branch_name):
    """
    Deletes the given branch on remote
    Args:
        repo: Github repo object
        branch_name: Name of the branch to delete
    """
    logger = logging.getLogger()
    logger.info(f"Attempting to delete {branch_name} branch")

    ref = None
    try:
        ref = repo.get_git_ref(f"heads/{branch_name}")

    except github.GithubException as e:
        if '404' in str(e):
            logger.info(f"{branch_name} is already deleted")
            pass
        else:
            raise e

    if ref:
        ref.delete()
        logger.info(f"Successfully deleted {branch_name}")

@retry(stop=stop_after_attempt(5), wait=wait_fixed(2))
def post_comment(pr, body):
    """
    Posts a comment in the PR and tags all the reviwers
    Args:
        pr: Github PR object
        body: Text body of the comment
    """
    logger = logging.getLogger()
    users, teams = pr.get_review_requests()

    reviewer_names = list()
    for user in users:
        reviewer_names.append(user.login)

    for team in teams:
        reviewer_names.append(team.name)

    reviewer_handles = ['@' + name for name in reviewer_names]
    pr.create_issue_comment(f"{' '.join(reviewer_handles)}, \n{body}")
    logger.info("Posted comment to PR")

@retry(stop=stop_after_attempt(5), wait=wait_fixed(2))
def auto_merge(args):
    """
    Automatically merges the PR if:
        The current commit is the latest commit of the PR
        The PR branch is up to date with the base branch
        The PR can be merged (e.g. no merge conflicts)
    """
    logger = logging.getLogger()

    org_repo, pr_num = parse_pr_url(args['repo_path'])
    gh = github.Github(
        login_or_token=args['gh_token'],
        base_url=args['gh_api_url']
    )

    repo = gh.get_repo(org_repo)
    pr = repo.get_pull(pr_num)

    if is_latest_commit(args['repo_path'], pr):
        if pr.mergeable_state != 'dirty':
            if is_branch_up_to_date(pr, repo):
                logger.info("Auto merging PR")
                pr.merge()
                delete_branch(repo, pr.head.ref)
                exit(0)

            else:
                logger.error("Branch out of date with base; updating branch")
                pr.update_branch(pr.head.sha)
        else:
            msg = "Cannot auto merge to due conflicts; resolve them manually."
            logger.error(msg)
            post_comment(pr, msg)
    else:
        logger.error("This is not the latest commit; " +\
            "the pipeline build based off the latest commit will auto merge.")

    exit(1)

def main():
    logger = set_up_logger()
    args = parse_env()

    if args['hotfix_branch']:
        logger.info("Attempting to auto merge")
        auto_merge(args)
    else:
        logger.info("PR is not a hotfix; skipping auto merge")

if __name__ == "__main__":
    main()
