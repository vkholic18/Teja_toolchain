# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022, 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Updates environemnt yaml files in dev-regions
#
# Args:
#    feature_flag: name of the feature_flag to update
#....mzone_name: name of the mzone used to derive mzone environment yaml
#....iks_cluser_name: name of the iks_cluster used to derive mzone environment yaml
#....tag: git hash or gittag to use when updating version in environment yaml
#....dev_regions_path: path to dev-regions repo
#
# Use:
#    python3 update_environment.py feature_flag mzone_name iks_cluser_name tag
#

import argparse
import logging
import os
import pathlib
import ruamel.yaml
import datetime
import sys
from pathlib import Path
import glob


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

    parser = argparse.ArgumentParser(description='Update dev-regions environment yaml')
    parser.add_argument('feature_flag', help='feature flag name')
    parser.add_argument('iks_cluster_name', help='Name of iks cluster taken from pipeline.yaml')
    parser.add_argument('tag', help='A tag in either SHA format or semantic format')
    parser.add_argument('dev_regions_path', help='Path to dev regions repo')
    parser.add_argument('rule_tag', help='rule tags name')
    parser.add_argument('additional_target_dev_env', nargs='?', help='additional target dev env name')

    return parser

def get_environment_yaml_names(dev_regions_path, iks_cluster_name, feature_flag, rule_tag, additional_target_dev_env):
    """
    We find the environment yaml names based of the mzone and iks cluster names derived from pipeline yaml, also 
    if additional_target_dev_env is provided, these entries are also considered in identifying the relevant environment yaml files.
    Args:
        dev_regions_path
        iks_cluster_name
        feature_flag
        rule_tag
        additional_target_dev_env
        
    Returns:
        files_to_update : a dict containing all entries of files to be modified
    """

    logger = logging.getLogger()
    rule_tag_list = rule_tag.split(",")
    files_to_update = []
    yaml = ruamel.yaml.YAML(typ='safe', pure=True)
    env_file_path = dev_regions_path + '/' + iks_cluster_name + '/' + iks_cluster_name +'.yaml'
    if os.path.exists(env_file_path):
        files_to_update.append(env_file_path)
    else:
        yaml_files = glob.glob(os.path.join(dev_regions_path, '**/*.yaml'), recursive=True)
        for file in yaml_files:
            if os.path.basename(file).startswith(('rias-ng', 'genctl-ng')):
                with open(file, 'r') as file_content:
                    data = yaml.load(file_content)
                    try:
                        for every in (data['infrastructure']['providers']['ibm_cloud']['resources']['ibm_container_cluster']):
                            if every['name'] == iks_cluster_name:
                                env_file_path = file
                                files_to_update.append(env_file_path)
                                break
                    except TypeError as e:
                        pass
                                
    for every_rule in rule_tag_list:
        if "mzone" in every_rule:
            every_rule = every_rule.strip()
            if every_rule in open(env_file_path).read():
                pass
            else:
                yaml_files = glob.glob(os.path.join(dev_regions_path, '**/*.yaml'), recursive=True)
                for file in yaml_files:
                    if os.path.basename(file).startswith(('rias-ng', 'genctl-ng')):
                        with open(file, 'r') as file_content:
                            data = yaml.load(file_content)
                            try:
                                for every in (data['infrastructure']['providers']['ibm_onprem']['mzones']):
                                    if every['name'] == every_rule:
                                        files_to_update.append(file)
                                        break
                            except TypeError as e:
                                pass

    logger.info(f"dev-regions environment file path: {files_to_update}")

    if additional_target_dev_env is not None:
        for every_dev_env in additional_target_dev_env.split(","):
            files_to_update.append(dev_regions_path + '/' + every_dev_env + '/' + every_dev_env +'.yaml')

    return files_to_update

def parse_yaml(filename):
    """
    Deserialize yaml file and return python data dict
    """

    logger = logging.getLogger()

    # Check if filename exists before parsing
    if os.path.exists(filename):
        logger.info(f"{filename} file exists.")
        with open(filename) as f:
            data = ruamel.yaml.round_trip_load(f)
            logger.info(f"Parsed yaml file {filename}")
    else:
        logger.error(f"{filename} file does not exists.")
        # We expect all the environment yaml files to be present in dev-regions however
        # If not we simply skip and exit 0 for now.
        # Once the feature roll out has happened we'll update this to exit 1
        exit(0)

    return data

def update_feature_flag_version(data, feature_flag, version):
    """
    Updates the feature flag version in the environment file
    If the feature flag does not exist, it will create it
    Args:
        dict (from parsed current environment yaml file)
        feature_flag
        version (new feature flag version)
    Returns:
        dict (with new version)
    """
    logger = logging.getLogger()
    do_exist = False

    # Some of the environment files feature flags are initially set to string "none" in dev-regions
    if data['apps']['feature_flags'] == 'none' or data['apps']['feature_flags'] == None:
      logger.info(f"feature_flag key name is set to none, replacing with new feature flag values...")
      data['apps']['feature_flags'] = {'vpc-ci': [{'name': feature_flag, 'default': {'variation_value': version}}]}
      do_exist = True
    elif data['apps']['feature_flags']['vpc-ci'] == 'none' or data['apps']['feature_flags']['vpc-ci'] == None:
      logger.info(f"vpc-ci key name is set to none, replacing with new feature flag values...")
      data['apps']['feature_flags']['vpc-ci'] = [{'name': feature_flag, 'default': {'variation_value': version}}]
      do_exist = True
    else:
      feature_flags = data['apps']['feature_flags']['vpc-ci']
      # iterate through list of arrays
      for ff in feature_flags:
          if "name" in ff:
            if ff["name"] == feature_flag:
              do_exist = True
              # Update version
              ff["default"]["variation_value"] = version

    # Add missing feature flag if it doesn't already exist
    if do_exist == False:
        logger.info(f"{feature_flag} doesn' exist in file, creating...")
        new_feature_flag = {'name': feature_flag, 'default': {'variation_value': version}}
        feature_flags.append(new_feature_flag)

    return data

def update_environment_yaml_files(data, env_file_path, feature_flag, version):
    """
    Update environment yaml files with the new feature flag version
    Args:
        data (parsed env file yaml)
    """

    updated_feature_flags = update_feature_flag_version(data, feature_flag, version)

    with open(env_file_path, 'w') as fp:
        ruamel.yaml.dump(updated_feature_flags, fp, Dumper=ruamel.yaml.RoundTripDumper)

def update_locked_environment_yaml_files(data, env_file_path, feature_flag, version):
    """
    Add the feature flag version in the corersponding comment in the locked environment file
    If both feature flag and comment does not exist, it will create a separte comment
    Args:
        dict (from parsed current environment yaml file)
        feature_flag
        version (new feature flag version)
    Returns:
        dict (with new version)
    """

    logger = logging.getLogger()

    update_time = datetime.datetime.now().isoformat(timespec='minutes') 

    do_exist = False

    try:
        for ff in data['apps']['feature_flags']['vpc-ci']:
            if ff['name'] == feature_flag:
                logger.info(f"Feature flag {feature_flag} is found and EOL comment is added")
                do_exist = True
                ff['default'].yaml_add_eol_comment(f'{version} at {update_time} when locked', 'variation_value')
    except Exception as e:
        # ruamel.yaml can add a comment under 'vpc-ci' correctly only if it is a list and has more than 1 item
        logger.info(f"Unsupport format: 'vpc-ci' needs to be a list and has more than 1 item: {e}")
        return data

    if do_exist == False:
        print(f"Searching feature flag {feature_flag} in comments")

        ff_in_comments = False

        try:
            logger.debug(data['apps']['feature_flags']['vpc-ci'].ca)
            for ct in data['apps']['feature_flags']['vpc-ci'].ca.items[0][1]:
                if feature_flag in ct.value:
                    ff_in_comments = True
                    ct.value = f'# {feature_flag}: {version} at {update_time}\n'
                    logger.info(f"Feature flag {feature_flag} is found in comments and updated")
                    break
        except Exception as e:
            logger.info(f"Unsupport format: comments under 'vpc-ci' is invalid: {e}")

        if ff_in_comments == False:
            logger.info(f"Add new comment for feature flag {feature_flag}")
            try:
                data['apps']['feature_flags']['vpc-ci'].yaml_set_start_comment(f'{feature_flag}: {version} at {update_time}', indent=4)
            except Exception as e:
                logger.error(f"Add record for feature flag {feature_flag} failed: {e}")

    with open(env_file_path, 'w') as of:
        ruamel.yaml.dump(data, of, Dumper=ruamel.yaml.RoundTripDumper)


def check_file_lock(parsed_yaml):
    """
    Evaluate if there's a property called update_from_ci_pipeline. If there is and it's value is False
    return True else return False
    Args:
        Parsed yaml
    Return:
        Boolean
    """

    isLocked = False
    for k,v in parsed_yaml.items():
        if k == "update_from_ci_pipeline" and v == False:
            isLocked = True

    return isLocked

def main():
    setup_logger()
    logger = logging.getLogger()

    arg_parser = create_arg_parser()
    parsed_args = arg_parser.parse_args(sys.argv[1:])

    feature_flag = parsed_args.feature_flag
    iks_cluster_name = parsed_args.iks_cluster_name
    version = parsed_args.tag
    dev_regions_path = parsed_args.dev_regions_path
    rule_tag = parsed_args.rule_tag
    additional_target_dev_env = parsed_args.additional_target_dev_env

    env_files_path = get_environment_yaml_names(dev_regions_path, iks_cluster_name, feature_flag, rule_tag, additional_target_dev_env)

    for every_file in env_files_path:
        # Update env file in dev-regions
        logger.info("Updating dev-regions environment yaml file...")
        env_file_data = parse_yaml(every_file)

        #If environment yaml in dev-regions is not locked, update environment yaml file with new feature flag version
        if not check_file_lock(env_file_data):
            logger.info(f"{every_file} not locked, updating {feature_flag} with version: {version}...")
            update_environment_yaml_files(env_file_data, every_file, feature_flag, version)
        else:
            logger.info(f"{every_file} locked, updating {feature_flag} with version: {version} in comments...")
            update_locked_environment_yaml_files(env_file_data, every_file, feature_flag, version)

if __name__ == "__main__":
    main()
