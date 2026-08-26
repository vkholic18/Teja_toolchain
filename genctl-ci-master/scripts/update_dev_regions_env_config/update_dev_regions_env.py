# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Updates environemnt yaml files in dev-regions
#
# Args:
#    feature_flag: name of the feature_flag to update
#    dev_regions_file_path: path to dev-regions file
#
# Use:
#    python3 scripts/update_dev_regions_env.py feature_flag dev_regions_file_path
#

import argparse
from ruamel.yaml import YAML

def parse_args():
    parser = argparse.ArgumentParser(description='Remove shared FF entries from YAML file')
    parser.add_argument('feature_flag', help='feature flag name to retain in the yaml')
    parser.add_argument('dev_regions_file_path', help='path to env file from dev-regions')
    return parser.parse_args()

def load_yaml(dev_regions_file_path):
    yaml = YAML()
    with open(dev_regions_file_path, 'r') as file:
        return yaml.load(file)

def remove_flags(data, feature_flag):
    # Check that the expected keys exist in the YAML structure
    if ('apps' in data and
            'feature_flags' in data['apps'] and
            'vpc-ci' in data['apps']['feature_flags']):
        # Retain only the flag with the matching name
        data['apps']['feature_flags']['vpc-ci'] = [
            flag for flag in data['apps']['feature_flags']['vpc-ci']
            if flag.get('name') == feature_flag
        ]
    else:
        print("Expected structure not found in YAML file.")
    return data

def save_yaml(data, dev_regions_file_path):
    yaml = YAML()
    yaml.indent(mapping=4, sequence=4, offset=2)
    with open(dev_regions_file_path, 'w') as file:
        yaml.dump(data, file)

def main():
    args = parse_args()
    feature_flag = args.feature_flag
    dev_regions_file_path = args.dev_regions_file_path
    print(f"Loading YAML file from: {dev_regions_file_path}")
    data = load_yaml(dev_regions_file_path)
    print(f"Keep only feature flag: {feature_flag}")
    data = remove_flags(data, feature_flag)
    print(f"Save updated YAML file back to: {dev_regions_file_path}")
    save_yaml(data, dev_regions_file_path)

if __name__ == '__main__':
    main()
