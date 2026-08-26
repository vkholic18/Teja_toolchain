# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Verifies workspace dependencies file

# Env:
#    PATH_TO_WORKSPACE_DEPENDENCIES_FILE: The path to the vetted versions file that needs to be validated / cleaned
#
# Use:
#    python3 verify_workspace_dependencies_file.py

import logging
import sys

from ci_python_tools import general_tools
from cerberus import Validator
from schema import my_schema

def verify_workspace_dependencies(workspace_dependencies):
    """ Verifies if the content of the workspace dependencies file is valid """
    # Get the logger
    logger = logging.getLogger()

    # Assume that answer is true
    answer = True, ""

    # First we check if all the root-level mandatory fields appear
    if 'version' in workspace_dependencies:
        if 'external_services' in workspace_dependencies:
            if 'workspaces' in workspace_dependencies:
                # We check that version field has a value
                if workspace_dependencies['version']:
                    # We check that eiter external_services or workspaces (or both) have content
                    if workspace_dependencies['external_services'] or workspace_dependencies['workspaces']:
                        logger.info("Basic validation passed, now will check schema...")
                        v = Validator(my_schema)
                        answer = v.validate(workspace_dependencies), v.errors
                    else:
                        answer = False, "Either external_services or workspaces section need to have content"
                else:
                    answer = False, "version can not be empty"
            else:
                answer = False, "workspaces key is missing"
        else:
            answer = False, "external_services key is missing"
    else:
        answer = False, "version key is missing"

    return answer


def main():
    # Define mandatory_args
    mandatory_args = ['PATH_TO_WORKSPACE_DEPENDENCIES_FILE']

    # Define logger and parse environment vars
    logger = general_tools.set_up_logger(logging.INFO)
    args = general_tools.parse_env(mandatory_args)

    # Set the path in a variable to ease readability
    path_to_file = args['path_to_workspace_dependencies_file']

    # Load the content
    workspace_dependencies = general_tools.load_yaml(path_to_file)

    # Verify
    result, error = verify_workspace_dependencies(workspace_dependencies)

    if result:
        logger.info("Verification passed")
    else:
        logger.error("Verification failed")
        logger.error(f"Error: {error}")
        logger.error("For more information, see the schema: https://github.ibm.com/cloudlab/srb/blob/master/architecture/cicd/common/mascd/dependencies-schema.yaml")
        sys.exit(1)

if __name__ == "__main__":
    main()
