#!/usr/bin/env python3
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Updates environemnt yaml files in dev-regions
#
# Args:
#    vetted-versions-file: vetted versions file Example: vetted-versions.yaml
#    component: name of the component Example: hostos-base-os-sw-release
#    version: version of component Example: 3.x.yy-20220424T083115Z_aabbccd
#
# Use:
#    python3 update_vetted_versions_for_dev_regions.py vetted-versions-file component version
#

import argparse
import logging
import os
import pathlib
import yaml
import sys
from pathlib import Path


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


def create_arg_parser():
    """ Creates and returns the ArgumentParser object """

    parser = argparse.ArgumentParser(
        description='Update dev-regions environment yaml')
    parser.add_argument('versionFile', help='version file')
    parser.add_argument('component', help='component name')
    parser.add_argument('version', help='new version')
    parser.add_argument('-a','--artifRepo', help='artifactory repo', required=False)
    parser.add_argument('-d','--dmmDeploymentEnabled', help='boolean value to check if DMM deployment is enabled', required=False)

    return parser


def parse_yaml(filename):
    """
    Deserialize yaml file and return python data dict
    """

    logger = logging.getLogger()

    # Check if filename exists before parsing
    if os.path.exists(filename):
        logger.info(f"{filename} file exists.")
        with open(filename) as f:
            data = yaml.safe_load(f)
            logger.info(f"Parsed yaml file {filename}")
    else:
        logger.error(f"{filename} file does not exists.")
        exit(1)

    return data


def update_environment_yaml_files(data, env_yaml_file, component, version, artifRepo, dmmDeploymentEnabled):
    """
    Update environment yaml files with the new component version
    Args:
        data (parsed env file yaml)
    """

    updated_component_with_version = update_component_with_version(
        data, component, version, artifRepo, dmmDeploymentEnabled)

    with open(env_yaml_file, 'w') as fp:
        yaml.dump(
            updated_component_with_version,
            fp,
            default_flow_style=False,
            sort_keys=False)

def update_component_with_version(data, component, version, artifRepo, dmmDeploymentEnabled):
    """
    Updates the component version in the environment file
    If the component does not exist, it will create it
    Args:
        dict (from parsed current environment yaml file)
        component
        version (new component version)
    Returns:
        dict (with new version)
    """
    logger = logging.getLogger()
    do_exist = False

    release_bundles = data['apps']['release_bundles']
    for rb in release_bundles:
        # There are several series of hostos release bundles. e.g. 2.x, 3.x, 4.x, 5.x, 6.x, ....
        # And there are several series of kube release bundles. e.g. 7.x, 8.x, 9.x,...
        # But an environment can only have a few types of hostos, especially only one type of kube.
        # We only care about a component if its type is already in the eyaml.
        #
        # For example:
        # If the eyaml looks like below, and the version of the component is "5.0.8-20221029T087959Z_1bg8669",
        # then "5.0.7-20221027T083954Z_6ba5665" would be replaced by "5.0.8-20221029T087959Z_1bg8669".
        # But if the version of the component is "8.0.8-20221029T087959Z_1bg8669", then nothing would be done.
        #
        # vetted-versions.yaml
        #     ...
        #     - name: hostos-boot-release
        #      runs:
        #       - version: 2.1.0-20201010T175248Z_3bb67d1
        #       - version: 3.0.5-20211229T121113Z_60d5a46
        #       - version: 5.0.7-20221027T083954Z_6ba5665
        #     - name: hostos-base-os-sw-release
        #     ...
        #
        if ("hostos" in component or "kube" in component or "etcd-base-release" in component) and dmmDeploymentEnabled != "true":
            if ("hostos-config" in component and ("hostos-config" in rb["name"] or "hostos-post-config" in rb["name"])) or (
                "hostos-boot" in component and ("hostos-boot" in rb["name"] or "hostos-z-boot" in rb["name"])) or (
                "hostos-config" not in component and rb["name"] == component):
                for run in rb["runs"]:
                    if str(run["version"].split('.')[0]) == str(version.split('.')[0]):
                        do_exist = True
                        # Update version
                        run["version"] = version
                        if artifRepo:
                            run['artifrepo'] = artifRepo
                        break
                    else:
                        pass
        
        elif rb["name"] == component:
            for run in rb["runs"]:
                do_exist = True
                # Update version
                run["version"] = version
                if component == "hostos-config-release":
                    for subentry in data['apps']['release_bundles']:
                        if subentry['name'] == 'hostos-post-config-release':
                            subentry['runs'][0]['version'] = version
                if "hostos" not in component:
                    if artifRepo:
                        run['artifrepo'] = artifRepo
                break

    if not do_exist:
        logger.info(f"{component} with {version} doesn't exist in file")

    return data


def check_file_lock(parsed_yaml):
    """
    Evaluate if there's a property called fileLocked. If there is and it's value is True
    return True else return False
    Args:
        Parsed yaml
    Return:
        Boolean
    """

    isLocked = False
    for k, v in parsed_yaml.items():
        if k == "fileLocked" and v:
            isLocked = True

    return isLocked


def main():
    setup_logger()
    logger = logging.getLogger()

    arg_parser = create_arg_parser()
    parsed_args = arg_parser.parse_args(sys.argv[1:])
    version_file = parsed_args.versionFile
    release_component = parsed_args.component
    release_version = parsed_args.version
    artifactory_repo = parsed_args.artifRepo
    dmm_deployment_enabled = parsed_args.dmmDeploymentEnabled

    logger.info("Updating mzone file...")
    current_environment_file_mzone_data = parse_yaml(version_file)

    if ("hostos" in release_component or "kube" in release_component or "etcd-base-release" in release_component or "smotainer" in release_component or "pds" in release_component) and dmm_deployment_enabled != "true" :
        logger.info(
            f"skipping update of {release_component} for {version_file}")
        return
        
    # Update environment yaml file for component with new version
    logger.info(f"updating {release_component} in {version_file} with version: {release_version}...")
    update_environment_yaml_files(
        current_environment_file_mzone_data,
        version_file,
        release_component,
        release_version,
        artifactory_repo,
        dmm_deployment_enabled
        )

    logger.debug(current_environment_file_mzone_data)


if __name__ == "__main__":
    main()
