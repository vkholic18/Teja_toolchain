# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Merges a PR

#
#
# Env:
#    GHE_API_TOKEN: Token for Github API
#    GHE_API_URL: Url for the GitHub API
#    REPOSITORY_NAME: Name of the repository which configuration will be checked
#    PR_NUMBER: Number of the PR that needs to be merged
#    PR_SHA: The SHA of the PR
#    MERGE_METHOD (Optional): Method for merging, should be one of the following merge, squash or rebase
#    APPROVE_BEFORE_MERGE (Optional): If set to true it will approve the PR before merging it
# Use:
#    python3 merge_pr.py


import github
import logging
import os

def set_up_logger():
    """
    Configures logger and formatting
    Returns:
        Logger object
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
        'GHE_API_TOKEN',
        'GHE_API_URL',
        'REPOSITORY_NAME',
        'PR_NUMBER',
        'PR_SHA'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    # If a merge method was passed and is valid, use it, if not, use merge
    if 'MERGE_METHOD' in os.environ.keys():
        if os.environ['MERGE_METHOD'] in ['merge', 'squash', 'rebase']:
            args["merge_method"] = os.environ['MERGE_METHOD']
        else:
            logger.error(f"Merge method {os.environ['MERGE_METHOD']} is not supported")
            logger.error(f"The supported merge methods are: merge, squash and rebase")
            exit(1)
    else:
        args["merge_method"] = "merge"

    # If we have an environment variable APPROVE_BEFORE_MERGE give the value, if not assume false
    if 'APPROVE_BEFORE_MERGE' in os.environ.keys():
        args['approve_before_merge'] = os.environ['APPROVE_BEFORE_MERGE']
    else:
        args['approve_before_merge'] = "false"


    # If we have an environment variable CREATE_FILE_WITH_MERGE_COMMIT_SHA give the value, if not assume false
    if 'CREATE_FILE_WITH_MERGE_COMMIT_SHA' in os.environ.keys():
        args['create_file_with_merge_commit_sha'] = os.environ['CREATE_FILE_WITH_MERGE_COMMIT_SHA']
    else:
        args['create_file_with_merge_commit_sha'] = "false"

    return args

def get_pull_request_by_number(repo, pr_number):
    """
    Gets the PR based on the PR number
    Returns:
        PR (PyGithub object)
    """
    # Get the logger
    logger = logging.getLogger()

    # Get the PRS
    pr_numbers = [pr.number for pr in repo.get_pulls()]

    # If the PR exist return it, if not exit 1
    if pr_number in pr_numbers:
        return repo.get_pull(pr_number)
    else:
        logger.error(f"PR with number {pr_number} does not exist ")
        exit(1)

def main():
    # Define logger and parse environment vars
    logger = set_up_logger()
    args = parse_env()

    # Instantiate GitHub object
    gh = github.Github(
        login_or_token=args['ghe_api_token'],
        base_url=args['ghe_api_url']
    )

    # Get the repository
    repo = gh.get_repo(args["repository_name"])

    # Get the PR
    pr = get_pull_request_by_number(repo, int(args["pr_number"]))

    # Before merge confirm pr sha and branch head sha are the same
    # Get PR branch
    pr_head_branch = pr.head.ref

    # Get head commit sha of branch
    sha_from_branch = pr.head.sha

    # Compare pr sha with branch head sha
    sha_from_pr=args['pr_sha']
    if sha_from_pr != sha_from_branch:
        logger.error(f"The sha from PR is {sha_from_pr} but the head of branch {pr_head_branch} is {sha_from_branch}. Both should match otherwise we could be merging untested code from {pr_head_branch}.")
        exit(1)

    # If required approve the PR
    if args['approve_before_merge'] == "true":
        pr.create_review(event="APPROVE")

    # Merge
    pr.merge(merge_method=args["merge_method"])

    logger.info(f"Succesfully merged PR {args['pr_number']} ")

    if args['create_file_with_merge_commit_sha'] == "true":
        merge_commit_sha = pr.merge_commit_sha
        with open('merged_pr_info.sh', 'w') as f:
            f.write(f'export MERGE_COMMIT_SHA="{merge_commit_sha}"\n')

if __name__ == "__main__":
    main()