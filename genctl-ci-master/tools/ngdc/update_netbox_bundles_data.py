#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
############## I M P O R T S ##################################################
import pprint
import json 
import logging
import requests
from requests.exceptions import RequestException
from requests.packages.urllib3.exceptions import InsecureRequestWarning # type: ignore
import os
import yaml
import sys
import pynetbox
from github import Github


# Suppress only the single InsecureRequestWarning from urllib3 needed
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

################# F U N C T I O N S ###########################################

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
    required_vars = [
        'NETBOX_URL','NETBOX_TOKEN',
        'GHE_API_TOKEN', 'GHE_API_URL' ,
        'ROLES_TO_GET_NETBOX_BUNDLES_FROM',
        'BUNDLE_NAME_FOR_REPLACE_VERSION', 'VERSION_TO_REPLACE',
        'ART_VALUE_TO_REPLACE_IN_TESTED_BUNDLE', 'ART_VALUE_TO_REPLACE_IN_VETTED',
        'PATH_TO_VETTED_VERSION_FILES_FOR_REPLACEMENT', 'INVENTORY_REPO_BRANCH'
    ]
    optional_vars = ['UPDATE_NETBOX_BUNDLES_DATA_DRY_RUN_MODE']

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

def update_netbox_data_section(netbox_client,gh_client,role,bundle_built,bundle_built_version,art_for_bundle_built,art_for_vetted,inventory_branch,dry_run_mode):
    """
        Updates on netbox the bundles section
    """
    logger = logging.getLogger()

    # Create empty boolean for ensuring the one we built is on netbox
    found_bundle_to_built = False

    # Get role
    my_role = netbox_client.extras.config_contexts.get(name=role)
    
    # Check we have something
    if my_role:
            # Get netbox data from role
        netbox_data = my_role.data

        # Check that we have the bundle section; if not, throw error
        if 'release_bundles' in netbox_data:
            # Iterate over the bundles we got from netbox
            for netbox_bundle in netbox_data['release_bundles']:

                # First check if this is is the bundle we are building now
                if netbox_bundle['name'] == bundle_built:
                    
                    # Mark we found
                    found_bundle_to_built = True

                    # Set version
                    netbox_bundle['version'] = bundle_built_version

                    # Set artifactory path
                    netbox_bundle['artifactory_path'] = art_for_bundle_built
                else:
                    # Try to get version from inventory
                    inv_version = get_version_from_inventory(gh_client, f"genctl-cicd/vpc-{netbox_bundle['name']}-compliance-inventory",inventory_branch)
                    
                    if inv_version != "":
                        # Set version
                        netbox_bundle['version'] = inv_version
                        
                        # Set artifactory path
                        netbox_bundle['artifactory_path'] = art_for_vetted
                    else:
                        logger.warning(f"Note: Bundle {netbox_bundle['name']} is present on netbox but not in inventory..")
        
            if found_bundle_to_built:
                logger.info(f"Will proceed to update on netbox")
                logger.info(f"These are the release bundles that we will update on netbox: ")
                pprint.pp(netbox_data['release_bundles'])
                if dry_run_mode == "true":
                    logger.info(f"WE ARE IN DRY RUN MODE !!!")
                    logger.info(f"No actual update will be done")              
                else:
                    my_role.update({"data": netbox_data})
            else:
                logger.error(f"Seems netbox bundle list didn't include {bundle_built}")
                sys.exit(1)
        else:
            logger.error(f"Could not find release_bundles section")
    else:
        logger.error(f"Role '{role}' not found.")
        sys.exit(1)

def setup_netbox_client(n_url,n_token):
    logger = logging.getLogger()
    nb = pynetbox.api(url="https://"+n_url, token=n_token)

    # Check if the nb object was created successfully
    if nb is None:
        raise logger.error(f"Failed to create NetBox API client.")

    session = requests.Session()
    session.verify = False
    nb.http_session = session

    return nb

def get_version_from_inventory(gh,inventory_repo_name_in_gh,branch):
    logger = logging.getLogger()
    newfile_content = None
    version_info =  ""

    # Instantiate GitHub object
    try:
        repo = gh.get_repo(inventory_repo_name_in_gh)
    except Exception as e:
        logger.error(f"Failed to authenticate or get the repository: {e}")
        return ""
    
    #Read he content of the files in the repository
    try:
        contents = repo.get_contents('',ref=branch)
        while contents:
            content = contents.pop(0)
            if content.type == 'dir':
                contents.extend(repo.get_contents(content.path, ref=branch))
            elif content.type == 'file' and content.name.endswith('_image'):

                #Read the file content
                file_content = repo.get_contents(content.path, ref=branch)
                newfile_content = file_content.decoded_content.decode('utf-8')
                break
    except Exception as e:
        logger.error(f"Failed to read files from repository: {e}")
        return ""
    
    #Process the content of the file found
    try:
        if not newfile_content:
            logger.error(f"File not found")
        else:
            content = json.loads(newfile_content)
            artifact_value = content.get('artifact', None)

            if artifact_value:
                start_index = artifact_value.find(':') + 1
                end_index = artifact_value.find('@')
                version_info = artifact_value[start_index:end_index]
            else:
                logger.error(f"The key 'artifact' is not found in the content.")
    except Exception as e:
        logger.error(f"An error occurred while processing the file content: {e}")


    return version_info

def main():

    # Setup logger
    logger = setup_logger()

    try:
        # Parse environment variables
        args = parse_env()

        # Create GH client that will be used later
        gh = Github(login_or_token=args['ghe_api_token'], base_url=args['ghe_api_url'])

        # Set Netbox client
        nb = setup_netbox_client(args['netbox_url'],args['netbox_token'])

        # Split to have a list of roles
        roles_to_process = args['roles_to_get_netbox_bundles_from'].split(" ")

        # Iterate over the roles
        for role in roles_to_process:
            #nb = get_netbox_bundles(args['netbox_url'],args['netbox_token'],rtp)

            update_netbox_data_section(nb,gh,role,args['bundle_name_for_replace_version'],args['version_to_replace'],
                                       args['art_value_to_replace_in_tested_bundle'], args['art_value_to_replace_in_vetted'],
                                       args['inventory_repo_branch'] , 
                                       args['update_netbox_bundles_data_dry_run_mode'])
    except Exception as e:
        logger.error(f"An error occurred: {e}")
        raise


######################### M A I N #############################################
# Entry point for the script
if __name__ == "__main__":
    main()