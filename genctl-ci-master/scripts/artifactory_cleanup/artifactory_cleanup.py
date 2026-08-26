
#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

"""
Description:
Delete artifacts in artifactory repositories based on custom dates and number of downloads
"""

#['wcp-genctl-docker-local', 'wcp-genctl-generic-local', 'wcp-genctl-stage-docker-local', 'wcp-genctl-stage-debian-local', 'wcp-genctl-stage-generic-local']


import requests
import logging
import os
from datetime import date
from datetime import timedelta
from ci_python_tools import general_tools

#repos_to_scan=['wcp-genctl-docker-local', 'wcp-genctl-generic-local', 'wcp-genctl-stage-docker-local', 'wcp-genctl-stage-debian-local', 'wcp-genctl-stage-generic-local']
#repos_to_scan=['wcp-genctl-stage-docker-local']

headers = {'content-type': 'text/plain'}

def parse_env():
    """
    Parse the arguments passed when calling this script
    """
    args = dict()

    required_vars = [
        'ARTIFACTORY_USER',
        'CC_ARTIF_ACCESS_TOKEN',
        'ARTIFACTORY_BASE_URL',
        'DAYS_PASSED_FOR_ZERO_DOWNLOADS',
        'DAYS_PASSED_SINCE_LAST_DOWNLOAD',
        'CLEANUP_DRY_RUN',
        'REPOS_TO_SCAN',
        'QUERY_LIMIT',
        'QUERY_MODE',
        'ARTIFACT_TYPE'
    ]

    optional_vars = ['ARTIFACTS_PATH']

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    for var in optional_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            args[var.lower()] = ""

    return args

def prepare_payload_never_downloaded(artif_scan_repo, zero_downloads_modified_date, query_limit, artifacts_path, artifact_type_pattern):
    """
    Prepare the payload for artifacts which were modified before 'zero_downloads_modified_date' and never downloaded
    """
    if not artifacts_path:
        full_artifacts_path = "*"
    else:
        full_artifacts_path = artifacts_path + "/*"

    data = 'items.find(                                                             \
              {                                                                     \
                 "type":"file",                                                     \
                 "repo":"'+ artif_scan_repo +'",                                    \
                 "path": { "$match": "'+ full_artifacts_path +'" },                 \
                 "name":{"$match":"'+ artifact_type_pattern +'"},                    \
                 "modified":{"$lt":"'+ zero_downloads_modified_date +'"},           \
                 "stat.downloads":{"$eq":null}                                      \
               })                                                                   \
               .limit('+ query_limit +')'
    logger.info(f'Will run the artifactory query: {data}')
    return data

def prepare_payload_downloaded_but_obsolete(artif_scan_repo, last_downloaded_date, query_limit, artifacts_path, artifact_type_pattern):
    """
    Prepare the payload for artifacts which have non-zero downloads but were last downloaded before 'last_downloaded_date'
    """
    if not artifacts_path:
        full_artifacts_path = "*"
    else:
        full_artifacts_path = artifacts_path + "/*"

    data = 'items.find(                                                             \
              {                                                                     \
                 "type":"file",                                                     \
                 "repo":"'+ artif_scan_repo +'",                                    \
                 "path": { "$match": "'+ full_artifacts_path +'" },                 \
                 "name":{"$match":"'+ artifact_type_pattern +'"},                           \
                 "stat.downloaded":{"$lt":"'+ last_downloaded_date +'"},            \
                 "stat.downloads":{"$gt":"0"}                                       \
               })                                                                   \
               .limit('+ query_limit +')'
    logger.info(f'Will run the artifactory query: {data}')
    return data

def find_artifacts_to_delete(data, artif_user, artif_token, artif_base_url, artif_scan_repo, headers, deletion_date):
    """
    Find images in artifactory which will be the deletion candidates based on the modified date and the number of downloads
    """
    artifacts_dict = dict()
    tags_list = list()
    total_tags = ''
    delete_candidates = list()

    try:
        artifact_data = requests.post(artif_base_url+'/api/search/aql', auth=(artif_user, artif_token), headers=headers, data=data, timeout=900)
        artifacts_dict = artifact_data.json()

        if artifacts_dict and 'results' in artifacts_dict:
            tags_list = artifacts_dict['results']
            total_tags = artifacts_dict['range']['total']

            logger.info('-' * 80)
            logger.info(f'Summary: Last Modified/Downloaded Date: Artifact to delete')
            if total_tags:
                # Extract the list of images to delete
                for artifact in tags_list:
                    append_path = ''

                    if artifact['name'] == 'manifest.json':
                        append_path = artifact['path']
                    elif artifact['name'] == 'list.manifest.json':
                        #do not add manifest to deleted candidate
                        skipped_path = artifact['path']
                        print(f'Skiping manifest: {skipped_path}')
                        continue
                    else:
                        append_path = artifact['path'] + '/' + artifact['name']

                    delete_candidates.append(append_path)

                    if 'stats' in artifact and 'downloaded' in artifact['stats'][0] and artifact['stats'][0]['downloaded']:
                        summary_print_date = "Last downloaded: " + artifact['stats'][0]['downloaded']
                    else:
                        summary_print_date = "Last modified: " + artifact['modified']

                    logger.info(f'{summary_print_date} : {append_path}  ')
            else:
                logger.info('No artifacts found')

    except Exception as exception:
        logger.error(f'Exception while finding the artifacts to delete!')
        logger.error(exception)
        exit(1)

    logger.info('-' * 80)
    return delete_candidates

def delete_artifacts(artif_user, artif_token, artif_base_url, artif_scan_repo, headers, artifacts_to_delete):
    """
    Delete artifacts in the artifactory repo
    """
    logger.info('-' * 80)
    for artifact in artifacts_to_delete:
        artifact_url = f'{artif_base_url}/{artif_scan_repo}/{artifact}'
        try:
            logger.info(f'Deleting {artifact_url}')
            response = requests.delete(artifact_url, auth=(artif_user, artif_token))
        except Exception as exception:
            logger.info(exception)
            exit(1)
    logger.info('Deletion complete.')
    logger.info('-' * 80)

def main():
    """
    Main function
    """
    global logger
    logger = general_tools.set_up_logger(logging.INFO)

    args = parse_env()
    artif_user = args['artifactory_user']
    artif_token = args['cc_artif_access_token']
    artif_base_url = args['artifactory_base_url']
    dry_run = args['cleanup_dry_run']
    days_passed_for_zero_downloads = int(args['days_passed_for_zero_downloads'])
    days_passed_since_last_download = int(args['days_passed_since_last_download'])
    repos_to_scan_string = args['repos_to_scan']
    repos_to_scan = [repo.strip() for repo in repos_to_scan_string.split(",")]
    query_limit = str(args['query_limit'])
    query_mode = str(args['query_mode'])
    artifact_type = str(args['artifact_type'])
    artifacts_path = str(args['artifacts_path'])

    zero_downloads_modified_date = str(date.today() -  timedelta(days=days_passed_for_zero_downloads))
    last_downloaded_date = str(date.today() -  timedelta(days=days_passed_since_last_download))

    if artifact_type == 'IMAGES-REPO':
        artifact_type_pattern = "manifest.json"
    elif artifact_type == 'PACKAGES-REPO':
        artifact_type_pattern = "*.*"
    else:
        logger.info(f'Artifactory type is not defined. It should be IMAGES-REPO or PACKAGES-REPO')
        exit(1)


    for artif_scan_repo in repos_to_scan:
        logger.info('*' * 80)
        logger.info(f'Processing {artif_scan_repo}')
        logger.info('*' * 80)

        final_delete_candidates=""
        if query_mode == 'NEVER-DOWNLOADED':
            logger.info(f'Processing artifacts modified before {zero_downloads_modified_date} and never downloaded')
            data_never_downloaded = prepare_payload_never_downloaded(artif_scan_repo, zero_downloads_modified_date, query_limit, artifacts_path, artifact_type_pattern)
            artifacts_never_downloaded = find_artifacts_to_delete(data_never_downloaded, artif_user, artif_token, artif_base_url, artif_scan_repo, headers, zero_downloads_modified_date)
            final_delete_candidates = artifacts_never_downloaded
        elif query_mode == 'OBSOLETE':
            logger.info(f'Processing artifacts last downloaded before {last_downloaded_date} and obsolete')
            data_obsolete = prepare_payload_downloaded_but_obsolete(artif_scan_repo, last_downloaded_date, query_limit, artifacts_path,  artifact_type_pattern)
            artifacts_downloaded_but_obsolete = find_artifacts_to_delete(data_obsolete, artif_user, artif_token, artif_base_url, artif_scan_repo, headers, last_downloaded_date)
            final_delete_candidates = artifacts_downloaded_but_obsolete
        else:
            logger.info(f'Query mode is not defined. It should be NEVER-DOWNLOADED or OBSOLETE')

        logger.info(f'The total number of artifacts found as a candidate for deletion: {len(final_delete_candidates)}')
        # Delete the artifacts if it is not a dry run
        if dry_run == 'true':
            logger.info('This is a dry-run. No artifacts deleted.')
            logger.info('-' * 80)
        else:
            if final_delete_candidates:
                delete_artifacts(artif_user, artif_token, artif_base_url, artif_scan_repo, headers, final_delete_candidates)
            else:
                logger.info('Nothing to delete.')
                logger.info('-' * 80)
        logger.info('-' * 80)

        print('\n')

if __name__ == "__main__":
    main()
