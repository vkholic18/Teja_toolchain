# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Validates globals against cluster
#
#
#
# Env:
#    ROOT_DIRECTORY_TO_FIND_YAML: The root directory from where to start to recursively search YAML files
#    CLUSTER_TYPE: The type of cluster (genctl/rias)
# Use:
#    python3 global_keys_check.py

import json
import logging
import os
import subprocess
import sys
import yaml

from ci_python_tools import general_tools


# mapping of namespace and its global names
globals_configmap_by_namespace = {
    'rias': 'region-globals',
    'genctl': 'genctl-globals'
}

def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    args = dict()

    required_vars = [
        'ROOT_DIRECTORY_TO_FIND_YAML',
        'CLUSTER_TYPE'
    ]

    args = general_tools.parse_env(required_vars)

    return args

def yaml_should_be_processed(data):
    if data and 'kind' in data:
        return data['kind'] == 'MustacheTemplate' and 'spec' in data and 'env' in data['spec']

def get_namespace(data,configmap_key_ref):
    if 'namespace' in configmap_key_ref:
        namespace = configmap_key_ref['namespace']
    else:
        namespace = data['metadata']['namespace']
    return namespace

def get_configmap_data(namespace, configmap):
    cmd = f'kubectl get cm {configmap} -n {namespace} -o jsonpath={{.data}}'
    print(cmd)
    cmdExec = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE)
    return json.loads(cmdExec.stdout)

def main():
    # Define logger and parse environment vars
    logger = general_tools.set_up_logger(logging.INFO)
    args = parse_env()

    # Assume as default that check is OK
    error = False

    # Initialize an empty set to hold the already checked
    already_checked = set()

    for root, directories, filenames in os.walk(args['root_directory_to_find_yaml']):
        for filename in filenames:
            path_to_file = os.path.join(root, filename)
            if path_to_file.endswith(".yaml"):
                try:
                    # Load the content of the YAML file
                    with open(path_to_file, "r") as stream:
                        try:
                            data = yaml.safe_load_all(stream)
                        except yaml.YAMLError as exc:
                            logger.error(f"{exc}")

                        logger.info(f"Will process file {path_to_file}")

                        # This index is used just for logging purposes
                        data_part_number = 1

                        # This supports a YAML file with multiple YAML documents in it
                        for data_part in data:
                            logger.info(f"Processing document {data_part_number} in file {path_to_file}")

                            # First, verify that the YAML document is relevant for this check
                            if yaml_should_be_processed(data_part):

                                # Get the envs
                                envs = data_part['spec']['env']

                                # Iterate over the envs
                                for env in envs:

                                    # If its optional skip it
                                    if 'optional' in env and env['optional']:
                                        continue
                                    else:
                                        # Check for config map key reference exists
                                        if 'valueFrom' in env and 'configMapKeyRef' in env['valueFrom']:
                                            configmap_key_ref = env['valueFrom']['configMapKeyRef']

                                            # Get the namespace
                                            namespace = get_namespace(data_part,configmap_key_ref)

                                            # First, verify if is a valid namespace and matches the current cluster we are validating
                                            if namespace in globals_configmap_by_namespace and namespace == args['cluster_type']:

                                                # Some additional verifications
                                                if configmap_key_ref['name'] == globals_configmap_by_namespace[namespace] and configmap_key_ref['key'] not in already_checked:
                                                    # Process
                                                    logger.info(f"File path: {path_to_file}")
                                                    key = configmap_key_ref['key']

                                                    # Add to the already checked
                                                    already_checked.add(key)

                                                    data = get_configmap_data(namespace, configmap_key_ref['name'])

                                                    # If key does not exist, error
                                                    if key not in data:
                                                        logger.info(f"{key} does not exist")
                                                        error = True
                            else:
                                logger.info(f"document {data_part_number} in file {path_to_file} is not relevant")

                            data_part_number = data_part_number + 1
                except Exception as e:
                    logger.error(f"Error occurred: {e}")
                    sys.exit(1)

    if error:
        print("globals key check error occurs")
        sys.exit(1)


if __name__ == "__main__":
    main()
