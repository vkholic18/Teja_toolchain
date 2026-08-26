# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Validates/cleans a vetted versions file

#   This script has two possibles behaviours according to the VETTED_VERSIONS_VALIDATION_MODE
#   1. If VETTED_VERSIONS_VALIDATION_MODE = soft then it "cleans" the file, creating a new file with only the valid components
#   2. If VETTED_VERSIONS_VALIDATION_MODE = hard then it verifies that the file has the proper format and if not logs error and exit 1
#
# Env:
#    PATH_TO_VETTED_VERSIONS_FILE: The path to the vetted versions file that needs to be validated / cleaned
#    VETTED_VERSIONS_VALIDATION_MODE: A string that should be either "soft" or "hard"
#
# Use:
#    python3 validate_vetted_versions.py

import yaml
import logging
import os
import sys

INVALID_COMPONENT_BASE_ERROR_MESSAGE = "The value set for component {} is not a valid one \n"


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

    required_vars = ['PATH_TO_VETTED_VERSIONS_FILE', 'VETTED_VERSIONS_VALIDATION_MODE']

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    # Set the validation mode in a variable for readability
    vetted_versions_validation_mode = args['vetted_versions_validation_mode']

    # This is to verify that the VETTED_VERSIONS_VALIDATION_MODE has a valid value
    if vetted_versions_validation_mode not in ['soft', 'hard']:
        logger.error(f"VETTED_VERSIONS_VALIDATION_MODE value was {vetted_versions_validation_mode} should be 'soft' or 'hard' ")
        exit(1)

    return args


def clean_file(vetted_versions):
    """
    Used in "soft" mode, generates a new YAML content including only the valid components

    Returns:
        result: A YAML to be dumped containing only the valid components
    """
    # Get the logger
    logger = logging.getLogger()

    # Create an empty dict that will have only the valid components
    result = {
        'version': {

        }
    }

    # Verify that for each key there is a value that is not empty or null
    for ver in vetted_versions['version']:

        # Get the value, if empty or null, val is set to None and then we can make the following if
        val = vetted_versions['version'][ver]

        # If not None, is means it is valid, and therefore we want to "keep it" by putting it in the cleaned one
        if val:
            result['version'][ver] = val
        else:
            logger.info(f"The value set for component {ver} is not a valid one, will remove the component")

    return result


def validate_file(vetted_versions):
    """
    Used in "soft" mode, generates a new YAML content including only the valid components

    Returns:
        result: A list of strings that represents errors (Or an empty list if no errors)
    """

    # Get the logger
    logger = logging.getLogger()

    # Create an empty list that will contain error messages for the configuration that do not match (In case there are)
    result = []

    # Verify that for each key there is a value that is not empty or null
    for ver in vetted_versions['version']:

        # Get the value, if empty or null, val is set to None and then we can make the following if
        val = vetted_versions['version'][ver]

        # If val = None then it means is a "bad" component
        if not val:
            result.append(INVALID_COMPONENT_BASE_ERROR_MESSAGE.format(ver))

    return result


def main():
    # Define logger and parse environment vars
    logger = set_up_logger()
    args = parse_env()

    # Set the path in a variable to ease readability
    path_to_file = args['path_to_vetted_versions_file']

    # Set the mode in a variable to ease readability
    vetted_versions_validation_mode = args['vetted_versions_validation_mode']

    # Load the file
    with open(path_to_file) as f:
        vetted_versions = yaml.safe_load(f)

    # Verify it has the key versions
    if 'version' in vetted_versions:

        # Check which type of validation mode (soft or hard)
        if vetted_versions_validation_mode == "soft":
            # Clean mode #

            # Clean and get new content
            cleaned = clean_file(vetted_versions)

            # Dump new content
            with open("vetted_versions_cleaned.yaml", 'w') as new_file:
                yaml.safe_dump(cleaned, new_file)
        else:
            # Hard mode #

            # Get a list with the errors (Or empty if none)
            errors = validate_file(vetted_versions)

            if errors:
                logger.error(
                    f"The vetted versions file {path_to_file} is invalid; see errors below and fix in order to continue")
                logger.error("\n\n" + "".join(errors))
                sys.exit(1)
    else:
        logger.error(f"Vetted versions file should have 'version' at the top of the file")
        sys.exit(1)


if __name__ == "__main__":
    main()
