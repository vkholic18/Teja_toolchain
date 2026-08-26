#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
############## I M P O R T S ##################################################
import logging
import requests
import os
import pynetbox


# Suppress only the single InsecureRequestWarning from urllib3 needed
#requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

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
        'ROLES_TO_DELETE'
    ]
    optional_vars = ['COPY_NETBOX_ROLE_DRY_RUN_MODE']

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

def delete_role(nb, rolename, dry_run_mode):

    #check if the role already exist
    rtd = nb.extras.config_contexts.get(name=rolename)
    if rtd:
        # Create the new context
        if dry_run_mode == "true":
            print(f"WE ARE IN DRY RUN MODE !!!")
            print(f"No actual delete will be done")
        else:
            print(f"Delete context !!!")
            success = rtd.delete()
            if success:
                print(f"Configuration context '{rtd}' deleted successfully.")
            else:
                print(f"Failed to delete configuration context '{rtd}'.")
    else:
        print(f"Context with ID {rtd} does not exist. Exiting ...")

def main():

    # Setup logger
    logger = setup_logger()

    try:
        # Parse environment variables
        args = parse_env()

        #Set Netbox client
        nb = setup_netbox_client(args['netbox_url'],args['netbox_token'])

        # Split to have a list of roles
        rtd = args['roles_to_delete'].split(" ")

        # Iterate over the roles
        for role in rtd:
            delete_role(nb, role, args['copy_netbox_role_dry_run_mode'])
    except Exception as e:
        logger.error(f"An error occurred: {e}")
        raise

######################### M A I N #############################################
# Entry point for the script
if __name__ == "__main__":
    main()