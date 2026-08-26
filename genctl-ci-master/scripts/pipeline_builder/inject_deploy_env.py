# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Injects the deployment environment the deployment task
#
# Env:
#    BUILD_TASK_PATH: path to the build task in genctl-ci or the workspace
#    CONFIG_DIR_PATH: path to the concourse output config directory
#    DEFAULT_LD_RULE_TAG: default deploument rule tag
#    DEFAULT_LD_FEATURE_FLAG: default deploument feature tag
#    WS_PATH: path to the github repository/workspace
#
# Use:
#    python3 inject_build_env.py
#

import json
import logging
import os
import yaml

from pipeline_config import PipelineConfig

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

def build_task_config(user_config, task_path, config_dir_path):
    """
    Modifies the given build task with given user config and rewrites it
    to the filesystem
    Args:
        user_config: build_env config from pipeline.yaml
        task_path: full path to the task
        config_dir_path: path to the output config directory
    """
    logger = logging.getLogger()

    task_name = os.path.basename(task_path)
    logger.info(f"Configuring environment for {task_name}")

    with open(task_path, 'r') as f:
        task = yaml.safe_load(f)

    tag = None
    feature_flag = None
    if user_config:
        feature_flag = user_config['feature_flag']
        logger.info(f"Using user specified LD feature flag, {user_config['feature_flag']}")

        if 'rule_tag' in user_config.keys():
            tag = user_config['rule_tag']
            logger.info(f"Using user specified tag, {user_config['rule_tag']}")

    task['params']['LAUNCH_DARKLY_RULE_TAG'] = tag
    task['params']['LAUNCH_DARKLY_FEATURE_FLAG'] = feature_flag
    logger.info(f"Using user specified LD feature flag: {feature_flag}")
    logger.info(f"Using user specified LD rule tag: {tag}")

    config_file_path = os.path.join(config_dir_path, task_name)
    with open(config_file_path, 'w+') as f:
        yaml.safe_dump(task, f)

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
        'WS_PATH',
        'CONFIG_DIR_PATH',
        'BUILD_TASK_PATH'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args

def main():
    setup_logger()
    args = parse_env()

    pipe_config = PipelineConfig(args['ws_path'])

    build_task_config(
        pipe_config.deployment,
        args['build_task_path'],
        args['config_dir_path']
    )

if __name__ == "__main__":
    main()
