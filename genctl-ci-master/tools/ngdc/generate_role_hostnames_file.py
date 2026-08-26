#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

import json 
import logging
import os
import yaml
import sys

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


def parse_env():
    """
    Parses environment variables for required and optional arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    # Required Vars
    required_vars = ['PATH_TO_PIPELINE_YAML','D_AND_T']
    optional_vars = ['TMP_ROLES_SUFFIX']

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)
    
    for var in optional_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            args[var.lower()] = ""

    return args

def main():

    # Setup logger
    logger = setup_logger()

    # Parse environment variables
    args = parse_env()
    
    # Load YAML file
    with open(args['path_to_pipeline_yaml'], 'r') as yaml_file:
            pipeline_yaml_data = yaml.safe_load(yaml_file)

    # Iterate overt the deployments and tests until the find the current one we are processing
    for deployment_and_test in pipeline_yaml_data['deployment_ngdc']['deployments_and_tests']:
        
        # Check if is the one we are processing
        if deployment_and_test['name'] == args['d_and_t']:
            # Create empty dict for res
            res = {}
            
            # Check if we have roles
            if 'roles' in deployment_and_test:
                    
                    # Check if mode is override and if yes verify there is only one role
                    if deployment_and_test['mode'] == "override":
                         if len(deployment_and_test["roles"]) > 1:
                              logger.error(f"In override mode we support only one role")
                              logger.error(f"Will exit with error...")
                              sys.exit(1)
                    
                    # Iterate over the roles and for each role put all the nodes (Optionally include suffix)
                    for role in deployment_and_test['roles']:
                        
                        # The key will be at least the role
                        role_key = role

                        # Add suffix if needed
                        if args['tmp_roles_suffix'] != "":
                             role_key = f"{role_key}{args['tmp_roles_suffix']}"[:99]
                        
                        res[role_key] = deployment_and_test['nodes']

                        #Dump the result into a file 
                        with open('role_hostnames_result.json', 'w') as file:
                            json.dump(res, file, indent=2)
                            sys.exit(0)
            else:
                 logger.error(f"Could not find roles...")
                 sys.exit(1)
                        
if __name__ == "__main__":
    main()