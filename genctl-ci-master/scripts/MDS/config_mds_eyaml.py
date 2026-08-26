
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

import copy
import github
import logging
import os
import sys
import argparse
import re
from enum import Enum
from packaging import version
import yaml
import ruamel.yaml
from ruamel.yaml.comments import CommentedMap as OrderedDict

from add_nodelist_flags import check_releasebundles_support_z
from add_nodelist_flags import get_flags
from add_nodelist_flags import add_flags_mds

# Constants
ENV_YAML_PATH = "environment.yaml"
HOSTOS_2_X_MAJOR = 2
HOSTOS_3_X_MAJOR = 3
HOSTOS_FIPS_MAJOR = 4
HOSTOS_5_X_MAJOR = 5
HOSTOS_6_X_MAJOR = 6
HOSTOS_REDHAT_MAJOR = 10
z_support_initial_versions = { 'hostos-base-net-sw-release': '2.0.3',
                               'hostos-base-os-sw-release': '2.1.3',
                               'hostos-boot-release': '2.1.0',
                               'hostos-config-release': '2.1.1',
                               'hostos-kernel-patch-release': '2.1.0',
                               'hostos-nextgen-os-sw-release': '2.1.1' }

class NodeType(Enum):
    ALL = 1
    NO_Z = 2
    NO_Z_SSC = 3
    NO_Z_LINUX = 4

def set_up_logger():
    """
    Configures logger and formatting
    """
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

    return logger

def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'MZONE_NAME',
        'GITHUB_API_KEY',
        'GITHUB_API_URL',
        'ENV_REPO_ORG',
        'ENV_REPO_REF',
        'PLATFORM_INVENTORY_REF',
        'PLATFORM_INVENTORY_ORG'
    ]

    missing_vars = list()
    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            missing_vars.append(var)

    if missing_vars:
        vars_str = ', '.join(missing_vars)
        logger.error(f"Missing required env variable(s), {vars_str}")
        exit(1)

    return args

def get_yaml(path):
    logger = logging.getLogger()
    try:
        with open(path, 'r') as eyaml:
            content = ruamel.yaml.round_trip_load(eyaml, preserve_quotes=True)

        return content
    except FileNotFoundError:
        logger.error(f"The eyaml file \"{path}\" does not exist")
        sys.exit(1)
    except yaml.YAMLError as err:
        logger.error("Unable to parse yaml ({}): reason: {}".format(path, err))
        sys.exit(1)
    except:
        logger.error("Unable to open manifest yaml ({}): reason: {}".format(
            path, sys.exc_info()[0]))
        sys.exit(1)

def get_repo_yaml(repo, ref, path):
    """
    Gets and parses a yaml file from a given github repository
    Args:
        repo: Github repository object
        ref: sha/branch of github repository
        path: Path to yaml file wihin repository
    Returns:
        data: Parsed data from yaml file
        sha: The git sha of the file
    """
    content = repo.get_contents(path, ref=ref)
    data = yaml.safe_load(content.decoded_content)
    sha = content.sha

    return data, sha

def add_nodelist_to_eyaml(eyaml, vetted_versions, inventory_file):
    support_nodes_type = check_releasebundles_support_z(vetted_versions)
    nodelist_flag = get_flags(inventory_file, support_nodes_type)
    add_flags_mds(eyaml, nodelist_flag)
    if nodelist_flag:
        flag_str = "--mzone-node-list=" + "".join(nodelist_flag).replace("--node-list ","")
        add_tool(eyaml, "ddt-deploy", flag_str)

def init_eyaml_versions(eyaml_template, versions, env_config):
    logger = logging.getLogger()
    for i, bundle in enumerate(eyaml_template):
        name = bundle['name']
        if name in versions.keys():
            eyaml_template[i]['version'] = versions[name]

def config_platform_inventory_vars(eyaml, platform_inventory_ref, platform_inventory_org):
    source = eyaml['infrastructure']['providers']['ibm_onprem']['mzones'][0]['source']
    ref = source.split('=')
    ref[1] = platform_inventory_ref
    eyaml['infrastructure']['providers']['ibm_onprem']['mzones'][0]['source'] = '='.join(ref)
    org = eyaml['infrastructure']['providers']['ibm_onprem']['mzones'][0]['source'].split('/')
    org[1] = platform_inventory_org
    eyaml['infrastructure']['providers']['ibm_onprem']['mzones'][0]['source'] = '/'.join(org)

def add_tool(eyaml, flag_name, flag_values, flag_cmd=None):
    """
    Adds a deployment tool with related flags to environment yaml.
    Args:
        eyaml: Environment yaml
        flag_name: Tool name
        flag_values: Tool flags separated by space.
        flag_cmd: Tool command
    """
    logger = logging.getLogger()

    tools_dict = {}
    tools_dict["name"] = flag_name
    tools_dict["flags"] = []

    flags = flag_values.split(" ")
    for flag in flags:
        tools_dict["flags"].append(flag)

    if flag_cmd:
        tools_dict["cmd"] = flag_cmd

    found_tool = False
    logger.info(f"Adding tool: {tools_dict}")
    if 'tools' in eyaml:
        for tool in eyaml["tools"]:
            if tool["name"] == flag_name:
                for flag in flags:
                    tool["flags"].append(flag)
                found_tool = True
                break
        if found_tool == False:
            eyaml['tools'].append(tools_dict)
    else:
        tools = [OrderedDict(tools_dict)]
        eyaml['tools'] = tools

def parse_args():
    """
    Parse the arguments passed when calling this file.
    """
    parser = argparse.ArgumentParser(
        description="Prepare Eyaml configuration file for deployment")
    parser.add_argument('-i', '--input-file', help="Eyaml input file usually a template file", required=True)
    parser.add_argument('-o', '--output-file', help="Eyaml output file with the proper configuration")
    parser.add_argument('-vv', '--vetted-versions', help="Vetted versions file to be used to initialize the Eyaml to known versions")
    parser.add_argument('-c', '--component', help="Component name to update")
    parser.add_argument('-p', '--package', help="Which package we wish to deploy")
    parser.add_argument('-po', '--package-only', help="Deploy only the specific package", action="store_true", default=False)
    parser.add_argument('-co', '--component-only', help="Deploy only the specific component", action="store_true", default=False)
    parser.add_argument('-v', '--version', help="Component version to update")
    parser.add_argument('-if', '--inventory-file', help="Inventory file")
    parser.add_argument('-op', '--operation', help="Supports two operations, init, prep", required=True)

    args = parser.parse_args()
    return args

def export_yaml(path, content):
    with open(path, "w") as out:
        ruamel.yaml.round_trip_dump(content, out, default_flow_style=False)

def main():
    # Setup logger
    logger = set_up_logger()
    # Setup environemt and CLI args
    env = parse_env()
    args = parse_args()
    eyaml = get_yaml(args.input_file)
    # init an eyaml with known good versions from a vetted version file
    if args.operation == "init":
        # setup git to fetch the eyaml config for the relevant mzone
        gh = github.Github(
            base_url=env['github_api_url'],
            login_or_token=env['github_api_key']
        )
        env_org_repo = f"{env['env_repo_org']}/{env['mzone_name']}"
        env_repo = gh.get_repo(env_org_repo)
        versions = get_yaml(args.vetted_versions)
        env_yaml, eyaml_sha = get_repo_yaml(env_repo, env['env_repo_ref'], ENV_YAML_PATH)
        logger.info(f"Pulled {env_org_repo}@{eyaml_sha}")
        eyaml_versions = copy.deepcopy(eyaml)
        eyaml_versions['name'] = env['mzone_name']
        versions['version']['hostos-post-config-release'] = versions['version']['hostos-config-release']
        init_eyaml_versions(eyaml_versions['apps']['release_bundles'], versions['version'], env_yaml)
        eyaml_versions['infrastructure'] = env_yaml['infrastructure']
        eyaml_versions['name'] = env_yaml['name']
        add_nodelist_to_eyaml(eyaml_versions, args.vetted_versions, args.inventory_file)
        config_platform_inventory_vars(eyaml_versions, env['platform_inventory_ref'], env['platform_inventory_org'])
        if 'REG_URL_PREFIX' in os.environ:
                flag="--reg-url-prefix=" + os.getenv('REG_URL_PREFIX')
                add_tool(eyaml_versions, "ddt-deploy", flag)
        export_yaml(args.output_file, eyaml_versions)
    if args.operation == "prep":
        component = args.component
        package = args.package
        tag = args.version
        if component == "cloudnet":
            component="pds"
        #if package ==  "hostos-kernel-patch-release":
        #    kernel_release = {
        #        'name': "hostos-kernel-patch-release",
        #        'version': "XXXX"
        #    }
        #    print("updating kernel patch")
        #    eyaml['apps']['release_bundles'].append(kernel_release)
        for bundle in eyaml['apps']['release_bundles']:
            if package == bundle['name']:
                bundle['version'] = tag
            if package == "hostos-config-release" and bundle['name'] == "hostos-post-config-release":
                bundle['version'] = tag
            if package == "hostos-boot-release" and bundle['name'] == "hostos-z-boot-release":
                bundle['version'] = tag
        if args.component_only:
            pack_to_remove = [p['name'] for p in eyaml['apps']['release_bundles'] if not p['name'].startswith(component)]
            eyaml['apps']['release_bundles'] = [rb for rb in eyaml['apps']['release_bundles'] if rb['name'] not in pack_to_remove]
        elif args.package_only:
            pack_to_remove = [p['name'] for p in eyaml['apps']['release_bundles'] if p['name'].startswith(component) and p['name'] != package]
            eyaml['apps']['release_bundles'] = [rb for rb in eyaml['apps']['release_bundles'] if rb['name'] not in pack_to_remove]
        export_yaml(args.output_file, eyaml)

if __name__ == "__main__":
    main()
