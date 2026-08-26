#!/usr/bin/env python3

# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

import os
import shlex
import subprocess
import sys
import logging
import argparse
import ruamel.yaml as yaml


def run_and_check(cmd):
    logger = logging.getLogger()
    rc = subprocess.call(cmd, stderr=subprocess.PIPE)
    if rc != 0:
        logger.error(f'Failed to execute "{cmd}"')
        sys.exit(1)


def make_ssh_cmd(cmd, ssh_config_params, deploy_server_target):
    ssh_cmd = ['ssh', deploy_server_target, cmd]
    ssh_cmd[1:1] = shlex.split(ssh_config_params)  # insert ssh_config_params
    return ssh_cmd


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
        '-i', '--infile', help="The EYAML configuration input file", required=True, dest="infile")
    parser.add_argument(
        '-sp', '--ssh-params', help="SSH config params", required=True, dest="ssh_params")
    parser.add_argument(
        '-ds', '--deploy-server', help="Deployment server target", required=True, dest="deploy_server")
    parser.add_argument(
        '-a', '--artifactory-docker-url', help="Artifactory docker url (default is prod)", required=True, dest="artifactory_docker_url")
    parser.add_argument(
        '-m', '--mzone-dir', help="Deployer directory to copy the docker artifacts into", required=True, dest="mzone_dir")
    parser.add_argument(
        '-c', '--component', help="The component we are deploying", required=True, dest="component")
    args = parser.parse_args()
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

def main():
    # Setup logger
    logger = set_up_logger()
    args = parse_args()
    data = get_yaml(args.infile)
    ssh_config_params = args.ssh_params
    deploy_server_target = args.deploy_server
    artifactory_docker_prod_url = args.artifactory_docker_url
    mzone_dir = args.mzone_dir

    for release_bundle in data['apps']['release_bundles']:
        bundle_name = release_bundle['name']
        bundle_version = release_bundle['version']
        component = args.component
        search_component = "pds" if args.component == "cloudnet" else args.component
        component = "kube" if args.component == "etcd" else args.component
        if bundle_name.startswith(search_component):
            if bundle_name not in ['hostos-post-config-release', 'hostos-z-boot-release']:
                logger.info(f'Package: {component}/{bundle_name}:{bundle_version}')
                img_file = f'{bundle_name}-{bundle_version}.img'
                docker_image = f'{artifactory_docker_prod_url}/{component}/{bundle_name}:{bundle_version}'
                cmd_image_exist = make_ssh_cmd(f'docker images -q {docker_image}', ssh_config_params, deploy_server_target)
                is_image_exist = subprocess.check_output(cmd_image_exist).decode()
                if is_image_exist != "":
                    logger.info(f'Image {docker_image} already exists on {deploy_server_target}')
                    continue

                cmd_pull_image = [ 'docker', 'pull', docker_image]
                run_and_check(cmd_pull_image)

                cmd_save_image = ['docker', 'save', docker_image,  '-o', img_file ]
                run_and_check(cmd_save_image)

                cmd_rsync_image = ['rsync', '-aq',
                                '-e', f'ssh {ssh_config_params}',
                                os.path.join('./', img_file),
                                f'{deploy_server_target}:{mzone_dir}/']
                run_and_check(cmd_rsync_image)

                cmd_load_image = make_ssh_cmd('cat ' + os.path.join(mzone_dir, img_file) + ' | docker load', ssh_config_params, deploy_server_target)
                run_and_check(cmd_load_image)

                cmd_rm_img = make_ssh_cmd('rm ' + os.path.join(mzone_dir, img_file), ssh_config_params, deploy_server_target)
                subprocess.call(cmd_rm_img, stderr=subprocess.PIPE)


if __name__ == "__main__":
    main()