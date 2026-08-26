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
Delete image tags from a secure docker registry (like reg-prod.genctlci.com)
"""

import logging
import requests
import sys
import yaml
import json
import re
import time
from datetime import datetime, timedelta
from collections import OrderedDict
from ci_python_tools import general_tools

# Global args
reg_auth_scope = 'registry:catalog:*'


def load_config(config_file):
    """
    Reads config.yaml to determine what to scan
    """
    try:
        with open(config_file) as f:
            scan_config = yaml.safe_load(f)
    except Exception as e:
        logger.error(e)
        exit(1)

    return scan_config

def find_images(reg_prod_url, auth, auth_domain, base_domain, auth_scope, auth_offline_token, auth_client_id):
    """
    Find all images in the registry
    """
    try:
        reg_token_url = f"{auth_domain}?service={base_domain}&scope={auth_scope}&offline_token={auth_offline_token}&client_id={auth_client_id}"
        reg_token_response = requests.get(reg_token_url, auth=auth, verify=False)
        reg_token_response.raise_for_status()
        reg_access_token = reg_token_response.json()['access_token']

        headers = {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + reg_access_token
        }
        images_json = requests.get(f'{reg_prod_url}/v2/_catalog?n=2000', headers=headers).json()
        images = images_json['repositories']
    except Exception as e:
        logger.error(e)
        exit(1)

    return images

def get_image_token(image, auth, auth_domain, base_domain, auth_offline_token, auth_client_id):
    """
    Return the token for the image scope
    Docker registry needs an image token to perform any actions on the associated image
    More info - https://docs.docker.com/registry/spec/auth/scope/#docker-registry-token-scope-and-access
    """
    # Allow '*' (all) actions on the image
    image_auth_scope=f'repository:{image}:*'
    try:
        image_token_url = f"{auth_domain}?service={base_domain}&scope={image_auth_scope}&offline_token={auth_offline_token}&client_id={auth_client_id}"
        image_token_response = requests.get(image_token_url, auth=auth, verify=False)
        image_token_response.raise_for_status()
        image_token = image_token_response.json()['access_token']
    except Exception as e:
        logger.error(e)
        exit(1)

    return image_token

def count_tags(image, headers, auth, reg_base_url):
    """
    Return the number of tags for an image
    """
    number_of_tags = 0
    tags_listing = dict()
    try:
        tags_listing_url = f'{reg_base_url}/v2/{image}/tags/list'
        tags_listing_response = requests.get(tags_listing_url, headers=headers).json()
        if tags_listing_response and 'tags' in tags_listing_response:
            if tags_listing_response['tags']:
                tags_listing = tags_listing_response['tags']
                number_of_tags = len(tags_listing_response['tags'])
            else:
                logger.error(f'Failed to find any tags for {image}')
    except Exception as e:
        logger.error(e)
        exit(1)

    return number_of_tags, tags_listing

def find_all_tags_with_date(image, headers, tags_list, reg_base_url, tag_life_days, cut_off_date):
    """
    Find which tags can be deleted based on the 'Created' date
    """
    all_tags_with_date = dict()
    sorted_tags_with_date = dict()

    try:
        for tag in tags_list:
            # Find the "created" datetime for the tag
            image_metadata = requests.get(f'{reg_base_url}/v2/{image}/manifests/{tag}', headers=headers).json()
            if 'history' in image_metadata:
                created_date_time = json.loads(image_metadata['history'][0]['v1Compatibility']).get('created')
                # Strip out the time
                match = re.search(r'\d{4}-\d{2}-\d{2}', created_date_time)
                created_date = match.group()

                # Write the tag and its creation date in a temp dict
                all_tags_with_date.update({tag: created_date})
            else:
                logger.error('#' * 80)
                logger.error(f'Failed to get "created" date for tag "{tag}"')
                logger.error(f'{image_metadata}')
                logger.error('#' * 80)

        sorted_tags_with_date = sorted(all_tags_with_date.items(), key=lambda x: x[1], reverse=True)

    except Exception as e:
        logger.error(e)
        exit(1)

    return sorted_tags_with_date

def prune_tags(sorted_tags_with_date, keep_tag_count):
    """
    Keep the 'latest' tag and the last 'keep_tag_count' tags
    Args:
        keep_tag_count = Number of tags we want to keep
    """
    # Remove the first <keep_tag_count> elements because they are the latest <keep_tag_count> tags
    delete_candidates_temp = sorted_tags_with_date[keep_tag_count:]

    # delete_candidates_temp is a list of tuples, convert it into a dict
    delete_candidates_final = dict(delete_candidates_temp)

    # Remove the 'latest' (literal) tag as well
    delete_candidates_final.pop('latest', None)

    return delete_candidates_final

def filter_by_created_date(delete_candidates, cut_off_date):
    """
    Remove the tags that are pushed after the cut-off date, they need to be saved.
    Example:
        If cut_off_date is 01-01-2021, all the tags pushed BEFORE 01-01-2021 will be deleted.
        Hence, the tags pushed AFTER 01-01-2021 will be saved.
    """
    tags_created_before_cutoff = list()

    logger.info(f'Potential delete candidates: {delete_candidates}')
    for tag, created in delete_candidates.items():
        # Convert "created" from string to date object for date comparison
        created_dt_obj = datetime.strptime(created, '%Y-%m-%d').date()
        if created_dt_obj < cut_off_date:
            tags_created_before_cutoff.append(tag)

    return tags_created_before_cutoff

def sort_tags(delete_these_tags):
    """
    Sort the given list, so that 'manifest list' comes before the images inside the manifest
    Example:
        delete_these_tags = ['abc-s390x', 'abc-amd64', 'abc']
        sorted_tags = ['abc', 'abc-amd64', 'abc-s390x']
    """
    sorted_tags = list()
    try:
        sorted_tags = sorted(delete_these_tags)
    except Exception as e:
        logger.error("Couldn't sort the final delete list. This can leave the manifests dangling. Exiting ...")
        logger.error(e)
        exit(1)

    return sorted_tags

def delete_tags(delete_these_tags, image,reg_base_url, image_token, headers):
    """
    Delete a list of tags for an image
    """
    headers_v2 = {
        'Content-Type': 'application/json',
        'Accept': 'application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json',
        'Authorization': 'Bearer ' + image_token
    }
    image_digest = ''

    try:
        for tag in delete_these_tags:
            # Get the manifest for the image, to extract the image digest, try 5 times
            for retry in range(5):
                manifest = requests.get(f'{reg_base_url}/v2/{image}/manifests/{tag}', headers=headers_v2)
                if manifest.headers and 'Docker-Content-Digest' in manifest.headers:
                    # Real "image" digest is a part of the response headers
                    image_digest = manifest.headers['Docker-Content-Digest']
                    break
                else:
                    time.sleep(2)

            if image_digest:
                delete_response = requests.delete(f'{reg_base_url}/v2/{image}/manifests/{image_digest}', headers=headers)
                if delete_response.status_code == 202:
                    logger.info(f'Successfully deleted tag {tag} (Digest: {image_digest})')
                else:
                    logger.error(f'{delete_response.status_code}: Failed to delete tag {tag} (Digest: {image_digest})')
            else:
                logger.error(f'Failed to find image digest for {image}:{tag}')
        logger.info('-' * 80)

    except Exception as e:
        logger.error(e)
        exit(1)


def main():
    """
    Main function
    """
    global logger
    logger = general_tools.set_up_logger(logging.INFO)

    # Parse environment variables
    mandatory_args = [
        'REG_BASE_URL',
        'REG_PROD_URL',
        'REG_PROD_USER',
        'REG_PROD_PASSWORD',
        'REG_PROD_AUTH_DOMAIN',
        'REG_PROD_BASE_DOMAIN',
        'REG_PROD_AUTH_OFFLINE_TOKEN',
        'REG_PROD_AUTH_CLIENT_ID']

    args = general_tools.parse_env(mandatory_args)
    auth = (args['reg_prod_user'], args['reg_prod_password'])
    reg_base_url = args['reg_base_url']
    reg_prod_url = args['reg_prod_url']
    auth_domain = args['reg_prod_auth_domain']
    base_domain = args['reg_prod_base_domain']
    auth_offline_token = args['reg_prod_auth_offline_token']
    auth_client_id = args['reg_prod_auth_client_id']

    # Read global args from config.yaml
    config_path = sys.path[0]
    config_file = config_path + '/config.yaml'
    config = load_config(config_file)

    # All the config args must exist
    if all (keys in config for keys in ('tag_life_days', 'keep_tag_count', 'dry_run')):
        tag_life_days = config['tag_life_days']
        keep_tag_count = config['keep_tag_count']
        dry_run = config['dry_run']
    else:
        logger.error("Configuration argument(s) missing from config.yaml")
        exit(1)

    cut_off_date = (datetime.today() - timedelta(days=tag_life_days)).date()
    logger.info('-' * 80)
    logger.info(f'Cut-off date is "{cut_off_date}"')

    image_list = find_images(reg_prod_url, auth, auth_domain, base_domain, reg_auth_scope, auth_offline_token, auth_client_id)

    for image in image_list:
        logger.info('-' * 80)
        logger.info(f'Processing {image}')
        image_token = get_image_token(image, auth, auth_domain, base_domain, auth_offline_token, auth_client_id)

        headers = {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + image_token
        }

        number_of_tags, tags_list = count_tags(image, headers, auth, reg_base_url)

        if number_of_tags:
            if number_of_tags > keep_tag_count:
                logger.info(f'{image} has more than {keep_tag_count} tags')
                # Find all existing tags and their created date
                sorted_tags_with_date = find_all_tags_with_date(image, headers, tags_list, reg_base_url, tag_life_days, cut_off_date)

                if sorted_tags_with_date:
                    # Filter out the tags that are not 'latest' removing the most recent 'keep_tag_count' tags
                    delete_candidates = prune_tags(sorted_tags_with_date, keep_tag_count)

                    # Remove the tags created after the <cut_off_date>
                    delete_these_tags = filter_by_created_date(delete_candidates, cut_off_date)

                    # Now the tags left are ready for deletion
                    if delete_these_tags:
                        logger.info('*' * 80)
                        # Sort the tags so that the manifest list comes before the included images.
                        # If not sorted, image will get deleted before the manifest and its manifest will be left dangling
                        sorted_tags = sort_tags(delete_these_tags)
                        logger.info(f'Tags pushed before the cut-off-date to be deleted: {sorted_tags}')
                        logger.info('*' * 80)

                        if dry_run:
                            logger.info('This is a dry-run. No tags will be deleted.')
                        else:
                            logger.info('Not a dry-run. Deleting the tags ...')
                            delete_tags(sorted_tags, image, reg_base_url, image_token, headers)
                    else:
                        logger.info(f'No tags created before {cut_off_date}. Deletion criteria not met. Nothing to delete')
                else:
                    logger.info('No tags with "created" date info, nothing to process.' )
            else:
                logger.info(f'{image} has {keep_tag_count} or less tags. Skipping ...')
        else:
            logger.error(f'Strangely {image} has no tags. Moving on ...')
        logger.info('-' * 80)


if __name__ == "__main__":
    main()
