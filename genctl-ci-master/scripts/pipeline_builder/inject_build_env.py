# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Injects the build environment docker image into the build task
#
# Env:
#    BUILD_TASK_PATH: path to the build task in genctl-ci or the workspace
#    CONFIG_DIR_PATH: path to the concourse output config directory
#    DEFAULT_IMAGE_PATH: path to the default docker image
#    DEFAULT_IMAGE_TAG: tag of the default docker image
#    DEFAULT_TRAVIS_IMAGE_PATH: (optional) path to default image for travis
#    DEFAULT_TRAVIS_IMAGE_TAG: (optional) tag of default image for travis
#    DOCKER_URL: url of the docker repository
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

# Constants
ARTI_BUILD_ENVS_PATH = 'build-envs'
ARTI_USERNAME_VAULT_KEY = '((wcp-genctl-docker-local-artifactory-username))'
ARTI_PASSWORD_VAULT_KEY = '((wcp-genctl-docker-local-artifactory-token))'

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

def build_task_config(user_config, task_path, config_dir_path,
    docker_url, default_image_path, default_image_tag,
    default_travis_image_path, default_travis_image_tag,use_custom_tag):
    """
    Modifies the given build task with given user config and rewrites it
    to the filesystem
    Args:
        user_config: build_env config from pipeline.yaml
        task_path: full path to the task
        config_dir_path: path to the output config directory
        docker_url: url of the docker repository
        default_image_path: path to the default docker image
        default_image_tag: tag of the default docker image
    """
    logger = logging.getLogger()

    task_name = os.path.basename(task_path)
    logger.info(f"Configuring environment for {task_name}:{task_path}:{user_config}:{config_dir_path}")

    with open(task_path, 'r') as f:
        task = yaml.safe_load(f)

    image_resource = {
        'type': 'docker-image',
        'source': {
            'username': ARTI_USERNAME_VAULT_KEY,
            'password': ARTI_PASSWORD_VAULT_KEY
        }
    }

    image_path = None
    ignoremultiarch = False
    customtag = None
    tag = None
    # if there is some other tag that needs to be used to inject build env than the standard tag passed in hack/ci/pipeline.yaml, added custom tag
    if user_config:
        if 'tag' in user_config.keys():
            logger.info(f"Using user specified tag, {user_config['tag']}")
            tag = travis_tag = user_config['tag']

        if use_custom_tag:
            if 'customtag' in user_config.keys():
                logger.info(f"Using user specified tag, {user_config['customtag']}")
                customtag = user_config['customtag']
                tag = travis_tag = customtag
            if 'ignoremultiarch' in user_config.keys():
                logger.info(f"Using user specified tag, {user_config['ignoremultiarch']}")
                ignoremultiarch = user_config['ignoremultiarch']
        if 'image' in user_config.keys():
            logger.info(f"Using user specified image, {user_config['image']}")
            image_path = travis_image_path = os.path.join(
                ARTI_BUILD_ENVS_PATH, user_config['image'])

    else:
        logger.info(f"Using default tag")
        tag = default_image_tag
        travis_tag = default_travis_image_tag

    if not image_path:
        logger.info(f"Using default image")
        image_path = default_image_path
        travis_image_path = default_travis_image_path
    logger.info(f"Using environment: {image_path}:{tag}")

    # TODO: stop adding -amd64 when Concourse supports multi-arch manifests
    if not use_custom_tag and not ignoremultiarch :
        if not str(tag).endswith('-amd64') :
            tag = f"{tag}-amd64"

    image_resource['source']['tag'] = tag
    image_resource['source']['repository'] = os.path.join(
        docker_url, image_path)
    task['image_resource'] = image_resource

    if default_travis_image_path:
        logger.info(f"Setting CC_GO_IMAGE_PATH={travis_image_path}, " +\
            f"CC_GO_IMAGE_TAG={travis_tag}")

        if 'params' not in task.keys():
            task['params'] = dict()
        task['params']['CC_GO_IMAGE_PATH'] = travis_image_path
        task['params']['CC_GO_IMAGE_TAG'] = travis_tag

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
        'DOCKER_URL',
        'DEFAULT_IMAGE_PATH',
        'DEFAULT_IMAGE_TAG',
        'BUILD_TASK_PATH'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    # Optional Vars
    optional_vars = [
        'DEFAULT_TRAVIS_IMAGE_PATH',
        'DEFAULT_TRAVIS_IMAGE_TAG',
        'CONFIG_NAME_FOR_OTHER_REPO',
        'USE_CUSTOM_TAG',
    ]

    for var in optional_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            args[var.lower()] = None

    return args

def main():
    setup_logger()
    args = parse_env()
    if args['config_name_for_other_repo']:
        pipe_config = PipelineConfig(args['config_name_for_other_repo'])
    else:
        pipe_config = PipelineConfig(args['ws_path'])

    build_task_config(
        pipe_config.environment,
        args['build_task_path'],
        args['config_dir_path'],
        args['docker_url'],
        args['default_image_path'],
        args['default_image_tag'],
        args['default_travis_image_path'],
        args['default_travis_image_tag'],
        args['use_custom_tag'],

    )

if __name__ == "__main__":
    main()
