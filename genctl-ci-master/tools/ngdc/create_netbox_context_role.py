#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# vpc_elba_zonelet_compute_hostos_debug
############## I M P O R T S ##################################################
import logging
import requests
from requests.exceptions import RequestException
from requests.packages.urllib3.exceptions import InsecureRequestWarning # type: ignore
import os
import pynetbox

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
        'EXISTING_ROLES',
        'TMP_ROLES_SUFFIX'
    ]
    optional_vars = ['CREATE_NETBOX_ROLE_DRY_RUN_MODE','CI_TEMP_DIR']

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

def get_tenant_id(nb, tenant_name):
    tenant_id = nb.tenancy.tenants.get(name=tenant_name)
    if not tenant_id:
        print(f"Failed to find tenant '{tenant_name}'.")
        exit (1)
    return tenant_id.id

def create_role(nb, rolename, role_name_suffix, dry_run_mode):

    # Prepare the new role name
    new_context_name = f"{rolename}{role_name_suffix}"[:99]
    
    #check if the role already exist (For example cases of re-run)
    new_context_exist = nb.extras.config_contexts.get(name=new_context_name)
    if not new_context_exist:

        ci_role = nb.extras.config_contexts.get(name=rolename)
        if ci_role:
            # List of tenant names to add to the context
            tenant_ids = []
            for tenant in ci_role.tenants:
                print(f"Tenant name: {tenant}")
                tenant_ids.append(get_tenant_id(nb, tenant.name))

            # Prepare data for the new context
            new_context_data = {
                'name': new_context_name,
                'weight': ci_role.weight,
                'data': ci_role.data,
                'description': ci_role.description,
                'is_active': ci_role.is_active,
                'tags': ci_role.tags,
                'tenants': tenant_ids
            }

            # Create the new context
            if dry_run_mode == "true":
                print(f"WE ARE IN DRY RUN MODE !!!")
                print(f"No actual update will be done")
                return None
            else:
                print(f"Create new context !!!")
                new_context = nb.extras.config_contexts.create(new_context_data)
                print(f"New context created with ID: {new_context.id}")
                return new_context_name
        else:
            print(f"Context with ID {ci_role} for cloning is not found.")
            return None
    else:
        print(f"Context with ID {new_context_exist} already exists")
        return new_context_name

def main():

    # Setup logger
    logger = setup_logger()

    try:
        # Parse environment variables
        args = parse_env()

        #Set Netbox client
        nb = setup_netbox_client(args['netbox_url'],args['netbox_token'])

        # Split to have a list of roles
        roles_to_process = args['existing_roles'].split(" ")

        # Create an empty list that will hold the list of roles created
        created_roles = []

        # Iterate over the roles and for each one "duplicate"
        for role in roles_to_process:
            rta = create_role(nb, role, args['tmp_roles_suffix'], args['create_netbox_role_dry_run_mode'])
            if rta is not None:
                created_roles.append(rta)

        # If we have the parameter of CI_TEMP_DIR; create a file with the list 
        if args['ci_temp_dir'] != "":
            if created_roles:
                # Open the file for writing
                with open(os.path.join(args['ci_temp_dir'],'created_roles.txt'), 'w') as f:
                    f.write(' '.join(created_roles))

    except Exception as e:
        logger.error(f"An error occurred: {e}")
        raise

######################### M A I N #############################################
# Entry point for the script
if __name__ == "__main__":
    main()