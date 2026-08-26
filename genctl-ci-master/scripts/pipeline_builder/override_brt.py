# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# Description:
#   The script replaces functional_tests configuration from hack/ci/pipeline.yaml
#   with a functional_tests defined in a hot fix configuration. This way the test suite
#   can be overridden in a hot fix pipeline


# Env:
#    WS_PATH: workspace root path
#    HOTFIX_FUNCTIONAL_TESTS: functional_tests defined in a HF configuration file
#
# Use:
#    python3 override_brt.py


import logging
import os

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

def load_yaml_string(yaml_str):
    logger = logging.getLogger()
    try:
        dictionary = yaml.safe_load(yaml_str)
        return dictionary
    except yaml.YAMLError:
        logger.info(f"yaml {yaml_str} is not valid, exiting")
        exit(1)

def save_yaml(file_path, yaml_dict):
    with open(file_path, 'w') as outfile:
        yaml.dump(yaml_dict, outfile, sort_keys=False)

def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'WS_PATH',
        'HOTFIX_FUNCTIONAL_TESTS'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args

def main():
    logger = set_up_logger()
    args = parse_env()

    infile = args['ws_path'] + "/hack/ci/pipeline.yaml"
    pipeline_environment = load_yaml(infile)
    override_brt_dict = load_yaml_string(args['hotfix_functional_tests'])
    pipeline_environment['functional_tests'] = override_brt_dict
    save_yaml(infile, pipeline_environment)

    print(pipeline_environment)

if __name__ == "__main__":
    main()
