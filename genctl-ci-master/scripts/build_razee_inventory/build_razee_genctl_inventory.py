#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

"""
Description:
Create a razee inventory file which lists the workspace, its LaunchDarkly image version and the other associated fields deployed to production
"""

import logging
import yaml
import re
import json
from ci_python_tools import general_tools
from github import Github

# Globals
ORGS = ['genctl', 'cloudlab', 'riaas', 'cloudnet', 'genctl_cicd', 'IPOPS-Automation']
RAZEE_REPO = 'genctl/genesis-deploy-artifacts'
RAZEE_GENCTL_RESOURCES = 'hack/deploy/razee/genctl-cluster-remote-resource.yaml'
RAZEE_VERSIONS_REPO = 'nextgen-environments/dal-prod'
RAZEE_VERSIONS_FILE = 'environment.yaml'
GITHUB_BASE_URL = 'https://github.ibm.com/api/v3'
GITHUB_BRANCH = 'master'

def remove_handlebars(github):
    """
    Remove the handlebars from the template file so that it can be parsed as a yaml
    """
    handlebars = ['{{#unless', '{{/unless}}']

    try:
        repo = github.get_repo(RAZEE_REPO)
        file_contents = repo.get_contents(RAZEE_GENCTL_RESOURCES, ref=GITHUB_BRANCH).decoded_content

        # Write the contents returned in 'bytes' to a file
        with open('old_inventory.yaml', 'wb') as f:
            f.write(file_contents)

        # Keep the lines not containing any handlebars
        with open('old_inventory.yaml') as old_inventory, open('new_inventory.yaml', 'w') as new_inventory:
            for line in old_inventory:
                if not any(handlebar in line for handlebar in handlebars):
                    new_inventory.write(line)

    except Exception as exception:
        logger.error(f'Exception while removing the handlebars')
        logger.error(exception)
        exit(1)

def parse_razee_resources():
    """
    Extract workspace name and its image-version from GDA RAZEE_GENCTL_RESOURCES file
    """
    razee_mappings = dict()
    start_pattern_workspace = '{{{ cos-bucket-name }}}/'
    end_pattern_workspace = '/{{ '
    start_pattern_image = '/{{ '
    end_pattern_image = ' }}/'

    try:
        with open('new_inventory.yaml', 'r') as fp:
            yaml_file_dict = yaml.safe_load(fp.read())['spec']['strTemplates']
            str_templates = yaml_file_dict[1]
            str_templates_dict = yaml.safe_load(str_templates)
            requests = str_templates_dict['spec']['requests']

        if requests:
            for workspace in requests:
                long_url = workspace['options']['url']
                workspace_name = re.search(f'{start_pattern_workspace}(.*){end_pattern_workspace}', long_url)
                workspace_name = workspace_name.group(1)
                image_version_name = re.search(f'{start_pattern_image}(.*){end_pattern_image}', long_url)
                image_version_name = image_version_name.group(1)

                razee_mappings[f'{workspace_name}'] = {}
                razee_mappings[f'{workspace_name}']['image_version'] = image_version_name
        else:
            logger.error('Nothing retured in \'Requests\' from the razee inventory, can\'t proceed.')
            exit(1)

    except Exception as exception:
        logger.error(f'Exception while getting the workspace names')
        logger.error(exception)
        exit(1)

    return razee_mappings

def build_razee_inventory(github, razee_mappings, inventory):
    """
    Check which org does the repo exist in and build its GHE URL and add image-version
    """
    repo = ''
    ghe_prefix = 'git@github.ibm.com:'

    for workspace in razee_mappings:
        for org in ORGS:
            try:
                repo = github.get_repo(f'{org}/{workspace}')
                if repo:
                    url = f'{ghe_prefix}{org}/{workspace}.git'
                    inventory[f'{workspace}'] = {}
                    inventory[f'{workspace}']['url'] = url
                    inventory[f'{workspace}']['ghe_repo'] = f'{org}/{workspace}'
                    inventory[f'{workspace}']['image_version'] = razee_mappings[f'{workspace}']['image_version']
                    break
            except Exception as exception:
                # Don't stop when a repo doesn't exist in org, check the rest
                logger.info(f'{workspace} does not exist in {org}. Checking others')
                pass

    return inventory

def update_inventory_with_tags(github, inventory):
    """
    Read prod RAZEE_VERSIONS_FILE and extract the image versions to add to the inventory
    """
    final_inventory = dict()

    try:
        repo = github.get_repo(RAZEE_VERSIONS_REPO)
        file_contents = repo.get_contents(RAZEE_VERSIONS_FILE, ref=GITHUB_BRANCH).decoded_content
        feature_flags = yaml.safe_load(file_contents)['apps']['feature_flags']['vpc-ci']

        # feature_flags = image-versions pulled from https://github.ibm.com/nextgen-environments/dal-prod/blob/master/environment.yaml
        # inventory = has image-versions pulled from GDA hack/deploy/razee/genctl-cluster-remote-resource.yaml
        # Compare the two above to update the inventory with the correct image-version tag/commit

        for workspace in inventory.items():
            workspace_name = workspace[0]
            gda_image_version = workspace[1]['image_version']
            for ff in feature_flags:
                prod_image_version = ff['name']
                # if image-version in gda == image-version in prod deployment yaml
                if gda_image_version == prod_image_version:
                    inventory[f'{workspace_name}']['hash'] = ff['default']['variation_value']
                    break

        # Some services are not deployed to prod yet. Their image-versions would be missing in the inventory.
        # Copy over only the items that are deployed and hence have 'hash' available to the final inventory
        final_inventory = {key: value for key, value in inventory.items() if 'hash' in value}

    except Exception as exception:
        logger.error(f'Exception while updating the inventory with tags')
        logger.error(exception)
        exit(1)

    return final_inventory

def main():
    """
    Main function
    """
    global logger
    logger = general_tools.set_up_logger(logging.INFO)

    # Parse environment variables
    mandatory_args = ['GHE_ACCESS_TOKEN']

    inventory = dict()

    # Create a temp file to write the inventory, it will be cloned later
    razee_inventory = 'razee_inventory.json'

    # Set the environment
    args = general_tools.parse_env(mandatory_args)
    ghe_access_token = args['ghe_access_token']
    github = Github(base_url=GITHUB_BASE_URL, login_or_token=ghe_access_token)
    remove_handlebars(github)

    # Parse the razee GDA yaml
    razee_mappings = parse_razee_resources()

    # Build initial razee inventory by adding GHE URLs, workspace names and their image-version
    inventory = build_razee_inventory(github, razee_mappings, inventory)

    # Add the production tags to the inventory
    final_inventory = update_inventory_with_tags(github, inventory)
    with open(razee_inventory, 'w') as fp:
        json.dump(final_inventory, fp, indent=4)

    # Print the razee inventory
    with open(razee_inventory, 'r') as f:
        logger.info('Razee inventory with the current production tags:')
        print(f.read())


if __name__ == "__main__":
    main()
