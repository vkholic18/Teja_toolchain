# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Verifies that protected branches in a repository have certain configuration

#   If for all the branches, all the configuration matches, exit 0
#   If not, prints the properties that do not match the expected, and exit 1
#
#
# Env:
#    GHE_API_TOKEN: Token for Github API
#    GHE_API_URL: Url for the GitHub API
#    REPOSITORY_NAME: Name of the repository from where the branches belong
#    MAIN_BRANCH_NAME: Name of the main branch (Usually master or main)
#    EXPECTED_CONFIG_FILE_PATH : Path to the expected config file
#    SPECIFIC_BRANCH_TO_CHECK (Optional): Name of a specific branch to check
#    (If this is used, only that branch is checked
#     The name of the branch should be one of the branches that appears in the expected file)
#    DEV_INTEG_SUFFIX (Optional): Suffix added to dev-integration branch
#
# Use:
#    python3 verify_protected_branches_configuration.py


from get_available_checks_helper import (
latest_commits_from_prs, get_last_week_commits_from_branch,
get_statuses_from_commit,
)

import github
from github.GithubException import UnknownObjectException
from ci_python_tools import general_tools
from datetime import datetime, timedelta
from math import ceil
import json
import logging
import os
import sys
from tenacity import retry, Retrying, RetryError, stop_after_attempt, wait_fixed, retry_if_exception_type


CONFIG_MISMATCH_BASE_ERROR_MESSAGE = "For branch {}, in the configuration {} expected {}, but got {} \n"
CHECKS_TO_BE_REQUIRED_BASE_ERROR_MESSAGE = "For branch {}, the following checks were expected to be marked as required checks, but they were not marked as required:  {} \n"
CHECKS_NOT_TO_BE_REQUIRED_BASE_ERROR_MESSAGE = "For branch {}, the following checks were expected to be not marked as required checks, but they were marked as required:  {} \n"

def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'VERIFY_PROTECTED_BRANCHES_GHE_API_TOKEN',
        'GHE_API_URL',
        'REPOSITORY_NAME',
        'MAIN_BRANCH_NAME',
        'EXPECTED_CONFIG_FILE_PATH'
    ]

    args = general_tools.parse_env(required_vars)

    # Support specific branch checking
    if 'SPECIFIC_BRANCH_TO_CHECK' in os.environ.keys() and not os.environ['SPECIFIC_BRANCH_TO_CHECK'] == '':
        args['specific_branch_to_check'] = os.environ['SPECIFIC_BRANCH_TO_CHECK']
    
    if 'DEV_INTEG_SUFFIX' in os.environ.keys() and not os.environ['DEV_INTEG_SUFFIX'] == '':
        args['dev_integ_suffix'] = os.environ['DEV_INTEG_SUFFIX']

    return args

@retry(stop=stop_after_attempt(5), wait=wait_fixed(2))
def get_available_status_checks(repo,ci_branches,today,one_week_ago,ci_checks_prefix):
    """
    Gets the repo object and returns the available checks

    Unfortunately there is no GHE API that gives us this, so came up with the following 'best effort' algorithm

    1. Iterate over the relevant CI_BRANCHES

    2. For each branch:
        Prefer to get checks from the last commit of open PRs TO that branch (As long as that last commit was from last week)
        In case we don't have "enough" of this type of commits, try to bring commits from the actual branch

    Returns: A set with the checks
    """

    # Declare empty set for holding the result
    result = set()
    # Iterate over the CI_BRANCHES
    for ci_branch in ci_branches:

        # Declare empty list that will hold the commits from where to get statuses for this branch
        commits_to_process = []
        # Get the open PRs to specific branch
        open_prs = repo.get_pulls(base=ci_branch)

        # If there are open PRs we start with them
        if list(open_prs):

            # Take up to 10 PRs
            prs_to_process = open_prs[:10]

            # From the 10 open PRs, bring the last commit of each one (As long as the commit is not older than a week)
            commits_from_prs = latest_commits_from_prs(repo,prs_to_process,one_week_ago)

            # Add the result to the list of commits that will be processed
            commits_to_process.extend(commits_from_prs)

        # If up to here we have less than 10 commits, we try with the commits from the branch itself
        if len(commits_to_process) < 10:

            # Get last week commits of the branch
            commits_from_branch = get_last_week_commits_from_branch(repo,ci_branch,today,one_week_ago)

            # Add the result to the list of commits that will be processed
            commits_to_process.extend(commits_from_branch)

        # Process
        for commit in commits_to_process:

            # Get statuses from that commit
            statuses = get_statuses_from_commit(commit,ci_checks_prefix)

            # Add to result
            result.update(statuses)

    return result

def get_expected_protected_branches_config(expected_config_file_path):
    """
        Gets the expected configuration for the protected branches, from the file passed as argument

        Returns: The expected configuration as a dictionary where the key is name of a branch
        and the value is a dict that represents the configuration
    """
    # Load the content of the file
    with open(expected_config_file_path) as f:
        expected_config = json.load(f)

    return expected_config


def format_raw_actual_protected_branch_config(raw_protected_branch_config):
    """
        Formats the raw protected branch config to a format that we can compare easily

        This is due to the fact that the response of GitHub is an object and if we just convert it to raw data,
        then we miss some fields, therefore this takes the raw data and builds the dictionary in the format we need

        Returns: A dictionary that represents the actual protected branch configuration ready for comparison
    """
    # Create an empty dictionary
    result = {}

    # Iterate over the keys of the dict
    for k in raw_protected_branch_config.keys():

        # If the value for k is a dictionary and it has enabled then we set in the result the boolean
        if type(raw_protected_branch_config[k]) == dict and 'enabled' in raw_protected_branch_config[k]:
            result[k] = raw_protected_branch_config[k]['enabled']
        else:
            result[k] = raw_protected_branch_config[k]

    return result

@retry(retry=retry_if_exception_type(UnknownObjectException), stop=stop_after_attempt(5), wait=wait_fixed(2))
def get_actual_protected_branch_config(repository, branch_name,user_login,ci_checks_prefix):
    """
        Gets the actual configuration for the repository, from the GitHub API

        Returns: The actual configuration as a dictionary that can be compared
    """
    # Get the logger
    logger = logging.getLogger()

    # Get the branch
    branch = repository.get_branch(branch_name)

    # Check that the branch is protected
    if branch.protected:
        try:
            # Get the protected branch config
            protected_branch_config = branch.get_protection()
        except UnknownObjectException:
            logger.error(f"Could not retrieve from GitHub branch protection for branch {branch_name}. ")
            logger.warning(f"Verify that user {user_login} is admin for the repository {repository.name}")
            sys.exit(1)
        # Convert it to raw data
        raw = protected_branch_config.raw_data

        # Return the protected branch config after format
        result = format_raw_actual_protected_branch_config(raw)

        # Set an empty list for checks_that_should_not_be_required, since we do not use the actual for comparison but we want it to be there so the comparison is done
        result['checks_that_should_not_be_required'] = []

        # Add a boolean representing False if required_pull_request_reviews is None or True otherwise
        if protected_branch_config.required_pull_request_reviews:
            result['required_pull_request_reviews'] = True
        else:
            result['required_pull_request_reviews'] = False

        # Set default values for the actual, will be overriden by the actual values we get from GitHub if any
        result['required_status_checks'] = False
        result['required_status_checks_names'] = []

        # Verify if there are actual values from GitHub and override accordingly
        if protected_branch_config.required_status_checks and protected_branch_config.required_status_checks.contexts:
            result['required_status_checks'] = True

            # Process the names of the status checks
            for status_check in protected_branch_config.required_status_checks.contexts:

                # Assume we will take the check as it comes
                actual_check_to_add = status_check

                # If is a "CI check", then remove the prefix
                if ci_checks_prefix in actual_check_to_add:
                    actual_check_to_add = actual_check_to_add.split('/')[1]

                # The split and taking the second part after the slash is due to the fact that the checks are in the form concourse-ci/SOMECHECK
                result['required_status_checks_names'].append(actual_check_to_add)

        # Add the ci_checks_prefix (Needed because is in expected and in order not to fail comparison)
        result['ci_checks_prefix'] = ci_checks_prefix
        
        # Return the final actual config for comparison
        return result
    else:
        logger.error(f"The branch {branch_name} is not a protected branch")
        sys.exit(1)


def compare_protected_branch_config(branch_name, expected_protected_branch_config, actual_protected_branch_config,available_status_checks):
    """
        Compares the expected and actual protected branch config.

        The comparison verifies that the expected is a subset of the actual,
        however if there are keys in the expected that do not appear in the actual, error will be logged and code will exit 1

        For the keys that are both in expected and actual verify that the value is the same

        Returns:

        A list with error messages for each key that is both in expected and actual but have different values,
        if there are none, returns an empty list
    """
    # Get the logger
    logger = logging.getLogger()

    # Create an empty list that will contain error messages for the configuration that do not match (In case there are)
    result = []

    # Iterate over the expected config and compare each configuration with the actual
    for config in expected_protected_branch_config.keys():

        # First verify that the key exists in the actual config, if not error and exit
        if config not in actual_protected_branch_config:
            logger.error(
                f"The key {config} which appears in the expected configuration file, does not exist in the actual configuration of the repo")
            sys.exit(1)
        else:
            # Set expected and actual
            expected_config_value = expected_protected_branch_config[config]
            actual_config_value = actual_protected_branch_config[config]

            # If the type is list we compare a little different, else regular comparison
            if type(expected_config_value) == list:

                # If the key is checks_that_should_not_be_required then we do a specific logic
                if config == 'checks_that_should_not_be_required':

                    # Create an empty list that will contain the checks that were expected to not be marked as required checks for that branch but were (AKA problematic)
                    bad_checks = []

                    # Iterate over the keys that should not be required and for each one verify if that check appears in the required checks of the actual config, if it does comparison is not OK and break loop
                    for check in expected_protected_branch_config['checks_that_should_not_be_required']:
                        if check in actual_protected_branch_config['required_status_checks_names']:
                            bad_checks.append(check)

                    # Comparison is OK if after the loop that runs above, the list of bad checks is still empty
                    comparison_ok = (bad_checks == [])
                else:
                    # If the key is required_status_checks_names then we want to consider as expected, only the ones that are available
                    if config == 'required_status_checks_names':

                        # Set the original expected required checks on a list
                        original_expected_required_checks = expected_config_value.copy()

                        # "Keep" in the expected only the statuses that are available to be marked as required
                        expected_config_value = [exp for exp in original_expected_required_checks if exp in available_status_checks]

                        # Get the discarded ones
                        discarded_checks = [check for check in original_expected_required_checks if check not in expected_config_value]

                        # Log
                        logger.info(f"Will compare the expected and actual required checks for branch {branch_name}")

                        if discarded_checks:
                            logger.info(f"Note that the following checks, despite they appear in the expected, won't be considered for the comparison, since they might not be available to mark as required: {str(discarded_checks)}")
                            logger.info(f"The reason for them to possibly not be available might be that they never run yet, or that they didn't run lately")


                    comparison_ok = (set(expected_config_value).issubset(set(actual_config_value)))
            else:
                comparison_ok = (expected_config_value == actual_config_value)

            # If the comparison is not OK we need to prepare the error message
            if not comparison_ok:

                # If the config that is being checked is checks_that_should_not_be_required the error message is different
                if config == 'checks_that_should_not_be_required':
                    error_message = CHECKS_NOT_TO_BE_REQUIRED_BASE_ERROR_MESSAGE.format(branch_name, bad_checks)
                elif config == 'required_status_checks_names':
                    missing_checks = [check for check in expected_config_value if check not in actual_config_value]
                    error_message = CHECKS_TO_BE_REQUIRED_BASE_ERROR_MESSAGE.format(branch_name,missing_checks)
                else:
                    error_message = CONFIG_MISMATCH_BASE_ERROR_MESSAGE.format(branch_name, config, str(expected_config_value),
                                                              str(actual_config_value))   

                # Append the error message
                result.append(error_message)

    return result


def main():
    # Define logger and parse environment vars
    logger = general_tools.set_up_logger(logging.INFO)
    args = parse_env()

    # Calculate datetimes that are used in few places
    today = datetime.today()
    one_week_ago = today - timedelta(days=7)

    # Support suffix for dev-integ
    dev_integ_branch = 'dev-integration'
    if 'dev_integ_suffix' in args:
        dev_integ_branch = f"{dev_integ_branch}{args['dev_integ_suffix']}"

    # Set the ci branches (To be used for retrieving available checks)
    ci_branches = [dev_integ_branch, args['main_branch_name']]
    try:
       for attempt in Retrying(stop=stop_after_attempt(5), wait=wait_fixed(2)):
           with attempt:
               # Instantiate GitHub object
               gh = github.Github(
                   login_or_token=args['verify_protected_branches_ghe_api_token'],
                   base_url=args['ghe_api_url']
               )
               # Get the user name
               user_login = gh.get_user().login
               # Get the repository
               repo = gh.get_repo(args['repository_name'])
    except RetryError:
        logger.error("Unable to initiate github")
        sys.exit(1)

    # Create an empty list for the result
    result = []

    # Get the expected configuration
    expected_protected_branches_config = get_expected_protected_branches_config(args['expected_config_file_path'])

    # Get the branches of that repository
    branch_names = [branch.name for branch in repo.get_branches()]

    # Verify that the CI branches exist
    if not set(ci_branches).issubset(set(branch_names)):
        logger.error(f"Missing branch/es: please ensure that the following branches exist in the repo: {str(ci_branches)}")
        sys.exit(1)

    # By default assume that we will check all the branches defined in the expected
    branches_to_check_configuration = list(expected_protected_branches_config.keys())

    # Handle the case where specific branch was passed
    if 'specific_branch_to_check' in args:

        # Use a var for easier reading purpose
        specific_branch_to_check = args['specific_branch_to_check']

        # Verify that the specific branch that was passed appears in the expected
        if specific_branch_to_check in branches_to_check_configuration:
            # Override in order to use only that specific branch
            branches_to_check_configuration = [ specific_branch_to_check ]

            logger.info(f"It was requested to explicitly verify the configuration of only the branch {specific_branch_to_check} ")
        else:
            logger.error(f"Branch {specific_branch_to_check} does not appear in the expected configuration file")
            sys.exit(1)

    # Log
    logger.info(f"For the following branches: {branches_to_check_configuration}, we will verify that such a branch exists in repo {args['repository_name']} and that it's configured properly")
    # Iterate over the branches of the expected file
    for branch in branches_to_check_configuration:

        # Verify the branch exists in the actual repository branches
        if branch in branch_names:
            # Log
            logger.info(f"Will verify that for branch {branch}, the expected and actual protected branch configuration match")

            # Get the expected protected branch config
            expected_protected_branch_config = expected_protected_branches_config[branch]

            # Get the checks prefix for that branch
            ci_checks_prefix = expected_protected_branch_config['ci_checks_prefix']
        
            # Get the available status checks (AKA = Checks found in the last week and that can be marked as required)
            available_status_checks = get_available_status_checks(repo,ci_branches,today,one_week_ago,ci_checks_prefix)

            # Get the actual protected branch config
            actual_protected_branch_config = get_actual_protected_branch_config(repo, branch,user_login,ci_checks_prefix)
            # Compare
            mismatch_config = compare_protected_branch_config(branch, expected_protected_branch_config,
                                                              actual_protected_branch_config,available_status_checks)

            # Add the result of the comparison as elements
            result.extend(mismatch_config)
        else:
            logger.error(f"Branch {branch} does not exist in {args['repository_name']}")
            sys.exit(1)

    # If there is mismatch between expected and actual configuration, show differences and exit 1
    if result:
        logger.error(
            f"The configuration of the protected branches for repository {args['repository_name']} is not as expected, see differences below")
        logger.error("\n\n" + "".join(result))
        logger.error("For more information about this, see the following: https://confluence.swg.usma.ibm.com:8445/x/-INJCw")
        logger.error("Contact the repository administrator in order to fix the configuration")
        sys.exit(1)


if __name__ == "__main__":
    main()
