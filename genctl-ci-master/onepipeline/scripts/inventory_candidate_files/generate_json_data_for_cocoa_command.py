# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Generates a .SH script with the relevant inventory add commands

# Env:
#    PATH_TO_INVENTORY_JSON_FILE: The path to the inventory JSON file we downloaded
#    PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND: The path were the resulting JSON file will be generated
#    VERSION_FIELD_VALUE: The value to put in version field

# Optional

#    PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND_SPECIAL_DEBIAN: Path where the additional JSON file needs to be created only for debians
#    SKIP_ICR_IMAGES_FOR_INVENTORY_UPDATE: Boolean indicating if discard the ICR images for the purpose of updates

# Use:
#    python3 generate_json_data_for_cocoa_command.py.py

from ci_python_tools import general_tools
import json
import logging
import os
import sys


def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'PATH_TO_INVENTORY_JSON_FILE', 
        'PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND' ,
        'VERSION_FIELD_VALUE'
    ]

    args = general_tools.parse_env(required_vars)

    # Deal with the optional

    if 'PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND_SPECIAL_DEBIAN' in os.environ.keys() and not os.environ['PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND_SPECIAL_DEBIAN'] == '':
        args['path_to_json_inventory_file_for_cocoa_command_special_debian'] = os.environ['PATH_TO_JSON_INVENTORY_FILE_FOR_COCOA_COMMAND_SPECIAL_DEBIAN']
    
    if 'SKIP_ICR_IMAGES_FOR_INVENTORY_UPDATE' in os.environ.keys() and not os.environ['SKIP_ICR_IMAGES_FOR_INVENTORY_UPDATE'] == '':
        args['skip_icr_images_for_inventory_update'] = os.environ['SKIP_ICR_IMAGES_FOR_INVENTORY_UPDATE']

    return args

def main():
    # Define logger and parse environment vars
    logger = general_tools.set_up_logger(logging.INFO)
    args = parse_env()

    # Load
    with open(args['path_to_inventory_json_file'], 'r') as f:
        inventory_data = json.load(f)

    if 'path_to_json_inventory_file_for_cocoa_command_special_debian' in args:
        special_debian_artifacts = []

    # Get the artifacts
    artifacts_original = inventory_data['artifacts']

    # Discard ICR images if needed
    if 'skip_icr_images_for_inventory_update' in args and args['skip_icr_images_for_inventory_update'] == "true":
        artifacts_after_icr_processing = [art for art in artifacts_original if '_FOR_ICR' not in art['name']]
    else:
        artifacts_after_icr_processing = artifacts_original
        

    # Loop over the artifacts and add missing fields
    for art in artifacts_after_icr_processing:
        art['version'] = args['version_field_value']
        art['repository-url'] = inventory_data['commons']['repository_url']
        art['commit-sha'] = inventory_data['commons']['commit_sha']
        art['pipeline-run-id'] = inventory_data['commons']['pipeline_run_id']
        art['build-number'] = inventory_data['commons']['build_number']
        
        if 'app_artifacts' in art:
            art['app-artifacts'] = art['app_artifacts']
            del art['app_artifacts']

        if 'path_to_json_inventory_file_for_cocoa_command_special_debian' in args:
            if art['type'] == "debian":
                special_debian_artifacts.append(art)
    
    # If needed, add additional artifact of type deployment
    if 'deployment_metadata' in inventory_data:
        # Initial creation taking values from deployment_metadata
        deployment_artifact = inventory_data['deployment_metadata']

        # Add missing fields
        deployment_artifact['version'] = args['version_field_value']
        deployment_artifact['repository-url'] = inventory_data['commons']['repository_url']
        deployment_artifact['commit-sha'] = inventory_data['commons']['commit_sha']
        deployment_artifact['pipeline-run-id'] = inventory_data['commons']['pipeline_run_id']
        deployment_artifact['build-number'] = inventory_data['commons']['build_number']

        if 'app_artifacts' in deployment_artifact:
            deployment_artifact['app-artifacts'] = deployment_artifact['app_artifacts']
            del deployment_artifact['app_artifacts']

        # Add it to the list of artifacts
        artifacts_after_icr_processing.append(deployment_artifact)

    # If needed delete the debians for the special mode
    if 'path_to_json_inventory_file_for_cocoa_command_special_debian' in args:
        # Keep all the artifacts that are NOT debian, debian will be treated separately
        final_artifacts = [art for art in artifacts_after_icr_processing if art['type'] != 'debian']
    else:
        final_artifacts = artifacts_after_icr_processing


    # Create a new file that will be used for cooca inventory command
    json_object = json.dumps(final_artifacts, indent=4) 
    with open(args['path_to_json_inventory_file_for_cocoa_command'], "w") as outfile:
        outfile.write(json_object)
    
    if 'path_to_json_inventory_file_for_cocoa_command_special_debian' in args:
        json_object_debians = json.dumps(special_debian_artifacts, indent=4) 
        with open(args['path_to_json_inventory_file_for_cocoa_command_special_debian'], "w") as outfile:
            outfile.write(json_object_debians)

if __name__ == "__main__":
    main()