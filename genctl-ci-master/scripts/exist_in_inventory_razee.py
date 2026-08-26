# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# Description:
#     Search if the component exist in the genesis-deploy-artifacts inventory
#     if exist return 0;

#
# Arguments:
#      $1: component name
#      $2: inventory file in genesis-deploy-artifacts e.g /hack/deploy/razee/genctl-cluster-remote-resource.yaml



import logging
import sys
import re

import yaml

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

def is_component_in_remote_resource(component, remote_resource):
    logger = logging.getLogger()

    # get the kind: RemoteResource from remote-resource yaml file
    # if both RemoteResourceS3 and RemoteResource exis use the RemoteResource (a second in the strTemplates list)
    if len(remote_resource["spec"]["strTemplates"]) > 1:
        components_templates_str = remote_resource["spec"]["strTemplates"][1]
    else:
        components_templates_str = remote_resource["spec"]["strTemplates"][0]
    if not components_templates_str:
        logger.info("Failed to parse strTemplates from remote resource file")
        sys.exit(1)
    pattern = re.compile('{{{ cos-bucket-name }}}/' + component + '/')
    if pattern.search(components_templates_str):
        logger.info("Component {} exist in an inventory".format(component))
        return True
    else:
        logger.info("Component {} does not exist in an inventory".format(component))
        return False

def main():
    logger = set_up_logger()
    component = sys.argv[1]
    infile  = sys.argv[2]

    remote_resource = load_yaml(infile)
    if is_component_in_remote_resource(component, remote_resource):
        logger.info("Component {} exist in an inventory".format(component))
        sys.exit(0)
    else:
        logger.info("Component {} does not exist in an inventory".format(component))
        sys.exit(100)

if __name__ == "__main__":
    main()
