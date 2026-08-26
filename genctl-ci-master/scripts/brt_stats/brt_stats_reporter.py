#!/usr/bin/python
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
#
# Description:
#   Reads the last merged pr that was pushed into master, check for the run_workspace check status
#   in the last commit of the PR, if it failed - means blast-radius tests failed and the pr was pushed anyway
#   if it succeeded then the blast-radius passed
#   after that we fetch data about the pr, like commit statistics for the commits that run the brt tests
#   the script will then go through all the prs that were merged into master and search for the latest pr that failed/succeeded - based on
#   latest merged pr status, and will also fetch data regarding that pr for reference
#
# Env:
#    GITHUB_API_KEY: Api key to access GitHub API
#    GITHUB_API_URL: Url of GitHub API
#    WORKSPACE_REPO: Workspace repository name
#    WORKSPACE_ORG': Workspace org name
#    BRT_REPO: Blast radius stats repo name for writing the data
#    BRT_REPO_ORG: Blast radius stats repo org name 
#    CHECK_NAME: The name of the check we want to get statistics for - defaults to workspace_tests 
#
# Use:
#    python3 brt_stats_reporter.py
#


import github
import os
import logging
import yaml
import datetime
from github.GithubException import UnknownObjectException
from math import trunc
import json

BRT_TESTS_DEFINITION_FILE = "hack/ci/pipeline.yaml"
FILTERED_STATE = ["pending"]


def set_up_logger():
    """
    Configures logger and formatting
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
        'GITHUB_API_KEY',
        'GITHUB_API_URL',
        'WORKSPACE_REPO',
        'WORKSPACE_ORG',
        'BRT_REPO',
        'BRT_REPO_ORG',
        'CHECK_NAME',
        'OUT_DIRECTORY'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args


def get_last_pull_request_and_count_by_check(repo, branch="master", filter_pr_branch="master", check_name="", state="", filtered_state=None, threshold=50):
    """Gets the last pull request that was merged into a branch by default - determined by filter_pr_branch defaults to master
       and can also be used to get the latest pull request that was merged into a branch by a specific check and the check status
       example : find the latest pull request that was merged and blast-radius tests failed in, in this case
       we also return the amount of "misses" hits until we hit that status.
       the logic of the function is to loop through all the prs, find the pr's that were merged into the branch specified,
       if the check is not provided, return the pr object,
       if the check field is provided - get the last commit to the pr and check if the status of the check we are looking for matches
       loop until it does for a max number of threshold

    Args:
        repo (gh_repo): github repo object
        branch (str, optional): the branch name we fetch commits from. Defaults to "master".
        filter_pr_branch (str, optional): the name of the branch that the pr was merged into. Defaults to "master".
        check_name (str, optional): name of the check to look for in the pr commit checks. Defaults to "".
        state (str, optional): state of the check - i.e success/failure. Defaults to "".
        filtered_state ([type], optional): skip certain states like - pending . Defaults to None.
        threshold (int, optional): number of prs to look for until we find the specific check pr. Defaults to 50.

    Returns:
        github pr object and optional: count of missed checks
    """
    logger = logging.getLogger()
    seen = set()
    for commit in repo.get_commits(sha=branch):
        for pull in commit.get_pulls():
            if check_name:
                pr_commit = repo.get_commit(sha=pull.head.sha)
                if pull.base.ref == filter_pr_branch:
                    seen.add(pull.number)
                    checks = pr_commit.get_statuses()
                    pr_check_status = get_check_stats(
                        checks, check_name, filtered_state)
                    if pr_check_status and pr_check_status["state"] == state:
                        print(seen)
                        logger.info(f"found last pr {pull.number}, with check {check_name} state {state}")
                        return pull, (len(seen) - 1)
                    elif len(seen) == threshold or pull.number == 1:
                        logger.warning(
                            f"unable to find pr with check {check_name}, in state {state}")
                        return None, len(seen)

            elif pull.base.ref == filter_pr_branch:
                logger.info(
                    f"found last PR to {filter_pr_branch}, id: {pull.number}")
                return pull, 0


def get_check_commit_statistics(pull_request, check_name, filtered_state):
    """Analyzes and gets statistics report for a specified pull request based on a required check

    Args:
        pull_request (gh pr object): pull request to analyze the commits for
        check_name (str): name of the check we want to analyze the commit checks
        filtered_state (list): a list containing check states to skip

    Returns:
        dic: containing the number of success/failure/total for a specific check in the pr commit history
    """
    logger = logging.getLogger()
    logger.info(
        f"calculating statistics for pr #{pull_request.number}, check {check_name}")
    pr_stats = {
        "success": 0,
        "failure": 0,
        "total": 0
    }
    for commit in pull_request.get_commits():
        checks = commit.get_statuses()
        check_status = get_check_stats(
            checks, check_name, filtered_state)
        if check_status:
            pr_stats[check_status['state']] += 1
            pr_stats['total'] += 1
    pr_stats['success_rate'] = calc_percentage(
        pr_stats['success'], pr_stats['total'])

    return pr_stats


def parse_brt_suits(config_file):
    """Parses blast radius tests from the pipeline.yaml definition file

    Args:
        config_file (file): blast radius definition file

    Returns:
        list, None: list of the blast radius suits that run on PR to master
    """
    logger = logging.getLogger()
    if not config_file.get("functional_tests"):
        return
    logger.info("parsing functional test suites...")
    suites = []
    for suite in config_file['functional_tests']['cpap']['integration_testing_repo']['test_configs']:
        suites.append(suite['path'])
    return suites

def parse_mzone_name(config_file):
    if not config_file.get("deployment"):
        if not config_file.get("mzone_name"):
            return
    return config_file["deployment"]["mzone_name"]

def extract_pr_url(pr):
    """Extracts url from pr object

    Args:
        pr (gh pr object): github pr reference

    Returns:
        str: url of the pull request
    """
    return pr.url.replace("/api/v3/repos", "").replace("pulls","pull")


def format_status(repo_name, commit_checks, pull_request, brt_suite_names, pr_stats, ws_url, version, mzone_name):
    """Formats a dictionary of collected data

    Args:
        repo_name (gh repo object): name of the github workspace
        commit_checks (dic): commit check dictionary with state and target url
        pull_request (pr object): pull request object to extract pr data
        brt_suite_names (list): blast radius suit names
        pr_stats (dictionary): pr commit check statistics dictionary
        ws_url (str): github workspace url
        version (str): the version the brt ran against
        mzone_name(str): the dev mzone name the brts are running against
    Returns:
        dictionary: formatted dictionary of the collected data
    """

    return {
        "status": {
            "workspace_name": repo_name,
            "github_repo": ws_url,
            "latest_merged_pr_number": pull_request.number,
            "latest_merged_pr_head_version": version,
            "latest_merged_pr_url": extract_pr_url(pull_request),
            "state": commit_checks['state'],
            "merged_by": pull_request.merged_by.name,
            "merge_date": pull_request.merged_at.strftime("%m/%d/%Y %H:%M"),
            "mzone_name" : mzone_name if mzone_name else "N/A",
            "latest_merged_pr_commits_stats": pr_stats,
            "brt_concourse_target_url": commit_checks['target_url'],
            "brt_suites": brt_suite_names if brt_suite_names else "N/A",
        }
    }


def get_gh_file(gh, repo, path):
    """Gets gh file from a repo path

    Args:
        gh (gh object): github object
        repo (str): location of the repo org/ws
        path (str): path to the file location on the repo

    Returns:
        dictionary or none: returns file yaml contents
    """
    logger = logging.getLogger()
    try:
        gh_repo = gh.get_repo(repo)
        gh_file = gh_repo.get_contents(path)
        decoded_file = gh_file.decoded_content
        return yaml.safe_load(decoded_file), gh_file.sha
    except UnknownObjectException:
        logger.info(f"file {path} was not found and will be created")
        return None, None


def get_check_stats(checks, check_name, filtered_state):
    """Gets a specific check state from a checks list

    Args:
        checks (list): collection of commit checks
        check_name (str): name of the check to look for
        filtered_state (list): statuses to ignore i.e pending

    Returns:
        dictionary: the state and target url of a specific check
    """
    check_payload = {}
    for check in checks:
        if check.context == check_name and check.state not in filtered_state:
            check_payload = {
                "state": check.state,
                "target_url": check.target_url
            }
            return check_payload


def calc_percentage(numerator, total):
    """calculate percentage
    """
    return f"{trunc((numerator/total) * 100)}%" if total else "0%"

def format_new_pr_state(current_pull_request, previous_pull_request, state, count):
    """Formats data based on two opposite pr states - failure/success """
    
    return {
        f"last_merged_{state}_pr_number": previous_pull_request.number if previous_pull_request else "N/A",
        f"last_merged_{state}_pr_url": extract_pr_url(previous_pull_request) if previous_pull_request else "N/A",
        f"last_merged_{state}_pr_date": previous_pull_request.merged_at.strftime("%m/%d/%Y %H:%M") if previous_pull_request else "N/A",
        f"days_since_last_merged_{state}_pr": (current_pull_request.merged_at - previous_pull_request.merged_at).days if previous_pull_request else "N/A"
    }


def get_latest_commit_head_version(sha, repo):
    tags = repo.get_tags()
    tag = "N/A"
    for tag in tags:
        if sha == tag.commit.sha:
            tag = tag.name
            break
    return tag

def update_status(previous_state, new_state, gh_repo, check):
    """Updates the state status based on the new pr state and the last pr that was merged with the opposite check status
       example: if latest pr was forced pushed - meaning failure, this function will look for the latest pr
       that succeeded and return additional information between the two

    Args:
        previous_state (dictionary): previous status on the brt-stats workspace
        new_state (dictionary): current pr status
        gh_repo (gh repo): gh repo currently inspecting
        check (str): the check name referencing

    Returns:
        dictionary: updated status
    """
    logger = logging.getLogger()
    if previous_state and previous_state['latest_merged_pr_number'] == new_state['latest_merged_pr_number']:
        logger.info('Last PR to master has already been processed')
        exit(0)
    current_pr = gh_repo.get_pull(int(new_state['latest_merged_pr_number']))
    if new_state['state'] == "failure":
        last_success_pull_request, count = get_last_pull_request_and_count_by_check(
            gh_repo, check_name=check, state="success", filtered_state=FILTERED_STATE)
        new_state['number_of_failed_prs_since_last_success'] = count
        new_state.update(format_new_pr_state(current_pr, last_success_pull_request, "successful", count))

    elif new_state['state'] == "success":
        last_failed_pull_request, count = get_last_pull_request_and_count_by_check(
            gh_repo, check_name=check, state="failure", filtered_state=FILTERED_STATE)
        new_state['number_of_successful_prs_since_last_failure'] = count
        new_state.update(format_new_pr_state(current_pr, last_failed_pull_request, "failed", count))

    return new_state


def write_json(contents, out_file):
    with open(out_file, 'w') as outfile:
        json.dump(contents, outfile, sort_keys = False, indent = 4)

def main():
    # set up environemt
    logger = set_up_logger()
    brt_suites = None
    args = parse_env()
    gh = github.Github(
        login_or_token=args['github_api_key'],
        base_url=args['github_api_url']
    )

    # set up brt-stats and workspace to read the stats from
    ws = f"{args['workspace_org']}/{args['workspace_repo']}"
    brt_stats_ws = f"{args['brt_repo_org']}/{args['brt_repo']}"
    brt_stats_file_path = f"workspaces/{args['workspace_repo']}.yaml"
    gh_repo = gh.get_repo(ws)
    brt_repo = gh.get_repo(brt_stats_ws)
    # get previous statistic for workspace if exists
    previous_stats, sha = get_gh_file(gh, brt_stats_ws, brt_stats_file_path)
    pipeline_config_file, _ = get_gh_file(gh, ws, BRT_TESTS_DEFINITION_FILE)

    # get brt suits from hack/ci/pipeline.yaml directory
    if pipeline_config_file:
        brt_suites = parse_brt_suits(pipeline_config_file)
        mzone_name = parse_mzone_name(pipeline_config_file)
    # get the latest merged pr
    pull_request, _ = get_last_pull_request_and_count_by_check(gh_repo)
    # get the commit statistics for the latest merged pr
    pr_stats = get_check_commit_statistics(pull_request, args['check_name'], FILTERED_STATE)
    # get the latest commit for the latest merged pr
    pr_commit = gh_repo.get_commit(sha=pull_request.head.sha)
    # get the checks hat ran on the commit
    head_commit_checks = pr_commit.get_statuses()
    # get the check stats [success/failure] and concourse target url
    head_commit_check_stats = get_check_stats(head_commit_checks, args['check_name'], FILTERED_STATE)
    ws_url = gh_repo.url.replace("/api/v3/repos", "")
    latest_commit_head_version = get_latest_commit_head_version(pull_request.head.sha, gh_repo)

    # pour in all the data into an object
    status = format_status(gh_repo.name, head_commit_check_stats, pull_request, brt_suites, pr_stats, ws_url, latest_commit_head_version, mzone_name)

    # if we found a file that exists, we would update it based on the previous state, otherwise create a new file
    if previous_stats:
        updated_stats = {"status": update_status(
            previous_stats['status'], status['status'], gh_repo, check=args['check_name'])}
        commit_msg = f"Update new brt status file {brt_stats_file_path}"
        contents = yaml.safe_dump(updated_stats, sort_keys=False)
        logger.info(f"file {brt_stats_file_path}, has been found, updating...")
        brt_repo.update_file(brt_stats_file_path, commit_msg, contents, sha)
        logger.info(f"file {brt_stats_file_path} has been updated.")
        logger.info(f"writing results to local {args['out_directory']} file")
        write_json(updated_stats, args['out_directory'])
    else:
        commit_msg = f"Create new brt status file {brt_stats_file_path}"
        updated_stats = {"status": update_status(
            None, status['status'], gh_repo, check=args['check_name'])}
        contents = yaml.safe_dump(updated_stats, sort_keys=False)
        logger.info(f"file {brt_stats_file_path}, has not been found, creating...")
        brt_repo.create_file(brt_stats_file_path, commit_msg, contents)
        logger.info(f"file {brt_stats_file_path} has been created.")
        logger.info(f"writing results to local {args['out_directory']} file")
        write_json(updated_stats, args['out_directory'])


if __name__ == "__main__":
    main()
