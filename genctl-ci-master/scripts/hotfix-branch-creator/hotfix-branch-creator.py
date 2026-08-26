# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Performs the following actions to prepare for a hotfix:
#       Updates the environment file in the vetted versions repo
#       Creates stable-* branches on major and minor component
#
# Inputs:
#    hotfix yaml config file:
#       Submitted by the developer to the hotfix repository
#       Contains major/minor component, enviornment, and vetted-versions info
#       See example.yaml in genctl-cicd/hotfix
#
# Env:
#    GHE_API_TOKEN: Token for Github API
#    GHE_API_URL: Url for the GitHub API
#    HOTFIX_REPO_PATH: Path to the hotfix-razee repo on the filesystem

#
# Use:
#    python3 hotfix-branch-creator.py
#
#

import git
import github
import logging
import os
import yaml

def set_up_logger():
    """
    Configures logger and formatting
    Returns:
        Logger object
    """
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

    return logger

def load_yaml(file_path):
    with open(file_path) as f:
        dictionary = yaml.safe_load(f)

    return dictionary

def get_hotfix(hotfix_repo_path):
    """
    Gets the latest hotfix configuration added to the repo
    Args:
        hotfix_repo_path: Path to the hotfix repository on the filesystem
    Returns:
        Hotfix configuration in a dictionary
    """
    logger = logging.getLogger()
    hotfix_repo = git.Repo(hotfix_repo_path)
    changed_files = list(hotfix_repo.head.commit.stats.files.keys())

    num_files = len(changed_files)
    if num_files > 1:
        logger.error(f"Multiple files ({num_files}) modified in one commit." +\
            " Only one hotfix file per PR is supported")
        exit(1)

    if num_files < 1 or not changed_files[0].endswith('.yaml'):
        logger.error(f"Hotfix config not detected in changed files")
        exit(1)

    hotfix_yaml_path = changed_files[0]
    logger.info(f"Executing {hotfix_yaml_path}")

    with open(os.path.join(hotfix_repo_path, hotfix_yaml_path)) as f:
        hotfix = yaml.safe_load(f)
    return hotfix

def create_branch(repo, branch_name, comp_tag):
    """
    Creates a branch on the given repo off the given sha
    Args:
        repo: Github Repo object
        branch_name: Name of the branch to be created
        comp_tag: tag off of which the branch is created
    """
    logger = logging.getLogger()

    try:
        sha = repo.get_commit(sha=comp_tag).sha

    except github.GithubException as e:
        logger.error(f"Could not find git sha by tag {comp_tag}. " + \
                     "Ensure the git tag exist.")
        exit (1)

    try:
        repo.get_branch(branch_name)
        branch_exists = True

        logger.info(f"{branch_name} already exists on {repo.name}")

    except github.GithubException as e:
        if 'Branch not found' in str(e):
            branch_exists = False
            pass
        else:
            logger.error(f"Could not access {repo.name}. " + \
                         "Ensure the CI user has collaborator access.")
            exit(1)

    if not branch_exists:
        try:
            repo.create_git_ref(
                ref='refs/heads/' + branch_name,
                sha=sha
            )
        except github.GithubException as e:
            logger.error(f"Could not create branch on {repo.name}. " + \
                         "Ensure the CI user has collaborator access.")
            exit(1)

        logger.info(f"Created {branch_name} branch from {sha} on {repo.name}")

def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'GHE_API_TOKEN',
        'GHE_API_URL',
        'HOTFIX_REPO_PATH'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args

def main():
    logger = set_up_logger()
    args = parse_env()

    gh = github.Github(
        login_or_token=args['ghe_api_token'],
        base_url=args['ghe_api_url']
    )

    # Retrieve latest hotfix file added to the hotfix repo
    hotfix = get_hotfix(args['hotfix_repo_path'])
    env = hotfix['ld_environment']
    owners = hotfix['owners'] if 'owners' in hotfix.keys() else list()

    components = list()
    if 'components' in hotfix.keys():
        components = hotfix['components']
    if 'nextgen_environment' in hotfix.keys():
        razee_hotfix_nextgen_environment = hotfix['nextgen_environment']
    if 'ld_environment' in hotfix.keys():
        razee_hotfix_ld_environment = hotfix['ld_environment']

    pipelines = dict()

    # Create infrastructure for minor components
    for component in components:
        comp_org_repo = component['name']
        comp_org = comp_org_repo.split('/')[0]
        comp_name = comp_org_repo.split('/')[1]
        comp_tag = component['github_tag']
        branch_name = 'stable-' + comp_tag
        if 'functional_tests' in component:
            comp_functional_tests = component['functional_tests']
        else:
            comp_functional_tests = ''

        # Create branch on minor component repo
        comp_repo = gh.get_repo(comp_org_repo)
        create_branch(comp_repo, branch_name, comp_tag)


if __name__ == "__main__":
    main()
