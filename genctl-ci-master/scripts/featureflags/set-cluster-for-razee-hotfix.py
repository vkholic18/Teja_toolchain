# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

import logging
import os
import re

import yaml
from featureflags import LaunchDarkly, set_value_and_use_in_rule

# Constants
RIAS_CLUSTER_REMOTE_RESOURCE = 'rias-cluster-remote-resource.yaml'
GENCTL_CLUSTER_REMOTE_RESOURCE = 'genctl-cluster-remote-resource.yaml'

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

def load_yaml(file_path):
    with open(file_path) as f:
        dictionary = yaml.safe_load(f)

    return dictionary

def load_yaml_string(yaml_str):
    logger = logging.getLogger()
    try:
        dictionary = yaml.safe_load(yaml_str)
        return dictionary
    except yaml.YAMLError:
        logger.info(f"yaml {yaml_str} is not valid, exiting")
        exit(1)

def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'BASE_ENVIRONMENT_PATH',
        'IBMCLOUD_IKS_CLUSTER_NAME',
        'IBMCLOUD_MZONE_CLUSTER_NAME',
        'LAUNCH_DARKLY_ENVIRONMENT',
        'LAUNCH_DARKLY_FEATURE_FLAG',
        'LAUNCH_DARKLY_DEFAULT_URL',
        'AUTH_TOKEN',
        'BASE_CLUSTER_REMOTE_RESOURCE_PATH'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args

def is_component_ff_in_remote_resource(component, remote_resource):
    logger = logging.getLogger()
    # get the kind: RemoteResource from remote-resource yaml file
    # if both RemoteResourceS3 and RemoteResource exis use the RemoteResource (a second in the strTemplates list)
    if len(remote_resource["spec"]["strTemplates"]) > 1:
        components_templates_str = remote_resource["spec"]["strTemplates"][1]
    else:
        components_templates_str = remote_resource["spec"]["strTemplates"][0]
    if not components_templates_str:
        logger.info("Failed to parse strTemplates from remote resource file")
        exit(1)
    pattern = re.compile('\{\{\s*' + component + '\s*\}\}')
    if pattern.search(components_templates_str):
        logger.info("Feature flag {} exist in an inventory".format(component))
        return True
    else:
        logger.info("Feature flag {} does not exist in an inventory".format(component))
        return False

def main():
    logger = set_up_logger()
    args = parse_env()

    ibmcloud_iks_cluster_name = args['ibmcloud_iks_cluster_name']
    logger.info(f"LD rule tag (aka IKS cluster):  {ibmcloud_iks_cluster_name}")
    ibmcloud_mzone_cluster_name = args['ibmcloud_mzone_cluster_name']
    logger.info(f"LD mzone rule tag (aka genctl cluster):  {ibmcloud_mzone_cluster_name}")
    launch_darkly_environment = args['launch_darkly_environment']
    logger.info(f"LD environment:  {launch_darkly_environment}")
    base_environment = load_yaml(args['base_environment_path'])
    launch_darkly_workspace_feature_flag = args['launch_darkly_feature_flag']
    logger.info(f"LD feature flag for hotfix workspace:  {launch_darkly_workspace_feature_flag}")

    rias_cluster_remote_resource_environment = load_yaml(args['base_cluster_remote_resource_path'] + '/' + RIAS_CLUSTER_REMOTE_RESOURCE)
    genctl_cluster_remote_resource_environment = load_yaml(args['base_cluster_remote_resource_path'] + '/' + GENCTL_CLUSTER_REMOTE_RESOURCE)

    # Create infrastructure for major components
    feature_flags = base_environment["apps"]["feature_flags"]["vpc-ci"]
    for feature_flag in feature_flags:
        ff_name = feature_flag["name"]
        if launch_darkly_workspace_feature_flag == ff_name:
            logger.info(f"Skip updating {launch_darkly_workspace_feature_flag} feature flag. The version will be set up from the HF build")
            continue
        ff_version = feature_flag["default"]["variation_value"]
        logger.info(f"Will be updating feature flag name: {ff_name} with version: {ff_version} for rule_tag: {ibmcloud_iks_cluster_name} ")
        ld = LaunchDarkly(args['launch_darkly_default_url'], ff_name, args['auth_token'])
        if is_component_ff_in_remote_resource(ff_name, rias_cluster_remote_resource_environment) or ff_name == "rias-globals-version" or ff_name == "rias-inception-version":
            logger.info(f"Feature flag {ff_name} is a part of rias cluster remote resource. Set a value for feature flag")
            set_value_and_use_in_rule(ld,ff_version,False,False,"development",ibmcloud_iks_cluster_name)
        else:
            logger.info(f"Feature flag {ff_name} is not a part of rias cluster remote resource. Skip ")

        if is_component_ff_in_remote_resource(ff_name, genctl_cluster_remote_resource_environment) or ff_name == "genctl-globals-version" or ff_name == "rias-inception-version":
            try:
                for rule in feature_flag["rules"]:
                    for clause in rule["clauses"]:
                        if clause["attribute"] == "mzone":
                            ff_version = rule["variation_value"]
                            logger.info(f"Will be updating feature flag name: {ff_name} with version: {ff_version} for mzone rule_tag: {ibmcloud_mzone_cluster_name} ")
                            set_value_and_use_in_rule(ld,ff_version,False,False,"development",ibmcloud_mzone_cluster_name)
            except KeyError:
                logger.error(f"rule attribute is not found for: {ff_name}")
                logger.info(f"Will be updating feature flag name: {ff_name} with version: {ff_version} for rule_tag: {ibmcloud_mzone_cluster_name} ")
                set_value_and_use_in_rule(ld,ff_version,False,False,"development",ibmcloud_mzone_cluster_name)
        else:
            logger.info(f"Feature flag {ff_name} is not a part of genctl cluster remote resource. Skip ")

if __name__ == "__main__":
    main()
