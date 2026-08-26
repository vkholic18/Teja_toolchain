# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

import json
import logging
import os
import subprocess
import sys
import argparse

import ruamel.yaml as yaml


GLOBAL_PROFILE_PATH = "/etc/profile"


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


def parse_args():
    """
    Parse the arguments passed when calling this file.
    """
    parser = argparse.ArgumentParser(
        description="Parser to deploy component using MDS")
    parser.add_argument(
        '-ef', '--eyaml-file', help="The EYAML configuration template file to use on the deployer", required=True, dest="eyaml_file")
    parser.add_argument('-rb', '--release-bundles', action='append', nargs='+')
    parser.add_argument('-te', '--target-eyaml', help="The eyaml file path on the deployer")

    args = parser.parse_args()
    return args


def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'WCP_ARTIFACTORY_USERNAME',
        'CC_ARTIF_ACCESS_TOKEN',
        'GITHUB_API_KEY',
        'GITHUB_API_URL',
        'DAL_VAULT_KEY',
        'IBMCLOUD_ACCOUNT',
        'IBMCLOUD_KEY',
        'MZONE_DIR',
        'BASTION_USERNAME',
        'DEPLOY_SERVER',
        'MZONE_NAME',
        'SSH_CONFIG_PARAMS',
        'VV_REPO_PATH',
        'GENCTL_VETTED_VERSIONS'
    ]

    missing_vars = list()
    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            missing_vars.append(var)

    if missing_vars:
        vars_str = ', '.join(missing_vars)
        logger.error(f"Missing required env variable(s), {vars_str}")
        exit(1)

    return args


def get_yaml(path):
    logger = logging.getLogger()

    try:
        with open(path, 'r') as eyaml:
            content = yaml.safe_load(eyaml)

        return content
    except FileNotFoundError:
        logger.error(f"The eyaml file \"{path}\" does not exist")
        sys.exit(1)
    except yaml.YAMLError as err:
        logger.error("Unable to parse yaml ({}): reason: {}".format(path, err))
        sys.exit(1)
    except:
        logger.error("Unable to open manifest yaml ({}): reason: {}".format(
            path, sys.exc_info()[0]))
        sys.exit(1)


def split_approle(approle_str):
    """
    Splits vault approle into constituent parts: role_id and secret_id
    Args:
        approle_str: String of the approle json
    Returns:
        aprole role_id, aprole secret_id,
    """
    approle = json.loads(approle_str)
    return approle['role_id'], approle['secret_id']


def add_release_bundle_exec(component, eyaml_path):
    logger = logging.getLogger()
    eyaml_content = get_yaml(eyaml_path)
    execution_cmd = ""
    does_exists = False
    if component == "cloudnet":
        component = "pds"
    for bundle in eyaml_content['apps']['release_bundles']:
        name = bundle['name']
        if name.startswith(component):
            does_exists = True
            logger.info(f"adding {name} to bundle deployment")
            execution_cmd += f"--release-bundle={name} "

    return execution_cmd, does_exists


def batch_deploy(args, batch, eyaml, vault_role_id, vault_secret_id, target_eyaml):
    logger = logging.getLogger()

    logger.info(f"Executing {batch} deployment")

    mds_flags = \
        "--test " +\
        "--headless " +\
        "--skip-env-validation " +\
        "--forcereboot " +\
        "--wipe-rias " +\
        "--snowless " +\
        "--secrets-from-env " +\
        "--skip-health-checks "

    execution_cmd, is_executable = add_release_bundle_exec(batch, eyaml)
    if is_executable:
        deploy_cmd = \
            f"source {GLOBAL_PROFILE_PATH}; " +\
            f"cd {args['mzone_dir']}/micro-deploy-server; " +\
            f"MDS_EMAIL={args['wcp_artifactory_username']} " +\
            f"MDS_GITHUB_APIKEY={args['github_api_key']} " +\
            f"MDS_ARTIF_ACCESSTOKEN={args['cc_artif_access_token']} " +\
            f"MDS_VAULT_ROLE_ID={vault_role_id} " +\
            f"MDS_VAULT_SECRET_ID={vault_secret_id} " +\
            f"MDS_IBMCLOUD_ACCOUNT={args['ibmcloud_account']} " +\
            f"MDS_IBMCLOUD_APIKEY={args['ibmcloud_key']} " +\
            f"./mds deploy {mds_flags} {execution_cmd} --eyaml-file={args['mzone_dir']}/micro-deploy-server/{target_eyaml}"

        logger.info(f"Executing MDS with flag(s): {mds_flags} {execution_cmd}")
        exit_code = subprocess.call([
            "ssh",
            *args['ssh_config_params'].split(' '),
            f"{args['bastion_username']}@{args['deploy_server']}",
            deploy_cmd
        ])

        if exit_code != 0:
            logger.error(f"Deployment failed with exit {exit_code}")
            sys.exit(exit_code)
    else:
        logger.info(
            f"Component {batch} was not found in eyaml therefore was not executed")
        sys.exit(0)


def main():
    # Setup logger
    logger = set_up_logger()
    # Setup environemt and CLI args
    env = parse_env()
    args = parse_args()
    for batches in args.release_bundles:
        for batch in batches:
            # Get environment repo for the specific mzone
            vault_role_id, vault_secret_id = split_approle(env['dal_vault_key'])
            batch_deploy(env, batch, args.eyaml_file, vault_role_id, vault_secret_id, args.target_eyaml)


if __name__ == "__main__":
    main()
