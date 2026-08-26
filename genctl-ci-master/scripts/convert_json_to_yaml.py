#! /usr/bin/env python3
## ==============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2025
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## ==============================================================================================

## This script is used to convert json file to yaml.

## Usage: python3 convert_json_to_yaml.py -i input_json_file.json -o output_ysml_file.yaml

import yaml,json
import logging
import argparse

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

    return logger


def convert_json_to_yaml(json_file, yaml_file):
    """
    Convert a JSON file to YAML.

    Args:
        json_file (str): Path to the input JSON file.
        yaml_file (str): Path to the output YAML file.
    """
    try:
        with open(json_file, 'r') as f:
            data = json.load(f)
        
        with open(yaml_file, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False)
    
    except FileNotFoundError:
        logger.info(f"Error: {json_file} not found")
    
    except json.JSONDecodeError as e:
        logger.info(f"Error: Invalid JSON in {json_file} - {e}")

def main():
    """
    Main function
    """

    parser = argparse.ArgumentParser(
        description="convert FFSLD files"
    )

    # global flags
    parser.add_argument('-i', '--file-input-path', help='path to input json file', required=True, dest="input_path")
    parser.add_argument('-o', '--file-output-path', help='path to output yaml file', required=True, dest="output_path")
    args = parser.parse_args()

    convert_json_to_yaml(args.input_path, args.output_path)
    

if __name__ == "__main__":
    logger = setup_logger()
    main()
