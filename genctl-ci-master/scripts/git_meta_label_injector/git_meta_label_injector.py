# =============================================================================================
# IBM Confidential
# (c) Copyright IBM Corp. 2021, 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Updates version.json and the deployment labels in deployment file(s) with
#    the following data: gitBranch, gitRevision, gitLastCommitTime, gitTag
#
# Environment:
#   WORKSPACE_PATH: Relative path to the workspace on disk
#   VAULT_AGENT_IMAGE: defined in pipeline-params.yaml
#
# Use:
#    python3 git_meta_label_injector.py
#

import git
import json
import logging
import os
import re
import sys


#Constants
INDENT_SIZE = 2
TMPL_PREFIX = "{{"
VERSION_INSERT_TOKEN = "## insert_version ##"
VAULT_AGENT_IMAGE_INSERT_TOKEN = "## insert_vault_agent_image ##"

kind_pattern = re.compile(r'^( +)?kind\: (?:Deployment|DaemonSet|StatefulSet|ReplicaSet)')
not_kind_pattern = re.compile(r'^( +)kind\: (?!Deployment|DaemonSet|StatefulSet|ReplicaSet)')
meta_pattern = re.compile(r'^( +)metadata\:')


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


def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        "WORKSPACE_PATH",
        "VAULT_ENTERPRISE_IMAGE_LOCATION"
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


def find_head_commit_tag(repo):
    """
    Finds git tag associated with the head commit of a repo
    Args:
        repo: Github repository to search through
    Returns:
        The name of the git tag or None if nothing was found
    """
    logger = logging.getLogger()
    git_tag = None
    sha = repo.head.commit

    for tag in repo.tags:
        if repo.commit(tag) == sha:
            git_tag = str(tag)
            break

    if git_tag:
        logger.info(f"Tag {git_tag} found for commit {sha}")

    return git_tag


def find_head_branch(repo):
    """
    Finds the branch name associated with a commit ID
    Args:
        repo: Github repository to search through
    Returns:
        Name of the branch (if multiple branches, defaults to master)
    """
    sha = repo.head.commit

    branches = repo.git.branch('--contains', sha).splitlines()
    branches = [ name.strip('*').strip() for name in branches ]

    for branch in branches:
        if 'HEAD detached at' in branch:
            branches.remove(branch)

    if 'master' in branches:
        return 'master'
    elif branches:
        return branches[0]
    else:
        return None


def parse_org_name_repo_name(repo):
    """
    Retrieves and parses the origin url for the org and repo name
    Args:
        repo: Github repository to search through
    Returns:
        org_name: the name of the GitHub organization
        repo_name: the name of the repository
    """
    url = repo.git.remote("get-url", "--all", "origin")
    if url.endswith('.git'):
        if url.startswith('git@'):
            regex = re.compile(r'git@.+?:(.+?)\/(.+?)\.git')
            org_name = regex.match(url).group(1)
            repo_name = regex.match(url).group(2)
        else:
            regex = re.compile(r'http.+?\/([^\/]+)\/([^\/]+)\.git')
            org_name = regex.match(url).group(1)
            repo_name = regex.match(url).group(2)
    else:
        regex = re.compile(r'http.+?\/([^\/]+)\/([^\/]+)\/([^\/]+)')
        org_name = regex.match(url).group(2)
        repo_name = regex.match(url).group(3)

    return org_name, repo_name

def generate_git_data(repo_path):
    """
    Retrieves and generates a dict of the following git data: gitBranch,
    gitRevision, gitLastCommitTime, and gitTag
    Returns:
        A dictionary of the data retrieved
    """
    logger = logging.getLogger()

    repo = git.Repo(repo_path)
    git_tag = find_head_commit_tag(repo)
    branch_name = find_head_branch(repo)
    timestamp = repo.head.commit.authored_datetime.timestamp()
    org_name, repo_name = parse_org_name_repo_name(repo)

    data = dict()
    data['gitBranch'] = branch_name
    if os.path.exists(f'{repo_path}/.git/resource/head_sha'):
        # Concourse uses a merge commit for PRs. Get the PR commit instead
        with open(f'{repo_path}/.git/resource/head_sha') as f:
            data['gitRevision'] = f.read().strip()
    else:
        data['gitRevision'] = str(repo.head.commit)
    data['gitLastCommitTime'] = str(timestamp)
    data['gitOrg'] = org_name
    data['gitRepo'] = repo_name
    if git_tag:
        data['gitTag'] = git_tag
        data['version'] = git_tag
    else:
        logger.info("git tag not found; defaulting version to sha")
        data['version'] = data['gitRevision']

    return data


def find_razee_yaml_files(path):
    """
    Finds razee deployment yaml files within a directory
    Args:
        Path to deployment config directory
    Returns:
        List of paths to deployment template files
    """
    files = []

    for r, _, f in os.walk(path):
        for file in f:
            if '.yaml' in file:
                file_path = os.path.join(r, file)
                files.append(file_path)

    return files

def find_deployment_files(path, kind_pattern=kind_pattern):
    """
    Finds deployment template files within a directory
    Args:
        Path to deployment config directory
        Deployment kind pattern to match
    Returns:
        List of paths to deployment template files
    """
    files = []

    for r, _, f in os.walk(path):
        for file in f:
            if '.yaml' in file:
                file_path = os.path.join(r, file)

                for line in open(file_path):
                    if kind_pattern.match(line):
                        files.append(file_path)
                        break

    return files

def find_files_having_workspace_tag(razee_yaml_files):
    """
    Finds files containing 'workspace_tag'
    Args:
        Razee deployment yaml files
    Returns:
        List of file paths containing 'workspace_tag'
    """
    deploy_files = []

    for file in razee_yaml_files:
        with open(file) as f:
            if 'workspace_tag' in f.read():
                deploy_files.append(file)

    return deploy_files

def update_deployment_labels(file_content, labels):
    """
    Insert the 'labels' (git metadata) in the resource yamls which contain 'workspace_tag' label
    Note: parsing cannot be done with a YAML parser (pyYaml, etc) because
          the deployment file is acutally a jinja2 template
    Args:
        file_content: string contents of a k8s resource file containing 'workspace_tag' label
        labels: dict of labels
    Returns:
        Updated string file contents
    """
    file_lines = file_content.split('\n')

    for index, line in enumerate(file_lines):
        if 'workspace_tag:' in line:
            # Determine size of indent
            meta_indent = len(line) - len(line.lstrip())

            # Insert git metadata right after the line containing 'workspace_tag'
            for key, val in labels.items():
                yaml_str = f"{key}: \"{val}\""
                file_lines.insert(
                    index + 1, meta_indent * ' ' + yaml_str)

    return '\n'.join(file_lines)

def replace_deployment_version(file_content, version_value):
    """
    Do a search and replace of VERSION_INSERT_TOKEN with the version value in the file
    Note: parsing cannot be done with a YAML parser (pyYaml, etc) because
          the deployment file is acutally a jinja2 template
    Args:
        file_content: string contents of a k8s resource file containing 'workspace_tag' label
        version_value: string with the version value
    Returns:
        Updated string file contents
    """
    file_content = file_content.replace(VERSION_INSERT_TOKEN, version_value)

    return file_content

def main():
    logger = setup_logger()
    logger.info("Adding git metadata to deployment labels")

    args = parse_env()
    repo_path = args['workspace_path']
    vault_enterprise_image_location_path = args['vault_enterprise_image_location']

    DEPLOYMENT_CONFIG_PATH = os.getenv('COS_UPLOAD_CONTENT_ROOT') or ""

    deploy_dir = os.path.join(repo_path, DEPLOYMENT_CONFIG_PATH)
    if not os.path.exists(deploy_dir):
        logger.warning(
            f"{DEPLOYMENT_CONFIG_PATH} does not exist in workspace; skipping")
        exit(0)

    version = dict()
    # Inject git metadata
    version.update(generate_git_data(repo_path))

    logger.info("Version metadata:")
    for key, value in version.items():
        logger.info(f"{key}: {value}")

    # Find all razee yamls
    razee_yaml_files = find_razee_yaml_files(deploy_dir)

    # Insert vault agent image in razee yaml files
    for yaml_file in razee_yaml_files:
        with open(yaml_file, 'r') as f:
            file_content = f.read()
        file_content = file_content.replace(VAULT_AGENT_IMAGE_INSERT_TOKEN, vault_enterprise_image_location_path)
        with open(yaml_file, 'w') as f:
            f.write(file_content)

    # Filter to find which yamls contain the 'workspace_tag'
    deploy_files = find_files_having_workspace_tag(razee_yaml_files)

    # Update deployment template file(s) with versions
    for deploy_file in deploy_files:
        logger.info(f"Adding deployment version to {deploy_file}")
        with open(deploy_file, 'r') as f:
            deployment = f.read()

        deployment = replace_deployment_version(deployment, version['version'])
        with open(deploy_file, 'w') as f:
            f.write(deployment)

    # Update deployment template file(s) with labels
    for deploy_file in deploy_files:
        logger.info(f"Adding deployment labels to {deploy_file}")
        with open(deploy_file, 'r') as f:
            deployment = f.read()

        deployment = update_deployment_labels(deployment, version)
        with open(deploy_file, 'w') as f:
            f.write(deployment)

if __name__ == '__main__':
    main()
