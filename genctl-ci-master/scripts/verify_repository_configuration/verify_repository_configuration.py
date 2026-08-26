# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Verifies that a repository has certain configuration

#   If all the properties match the expected, exit 0
#   If not, prints the properties that do not match the expected and exit 1
#
#
# Env:
#    GHE_API_TOKEN: Token for Github API
#    GHE_API_URL: Url for the GitHub API
#    REPOSITORY_NAME: Name of the repository which configuration will be checked
#    EXPECTED_CONFIG_FILE_PATH (Optional): Path to the expected config file
#
# Use:
#    python3 verify_repository_configuration.py


import github
import json
import logging
import os
import sys

CONFIG_MISMATCH_BASE_ERROR_MESSAGE = "For configuration {} expected {}, but got {} \n"


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
        'REPOSITORY_NAME'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    # This is to deal with the expected config file path, by default use a file that is next to the current script that is being executed
    if 'EXPECTED_CONFIG_FILE_PATH' in os.environ.keys() and not os.environ['EXPECTED_CONFIG_FILE_PATH'] == '':
        args['expected_config_file_path'] = os.environ['EXPECTED_CONFIG_FILE_PATH']
    else:
        args['expected_config_file_path'] = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                         'default_expected_config.json')

    return args


def get_expected_repo_config(expected_config_file_path):
    """
        Gets the expected configuration for the repository, from the file passed as argument

        Returns: The expected configuration as a dictionary
    """
    # Load the content of the file
    with open(expected_config_file_path) as f:
        expected_config = json.load(f)

    return expected_config


def get_actual_repo_config(gh, repo_name):
    """
        Gets the actual configuration for the repository, from the GitHub API

        Returns: The actual configuration as a dictionary
    """
    # Get the repository
    repo = gh.get_repo(repo_name)

    # First check if the repository has a dev-integration branch, in that case just exit 0
    # for branch in repo.get_branches():
    #    if branch.name == 'dev-integration':
    #        logger.info(f"Repository {repo_name} has a dev-integration branch")
    #        sys.exit(0)

    return repo.raw_data


def compare_repo_config(expected_repo_config, actual_repo_config):
    """
        Compares the expected and actual configuration.

        The comparison verifies that the expected is a subset of the actual, this means that there can be keys
        defined in the actual that are not present in the expected (Since GitHub repositories have a lot of attributes),
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
    for config in expected_repo_config.keys():

        # First verify that the key exists in the actual config, if not error and exit
        if config not in actual_repo_config:
            logger.error(
                f"The key {config} which appears in the expected configuration file, does not exist in the actual configuration of the repo")
            sys.exit(1)
        else:
            # Set expected and actual
            expected_config_value = expected_repo_config[config]
            actual_config_value = actual_repo_config[config]

            # If they are different, add the error message to the list
            if expected_config_value != actual_config_value:
                result.append(
                    CONFIG_MISMATCH_BASE_ERROR_MESSAGE.format(config, expected_config_value, actual_config_value))

    return result


def main():
    # Define logger and parse environment vars
    logger = set_up_logger()
    args = parse_env()

    # Instantiate GitHub object
    gh = github.Github(
        login_or_token=args['ghe_api_token'],
        base_url=args['ghe_api_url']
    )

    # Get the expected configuration
    expected_repo_config = get_expected_repo_config(args['expected_config_file_path'])

    # Get the actual configuration
    actual_repo_config = get_actual_repo_config(gh, args['repository_name'])

    # Compare
    mismatch_config = compare_repo_config(expected_repo_config, actual_repo_config)

    # If there is mismatch between expected and actual configuration, show differences and exit 1
    if mismatch_config:
        logger.error(
            f"The configuration of the repository {args['repository_name']} is not as expected, see differences below")
        logger.error("\n\n" + "".join(mismatch_config))
        logger.error("For more information about this, see the following: https://confluence.swg.usma.ibm.com:8445/x/-INJCw")
        logger.error("Contact the repository administrator in order to fix the configuration")
        sys.exit(1)


if __name__ == "__main__":
    main()
