#!/usr/bin/env python3
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Updates environemnt yaml files in dev-regions with the latest versions from vetted file
#
# Args:
#    vettedFile: vetted versions file path, Example: vetted-versions.yaml
#    envFile: envFile file path , Example: rias-ng-us-south-dal-dev24-etcd/rias-ng-us-south-dal-dev24-etcd.yaml
#    update_type: one of ('update_all', 'update_only_high_level_rb')
#
# Use:
#    python3 update_dmm_env_from_vetted_versions.py vettedFile envFile update_type
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
        description='Update dev-regions environment yaml with versions from vetted')
    parser.add_argument('vettedFile', help='path to vetted version file')
    parser.add_argument('envFile', help='path to env file from dev-regions')
    parser.add_argument('update_type', help='update type')
    parser.add_argument('vetted_version_replacement_file', nargs='?', type=str, help='pr pipeline basebranch that corressponds to hostos version')
    parser.add_argument('pipeline_yaml_file_path', nargs='?', type=str, help='Optional attribute that points to the path of pipeline.yaml file.')
    parser.add_argument('pre_int_replacement_file', nargs='?', type=str, help='path to pre int replacement file')

    return parser


def update_intermediate_file(final_file, intermediate_file, update_mode):
    with open(final_file, 'r') as f:
        final_data = yaml.safe_load(f)

    with open(intermediate_file, 'r') as f:
        intermediate_data = yaml.safe_load(f)

    for bundle in intermediate_data['apps']['release_bundles']:
        for final_bundle in final_data['apps']['release_bundles']:
            if bundle['name'] == final_bundle['name']:
                if update_mode == 'update_all' or bundle['name'] in ["rias-release", "rias-etcd-release", "genctl-release"]:
                    if bundle['name'] in ["rias-release", "rias-etcd-release", "genctl-release"]:
                        if 'runs' not in bundle:
                            bundle['runs'] = [{'version': final_bundle['runs'][0]['version']}]
                        else:
                            bundle['runs'][0]['version'] = final_bundle['runs'][0]['version']
                    else:
                        if 'hostos' in bundle['name']:
                            for run in bundle['runs']:
                                for final_run in final_bundle['runs']:
                                    if str(final_run['version']).startswith('6.'):
                                        run['version'] = final_run['version']
                                        break
                        else:
                            version_prefix = '17'
                            matching_versions = [v for v in final_bundle['runs'] 
                                                    if isinstance(v['version'], str) 
                                                    and v['version'].startswith(version_prefix)]
                            if matching_versions:
                                if 'runs' not in bundle:
                                    bundle['runs'] = [{'version': matching_versions[0]['version']}]
                                else:
                                    if not bundle['runs']:
                                        bundle['runs'].append({'version': matching_versions[0]['version']})
                                    else:
                                        bundle['runs'][0]['version'] = matching_versions[0]['version']
                            else:
                                print(f"Warning: No matching version found for {bundle['name']}")


        # Remove artifrepo field
        if 'runs' in bundle:
            if 'artifrepo' in bundle['runs'][0]:
                del bundle['runs'][0]['artifrepo']

    with open(intermediate_file, 'w') as f:
        yaml.dump(intermediate_data, f, default_flow_style=False, sort_keys=False)

def update_intermediate_file_component_only(final_file, intermediate_file, update_mode, vetted_version_replacement_file, pipeline_yaml_file_path, pre_int_replacement_file):

    with open(pre_int_replacement_file, 'r') as f:
        pre_int_replacement_file_data = yaml.safe_load(f)
    
    with open(intermediate_file, 'r') as f:
        intermediate_data = yaml.safe_load(f)

    with open(vetted_version_replacement_file, 'r') as f:
        vetted_version_replacement_file_data = yaml.safe_load(f)

    with open(pipeline_yaml_file_path, 'r') as f:
        pipeline_yaml_file_path = yaml.safe_load(f)

    intermediate_data['apps']['release_bundles'] = pipeline_yaml_file_path['dmm_deployment']['bundles_to_deploy']['release_bundles']

    for entry in intermediate_data['apps']['release_bundles']:
        if 'runs' in entry:
            if entry['name'] not in vetted_version_replacement_file_data['version']:
                if entry['name'] == "hostos-post-config-release":
                    entry['runs'][0]['version'] = vetted_version_replacement_file_data['version'].get("hostos-config-release")
                # elif entry['name'] not in vetted_version_replacement_file_data['version']:
                else:
                    entry['runs'][0]['version'] = pre_int_replacement_file_data['version'].get(entry['name'])
            else:
                for every in vetted_version_replacement_file_data['version']:
                    version_to_update = vetted_version_replacement_file_data['version'].get(every)
                    if entry['name'] == every:
                        entry['runs'][0]['version'] = version_to_update

    with open(intermediate_file, 'w') as f:
        yaml.dump(intermediate_data, f, default_flow_style=False, sort_keys=False)

def main():
    setup_logger()
    logger = logging.getLogger()

    arg_parser = create_arg_parser()
    parsed_args = arg_parser.parse_args(sys.argv[1:])
    vettedFile = parsed_args.vettedFile
    envFile = parsed_args.envFile
    update_type = parsed_args.update_type
    vetted_version_replacement_file = parsed_args.vetted_version_replacement_file
    pipeline_yaml_file_path = parsed_args.pipeline_yaml_file_path
    pre_int_replacement_file = parsed_args.pre_int_replacement_file

    if update_type not in ['update_all', 'update_only_high_level_rb', 'only_hostos']:
        print("Invalid update_type. Please use 'update_all', 'update_only_high_level_rb' or 'only_hostos'.")
        sys.exit(1)

    if parsed_args.vetted_version_replacement_file:
        update_intermediate_file_component_only(vettedFile, envFile, update_type, vetted_version_replacement_file, pipeline_yaml_file_path, pre_int_replacement_file)
    else:
        update_intermediate_file(vettedFile, envFile, update_type)


if __name__ == "__main__":
    main()
