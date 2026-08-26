#!/usr/bin/env python3

# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

import hjson
import os
import shlex
import subprocess
import sys


def run_and_check(cmd):
    rc = subprocess.call(cmd, stderr=subprocess.PIPE)
    if rc != 0:
        print(f'Failed to execute "{cmd}"')
        sys.exit(1)


def make_ssh_cmd(cmd, ssh_config_params):
    ssh_cmd = ['ssh', deploy_server_target, cmd]
    ssh_cmd[1:1] = shlex.split(ssh_config_params)  # insert ssh_config_params
    return ssh_cmd


infile = sys.argv[1]
ssh_config_params = sys.argv[2]
deploy_server_target = sys.argv[3]
artifactory_docker_prod_url = sys.argv[4]
mzone_dir = sys.argv[5]

with open(infile) as orig_file:
    data = hjson.load(orig_file)

for comp, comp_data in data['components'].items():
    for pkg, pkg_data in comp_data['packages'].items():
        if pkg not in ['hostos-post-config-release', 'hostos-z-boot-release']:
            print(f'Package: {comp}/{pkg}:{pkg_data["tag"]}')
            img_file = f'{pkg}-{pkg_data["tag"]}.img'
            docker_image = f'{artifactory_docker_prod_url}/{comp}/{pkg}:{pkg_data["tag"]}'

            cmd_image_exist = make_ssh_cmd(f'docker images -q {docker_image}', ssh_config_params)
            is_image_exist = subprocess.check_output(cmd_image_exist).decode()
            if is_image_exist != "":
                print(f'Image {docker_image} already exists on {deploy_server_target}')
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

            cmd_load_image = make_ssh_cmd('cat ' + os.path.join(mzone_dir, img_file) + ' | docker load', ssh_config_params)
            run_and_check(cmd_load_image)

            cmd_rm_img = make_ssh_cmd('rm ' + os.path.join(mzone_dir, img_file), ssh_config_params)
            subprocess.call(cmd_rm_img, stderr=subprocess.PIPE)
