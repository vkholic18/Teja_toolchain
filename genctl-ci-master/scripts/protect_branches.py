# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Creates a GitHub branch protection rule with the given pattern for the 
#    following repositories:
#       - The HARD_CODED repos listed in constants
#       - The components of orda
#       - The components of rias-release
#       - The components of rias-etcd-release
#       - The first level subcomponents of each of the components
#
#    If any of the updates fail, the script continues and provides a summary
#    of the failures at the end
#
# Env:
#    GH_TOKEN: GitHub API token (must be given admin access)
#
# Args:
#     --dry-run: (optional) enable dry-run mode
#
# Use:
#    export GH_TOKEN=123abc
#    python3 protect_branches.py (--dry-run)
#

import argparse
import requests
import github
import re
import json
import logging
import os
import sys

#Constants
# Token passed in through env to avoid token saved in bash history
GH_TOKEN = os.environ['GH_TOKEN']
HEADERS = {"Authorization": f"Bearer {GH_TOKEN}"}

IBM_GH_URL = "https://github.ibm.com"
API_V4_URL = f"{IBM_GH_URL}/api/graphql"
API_V3_URL = f"{IBM_GH_URL}/api/v3"

CONTROLLED_ORGS = [
    "genctl",
    "cloudlab"
]

HARDCODED_REPOS = [
    ("genctl", "orda"),
    ("genctl", "rias-release"),
    ("genctl", "rias-etcd-release"),
    #HostOS
    ("cloudlab", "hostos-base-net-sw-release"),
    ("cloudlab", "hostos-base-os-sw-release"),
    ("cloudlab", "hostos-boot-release"),
    ("cloudlab", "hostos-config-release"),
    ("cloudlab", "hostos-kernel-release"),
    ("cloudlab", "hostos-nextgen-os-sw-release"),
    #Kube
    ("cloudlab", "kube-addon-release"),
    ("cloudlab", "kube-base-release"),
    ("cloudlab", "kube-define-release")
]


def setup_logger():
    """
    Configures logger and formatting
    """
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

def post_graphql_request(query):
    """
    Sends api request with given query
    """
    request = requests.post(API_V4_URL, json={'query': query}, headers=HEADERS)

    if request.status_code != 200:
        raise Exception("POST mutation failed with error: "
            f"{request.status_code}, {request.text}")

    return request.json()

def dict_to_str(dictionary):
    """
    Converts Python dictionary to a string that graphql can interpret
    """
    string_list = list()

    for key, value in dictionary.items():
        if isinstance(value, str): value = f"\"{value}\""
        elif isinstance(value, bool): value = str(value).lower()
        string_list.append(f"{key}: {value}")

    return ', '.join(string_list)

def update_branch_protection(rule_id, settings):
    """
    Updates existing branch protection rule with given settings
    """
    settings_str = dict_to_str(settings)

    query = f"""
        mutation updateBranchProtectionRule {{
            updateBranchProtectionRule(
                input: {{
                    branchProtectionRuleId: "{rule_id}"
                    {settings_str}
                }}
            ),
            {{
                clientMutationId
            }}
        }}
    """

    post_graphql_request(query)

def create_branch_protection(repo_id, settings):
    """
    Creates a new branch protection rule on the given repo with given settings
    """
    settings_str = dict_to_str(settings)

    query = f"""
        mutation CreateBranchProtectionRule {{
            createBranchProtectionRule(
                input: {{
                    repositoryId: "{repo_id}"
                    {settings_str}
                }}
            ),
            {{
                clientMutationId
            }}
        }}
    """

    post_graphql_request(query)

def configure_branch_protection(org_name, repo_name, pattern, dry_run=False):
    """
    Pulls current branch protection configuration and idempotently updates 
    the existing rule or creates a new rule if one doesn't exist
    """
    logger = logging.getLogger()
    settings = {
        "pattern": pattern,
        "requiresApprovingReviews": True,
        "requiredApprovingReviewCount": 1,
        "dismissesStaleReviews": True
    }

    query = f"""
        query {{
            repository(owner: "{org_name}", name: "{repo_name}") {{
                id,
                branchProtectionRules(first: 100) {{
                    nodes {{
                        id
                        {' '.join(settings.keys())}
                    }}
                }}
            }}
        }}
    """

    repo_response = post_graphql_request(query)['data']['repository']
    protection_rules = repo_response['branchProtectionRules']['nodes']

    existing_rule = None
    for rule in protection_rules:
        if rule['pattern'] == pattern:
            existing_rule = rule
            break

    if existing_rule:
        logging.info("Branch protection rule for pattern already exists")
        settings_to_update = dict()
        uncompliant_settings = dict()

        for name, config in settings.items():
            if existing_rule[name] != config:
                uncompliant_settings[name] = existing_rule[name]
                settings_to_update[name] = config

        if settings_to_update:
            logger.info("Existing settings not in compliance: " +\
                f"{uncompliant_settings}")
            logger.info(f"Updating settings to: {settings_to_update}")

            rule_id = existing_rule['id']
            if not dry_run:
                update_branch_protection(rule_id, settings_to_update)
        
        else:
            logger.info("Existing rule in compliance")

    else:
        logging.info("Branch protection rule does not exist; creating")
        repo_id = repo_response['id']
        if not dry_run: create_branch_protection(repo_id, settings)

def parse_org_name_repo_name(url):
    """
    Parses the origin url to get the org and repo name
    """
    # Some of the urls don't have .git, this standardizes the pattern
    url = url.replace('.git', '')

    if url.startswith('git@'):
        regex = re.compile(r'git@.+?:(.+?)\/(.+?)$')
    else:
        regex = re.compile(r'http.+?\/([^\/]+)\/([^\/]+)$')

    org_name = regex.match(url).group(1)
    repo_name = regex.match(url).group(2)

    return org_name, repo_name

def get_submodule_components(repo):
    components = list()

    try:
        download_url = repo.get_contents('.gitmodules').download_url
    except Exception as e:
        # If .gitmodules 404s, the repo doesn't have any submodules 
        # so complete without erroring
        if str(e).startswith('404'):
            download_url = None
        else:
            raise e

    if download_url:
        gitmodules = requests.get(download_url).text
        url_regex = re.compile(r'url\ *=\ *(.+)')
        urls = list()

        for line in gitmodules.splitlines():
            url = url_regex.match(line.strip())
            if url:
                urls.append(url.group(1)) 

        for url in urls:
            component = parse_org_name_repo_name(url)
            if component not in components:
                components.append(component)

    return components

def get_inventory_json_components(repo):
    """
    Retrieves list of org/repo components in inventory.json file of given repo
    """
    inventory_json_path = 'component-input/inventory.json'

    inventory_string = repo.get_contents(inventory_json_path).decoded_content
    inventory = json.loads(inventory_string)

    components = list()
    for component in inventory.items():
        url = component[1].get("url")
        org, repo = parse_org_name_repo_name(url)
        components.append((org, repo))

    return components

def merge_lists(list_a, list_b):
    """
    Adds two lists and removes duplicates
    """
    in_a = set(list_a)
    in_b = set(list_b)

    in_b_not_in_a = in_b - in_a
    return list_a + list(in_b_not_in_a)

def get_repos():
    """
    Retrieves and returns list of all relevent repos to update
    """
    logger = logging.getLogger()
    repos = HARDCODED_REPOS

    
    gh = github.Github(login_or_token=GH_TOKEN, base_url=API_V3_URL)

    logger.info(f"Parsing genctl/orda for subcomponent repositories")
    orda = gh.get_repo('genctl/orda')
    repos = merge_lists(repos, get_submodule_components(orda))

    repos_with_inventory = [
        "genctl/rias-release",
        "genctl/rias-etcd-release"
    ]

    for repo_path in repos_with_inventory:
        logger.info(f"Parsing {repo_path} for subcomponent repositories")
        repo = gh.get_repo(repo_path)
        components = get_inventory_json_components(repo)

        repos = merge_lists(repos, components)

    subcomponents = list()
    for repo in repos:
        logger.info(f"Parsing {repo[0]}/{repo[1]} for subcomponents")
        try:
            gh_repo = gh.get_repo(f"{repo[0]}/{repo[1]}")
        except:
            continue
        components = get_submodule_components(gh_repo)
        subcomponents = merge_lists(subcomponents, components)

    repos = merge_lists(repos, subcomponents)

    return repos

def main():
    setup_logger()
    logger = logging.getLogger()
    pattern = "stable-*"

    if '--dry-run' in sys.argv:
        logger.info("Dry-run mode active; changes will not actually be made")
        dry_run = True
    
    repos = get_repos()
    failed_repos = list()
    skipped_repos = list()

    for org_name, repo_name in repos:
        if org_name in CONTROLLED_ORGS:
            try:
                logger.info(f"Attempting to update {org_name}/{repo_name}")
                configure_branch_protection(
                    org_name, repo_name, pattern, dry_run)
                logger.info(f"Successfully updated {org_name}/{repo_name}")

            except Exception as e:
                logger.info(f"Failed to update {org_name}/{repo_name}")
                failed_repos.append((f"{org_name}/{repo_name}", str(e)))
        
        else:
            logger.info(f"Skipping {org_name}/{repo_name} because we " +
            f"cannot control repositories in the {org_name} organization")
            skipped_repos.append(f"{org_name}/{repo_name}")

    #Print failure/success summary
    if len(skipped_repos) != 0:
        print("\nSome repositories were skipped:")
        for repo in skipped_repos:
            print(repo)

    if len(failed_repos) != 0:
        print("\nSome repositories failed to update:")
        for repo, message in failed_repos:
            print(f"{repo} failed to update because {message}")
    
    else:
        print("\nAll repositories were sucessfully updated")

if __name__ == "__main__":
    main()
