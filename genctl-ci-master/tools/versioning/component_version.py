#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Validates version file
#
# Args:
#    version_file_path: path to the version file
#
# Use:
#    python3 component_version.py <version_file_path>
#

import json
import logging
import os
import re
import sys

# CONSTANTS
REQUIRED_FIELDS = ['name']
ALLOWED_FEILDS = REQUIRED_FIELDS + ['version']
# Regex to match version pattern
VERSION_PATTERN = re.compile(r"(\d+\.)(\d+\.)(\d+)$")
EXAMPLE_FILE_MSG = "example file: http://ibmurl.hursley.ibm.com/OT57"

def setup_logger():
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

def validate_file_exists(file_path):
    """
    Validates the existance of the passed file
    Args:
        file_path: the path to the file to check
    Exception:
        SystemExit with code 1 if file not found
    """
    logger = logging.getLogger()

    if not os.path.exists(file_path):
        logger.error(f"{file_path} is required but was not found")
        logger.info(EXAMPLE_FILE_MSG)
        exit(1)

def validate_json(json_str):
    """
    Validates json syntax of inputted string
    Args:
        json_str: string of json to test
    Exception:
        SystemExit with code 1 if json is invalid
    """
    logger = logging.getLogger()

    try:
        json.loads(json_str)
    except ValueError:
        logger.error("version file is not valid JSON")
        logger.info(EXAMPLE_FILE_MSG)
        exit(1)

def validate_required_fields(version_dict):
    """
    Validates all required fields exist
    Args:
        version_dict: version file dictionary
    Exception:
        SystemExit with code 1 if missing required field
    """
    logger = logging.getLogger()

    for field in REQUIRED_FIELDS:
        if field not in version_dict:
            logger.error(
                f"{field} is required in version file but was not found")
            logger.info(EXAMPLE_FILE_MSG)
            exit(1)

def validate_all_fields(version_dict):
    """
    Validates only allowed fields exist
    Args:
        version_dict: version file dictionary
    Exception:
        SystemExit with code 1 if unexpected field
    """
    logger = logging.getLogger()

    for field in version_dict:
        if field not in ALLOWED_FEILDS:
            logger.error(f"{field} is not a valid field")
            logger.info(EXAMPLE_FILE_MSG)
            exit(1)


def validate_fields_not_empty(version_dict):
    """
    Validates no fields are empty
    Args:
        version_dict: version file dictionary
    Exception:
        SystemExit with code 1 if empty field
    """
    logger = logging.getLogger()

    for field in version_dict:
        if not bool(version_dict[field].strip()):
            logger.error(f"{field} cannot be empty")
            logger.info(EXAMPLE_FILE_MSG)
            exit(1)

def validate_version_format(version_dict):
    """
    Validates version is in correct semantic format
    Args:
        version_dict: version file dictionary
    Exception:
        SystemExit with code 1 if version is incorrect format
    """
    logger = logging.getLogger()

    if not bool(VERSION_PATTERN.match(version_dict['version'])):
        logger.error(
            "version field in improper format; " +\
            f"regex used to validate: {str(VERSION_PATTERN)}"
        )
        logger.info(EXAMPLE_FILE_MSG)
        exit(1)

def main():
    logger = setup_logger()

    try:
        version_file_path = sys.argv[1]
    except IndexError:
        logger.error("Missing required argument: version_file_path")
        exit(1)

    validate_file_exists(version_file_path)
    with open(version_file_path) as f:
        version_file_str = f.read()

    validate_json(version_file_str)
    version_file = json.loads(version_file_str)

    validate_required_fields(version_file)
    validate_all_fields(version_file)
    validate_fields_not_empty(version_file)

    if 'version' in version_file.keys():
        validate_version_format(version_file)

    logger.info(f"{version_file_path} is valid!")

if __name__ == '__main__':
    main()
