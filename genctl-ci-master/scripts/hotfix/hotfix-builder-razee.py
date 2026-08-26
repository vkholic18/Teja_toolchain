# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Performs the following actions to prepare for a hotfix:
#       Updates the environment file in the vetted versions repo
#       Creates stable-* branches on major and minor component
#       Updates hotfix-pipelines.yaml file in genctl-ci
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
#    SLACK_TOKEN: Token for slack API
#    HOTFIX_REPO_PATH: Path to the hotfix repository on the filesystem
#    GENCTL_CI_REPO_PATH: Path to the genctl-ci repo on the filesystem
#    TEMPLATE_CONFIGS_PATH: Path to the template config yaml
#    PARAMS_FILE_PATH: Path to the pipeline parameters file
#    CONCOURSE_URL: Url of Concourse on which to put the pipelines
#    CONCOURSE_USER: Concourse CLI username
#    CONCOURSE_PASS: Concourse CLI password
#
# Use:
#    python3 hotfix-builder-razee.py
#
#

import git
import github
import json
import logging
import os
import ruamel.yaml
import slack
import stat
import subprocess
import urllib.request
import yaml

#get pipeline-overrides-reader
import sys
path = os.path.realpath(__file__)
dir = os.path.dirname(path)
dir = dir.replace("hotfix", "")
sys.path.insert(1, dir)
import pipeline_overrides_reader


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

def get_pipeline_configs(template_configs_path):
    """
    Retrieves the pipeline config mapping from the pipeline config repo
    Args:
        template_configs_path: Path to the template config yaml
    Returns:
        Merged dictionary of the one-off and templatized pipelines
    """
    with open(template_configs_path) as f:
        template_pipes = ruamel.yaml.safe_load(f)

    configs = dict()
    for pipelines in [template_pipes]:
        for pipeline, config in pipelines.items():
            if pipeline not in configs.keys():
                configs[pipeline] = dict()

            configs[pipeline].update(config)
    return configs

def format_pipeline(config_file, pipeline_vars):
    """
    Formats the hotfix pipeline in a CommentedMap
    Args:
        config_file: The path to the pipeline configuration file
        pipeline_vars: Dictionary of pipeline variables
    Returns:
        Formatted pipeline of type dict
    """
    pipeline = {
        "team": "genctl",
        "config_file": config_file,
        "vars": pipeline_vars
    }
    return pipeline

def check_overrides(override_key, params_file):
    """
    Checks if an override exists in params/pipeline-overrides.yaml
    If it does, it creates a temp params file in /tmp/
    Args:
        override_key: the name of the pipeline
        params_file: path to pipeline_params.yaml
    Returns:
        The path to the overrides file or pipeline_params.yaml
    """
    #get params path
    path = os.path.realpath(__file__)
    dir = os.path.dirname(path)
    dir = dir.replace("scripts/hotfix", "params")

    override_file = pipeline_overrides_reader.make_file(override_key, dir)
    if (override_file != None):
        params_file = override_file

    return params_file

def deploy(pipelines, concourse_url, username, password, params_file):
    """
    Deploys pipelines to Concourse
    Args:
        pipelines: dict of hotfix pipeline configs
        concourse_url: Url of Concourse on which to put the pipelines
        username: Concourse CLI username
        password: Concourse CLI password
        params_file: Path to the pipeline parameters file
    """
    fly_path = "./fly"
    download_url = f"{concourse_url}/api/v1/cli?arch=amd64&platform=linux"

    logger = logging.getLogger()

    urllib.request.urlretrieve(download_url, fly_path)
    os.chmod(fly_path, os.stat(fly_path).st_mode | stat.S_IEXEC)

    targets = []
    for pipeline, config in pipelines.items():
        var_args = list()
        for name, value in config['vars'].items():
            var_args += ['--var', "{0}={1}".format(name, value)]

        # Login to concourse
        if config['team'] not in targets:
            result = subprocess.call([
                fly_path, 'login',
                '--ca-cert=' + \
                '/etc/pki/ca-trust/source/anchors/ibmcaintermediatecert.crt',
                '--concourse-url', concourse_url,
                '--target', config['team'],
                '--team-name', config['team'],
                '--username', username,
                '--password', password
            ])
            if result != 0:
                logger.error("Concourse login failed")
                exit(1)

            targets.append(config['team'])

        #Cut the version out of pipeline
        no_ver_pipeline_split = pipeline.split("-")
        no_ver_pipeline = ""
        for i in range(len(no_ver_pipeline_split) - 1):
            no_ver_pipeline += no_ver_pipeline_split[i] + "-"

        #Check for overrides
        cp_params_file = check_overrides(no_ver_pipeline[:-1], params_file)

        # Set the pipeline
        subprocess.call(
            [
                fly_path, 'set-pipeline',
                '--non-interactive',
                '--target', config['team'],
                '--pipeline', pipeline,
                '--config', config['config_file'],
                '--load-vars-from', cp_params_file
            ] + var_args
        )

def get_author_email(hotfix_repo_path):
    """
    Finds the email of the author of the last email
    Args:
        hotfix_repo_path: Path to the hotfix repository on the filesystem
    Returns:
        A string of the author's email
    """
    repo = git.Repo(hotfix_repo_path)
    head_commit = repo.head.commit
    email = repo.git.show("-s", "--format=%ae", head_commit.hexsha)

    return email.lower()

def send_summary(slack_token, owners, comp_name, branch_name,
    pipelines, hotfix_repo_path, concourse_url):
    """
    Sends a summary notifcation with branch and pipeline information to the
    author of the PR and any owners specified in the config
    Args:
        slack_token: Token for slack API
        owners: list of owners read from hotfix config
        comp_name: name of the component being fixed
        branch_name: name of the hotfix branch
        pipelines: dict of hotfix pipeline configs
        hotfix_repo_path: Path to the hotfix repository on the filesystem
        concourse_url: Url of Concourse
    """
    logger = logging.getLogger()
    message_lines = [
        "Branch: `{}`".format(branch_name),
        "Pipelines:"
    ]

    for name, properties in pipelines.items():
        url = "{0}/teams/{1}/pipelines/{2}".format(
            concourse_url, properties['team'], name)
        message_lines.append("\t- <{0}|{1}>".format(url, name))

    attachments = [
        {
            "fallback": "{} hotfix pipelines sucessfully created.". \
                format(comp_name),
            "color": "#2ecc71",
            "author_name": "Hotfix Pipelines Successfully Created",
            "text": '\n'.join(message_lines)
        }
    ]
    author = get_author_email(hotfix_repo_path)
    owners = [ owner.lower() for owner in owners ]
    owners.append(author) if author not in owners else owners

    sclient = slack.WebClient(token=slack_token)
    for owner in owners:
        channel = sclient.users_lookupByEmail(email=owner)['user']['id']
        sclient.chat_postMessage(channel=channel, attachments=attachments)
        logger.info(f"Summary notification sent to {owner}")

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
        'SLACK_TOKEN',
        'HOTFIX_REPO_PATH',
        'GENCTL_CI_REPO_PATH',
        'TEMPLATE_CONFIGS_PATH',
        'PARAMS_FILE_PATH',
        'CONCOURSE_URL',
        'CONCOURSE_USER',
        'CONCOURSE_PASS'
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

        pipeline_configs = get_pipeline_configs(args['template_configs_path'])
        pipe_types = ['hotfix-razee']

        for pipe_type in pipe_types:
            if comp_name not in pipeline_configs.keys():
                logger.error("Pipeline config could not be found for " +\
                    f"{comp_name}. Ensure it is referenced in " +\
                    args['template_configs_path'])
                exit(1)

            elif pipe_type not in pipeline_configs[comp_name].keys():
                logger.error(f"{pipe_type} config " +\
                    f"not found for {comp_name}")
                if pipe_type == 'pr': continue
                else: exit(1)

            comp_pipe_config = os.path.join(args['genctl_ci_repo_path'],
                pipeline_configs[comp_name][pipe_type])
            
            comp_pipe_name = f"{comp_name}-{pipe_type}-" + \
                f"{comp_tag}"
            comp_pipe_vars = {
                "workspace-org-name": comp_org,
                "workspace-repo-name": comp_name,
                "workspace-branch": branch_name,
                "hotfix-branch": branch_name,
                "hotfix-version": comp_tag,
                "razee-hotfix": "true",
                "razee-hotfix-nextgen-environment": razee_hotfix_nextgen_environment,
                "genctl-vetted-versions-file": razee_hotfix_nextgen_environment,
                "razee-hotfix-ld-environment": razee_hotfix_ld_environment,
                "hotfix-functional-tests": comp_functional_tests
            }

            pipelines[comp_pipe_name] = format_pipeline(
                comp_pipe_config, comp_pipe_vars)

    # Deploy pipelines to Concourse
    deploy(
        pipelines,
        args['concourse_url'],
        args['concourse_user'],
        args['concourse_pass'],
        args['params_file_path']
    )
    
    # Send slack summary to hotfix owners
    send_summary(
        args['slack_token'],
        owners,
        comp_name,
        branch_name,
        pipelines,
        args['hotfix_repo_path'],
        args['concourse_url']
    )

if __name__ == "__main__":
    main()
