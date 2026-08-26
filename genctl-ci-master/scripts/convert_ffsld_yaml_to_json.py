#!/usr/bin/env python3

##
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
##

# This script converts the yaml ffsld into json that mimics the LD response

# Use:
#    python3 scripts/convert_ffsld_yaml_to_json.py -f <PATH_OF_FFSLD_FILE>


import yaml
import json
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

def main():
    """
    Main function
    """
    logger = setup_logger()

    parser = argparse.ArgumentParser(
        description="convert FFSLD files"
    )

    # global flags
    parser.add_argument('-f', '--file-path', help='path to ffsld file', required=True, dest="file_path")
    args = parser.parse_args()

    logger.info("FFSLd file being processed : " + args.file_path)

    data=yaml.safe_load(open(args.file_path)); 
    json.dump({k:v for k,v in data['data'].items() if 'version' in k}, 
              open('desired_deployment_versions.json', 'w'), 
              indent=4)

if __name__ == "__main__":
    main()
