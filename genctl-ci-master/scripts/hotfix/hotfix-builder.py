# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
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
#    ONEOFF_CONFIGS_PATH: Path to the one-off config yaml
#    TEMPLATE_CONFIGS_PATH: Path to the template config yaml
#    PARAMS_FILE_PATH: Path to the pipeline parameters file
#    MAJOR_COMPS_PATH: Path to the major components config yaml
#    MINOR_COMPS_PATH: Path to the minor components config yaml
#    VV_REPO: org_name/repo_name of the vetted versions repo
#    CONCOURSE_URL: Url of Concourse on which to put the pipelines
#    CONCOURSE_USER: Concourse CLI username
#    CONCOURSE_PASS: Concourse CLI password
#    DEPLOYED_ENVS_PATH: Path to the deployed environments directory
#    CI_INTEG_ENV: Name of the vetted-versions env CI uses for integration
#    SMOTAINER_COMP_NAME: Name of the smotainer component in vetted-versions
#
# Use:
#    python3 hotfix-builder.py
#
# Shorthand:
#    maj: major
#    min: minor
#    comp: component
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

def get_deployed_versions(env, deployed_environments_path):
    """
    Retireves the versions in the nextgen-envs repo for the given env
    Args:
        env: Enviornment name
        deployed_environments_path: Path to the deployed environments directory
    Returns:
        A dictionary of components and versions
    """
    version_file_path = os.path.join(deployed_environments_path, f"{env}.yaml")

    with open(version_file_path) as f:
        deployed_versions = yaml.safe_load(f)

    return deployed_versions

def get_smotainer_version(vv_repo, ci_integ_env, smotainer_comp_name):
    """
    Retrieves the smotainer versions in the pre-integration environment
    Args:
        vv_repo: Vetted-versions github repo object
        ci_integ_env: Name of the vetted-versions env CI uses for integration
        smotainer_comp_name: Name of the smotainer component in vetted-versions
    Returns:
        The version of the smotainer
    """
    ci_integ_versions_str = vv_repo.get_contents(
        f"{ci_integ_env}.yaml").decoded_content
    ci_integ_versions = yaml.safe_load(ci_integ_versions_str)

    return ci_integ_versions['version'][smotainer_comp_name]

def find_min_comp_sha(min_comp_name, maj_comp_repo, branch_name,
        inventory_config, min_comp_mappings):
    """
    Determines the minor component sha from the inventory in the maj comp repo
    Args:
        min_comp_name: Name of the minor component
        maj_comp_repo: Major component GitHub repo object
        branch_name: The name of the stable branch
        inventory_config: The configuration of the major component inventory
    Returns
        The sha of the minor component
    """
    if inventory_config['type'] == 'submodules':
        submodule = maj_comp_repo.get_contents(min_comp_name, ref=branch_name)
        return submodule.raw_data.get('sha')

    elif inventory_config['type'] in ['json_file', 'yaml_manifest']:
        file_path = inventory_config['path']
        inv_file_str = maj_comp_repo.get_contents(
            file_path, ref=branch_name).decoded_content

        if inventory_config['type'] == 'json_file':
            inv_file = json.loads(inv_file_str)
            return inv_file[min_comp_name]['hash']

        elif inventory_config['type'] == 'yaml_manifest':
            manifest = yaml.safe_load(inv_file_str)
            comp_name = min_comp_mappings[min_comp_name]

            for config_type in manifest:
                for config, components in config_type.items():
                    if config == 'artifacts':
                        for component in components:
                            if component['name'] == comp_name:
                                version = component['version']
                                break

                    elif config == 'tools':
                        for component in components:
                            if component['tool_name'] == comp_name:
                                version = component['tool_version']
                                break

            return version.split('_')[-1]


def create_branch(repo, branch_name, sha):
    """
    Creates a branch on the given repo off the given sha
    Args:
        repo: Github Repo object
        branch_name: Name of the branch to be created
        sha: Commit sha off of which the branch is created
    """
    logger = logging.getLogger()

    # Convert short sha to full sha
    if len(sha) == 7:
        sha = repo.get_commit(sha=sha).sha

    try:
        repo.get_branch(branch_name)
        branch_exists = True

        logger.info(f"{branch_name} already exists on {repo.name}")

    except github.GithubException as e:
        if 'Branch not found' in str(e):
            branch_exists = False
            pass
        else:
            logger.error(f"Could not access {repo.name}. " +\
            "Ensure the CI user has collaborator access.")
            exit(1)

    if not branch_exists:
        try:
            repo.create_git_ref(
                ref='refs/heads/' + branch_name,
                sha=sha
            )
        except github.GithubException as e:
            logger.error(f"Could not create branch on {repo.name}. " +\
            "Ensure the CI user has collaborator access.")
            exit(1)

        logger.info(f"Created {branch_name} branch from {sha} on {repo.name}")

def get_pipeline_configs(oneoff_configs_path, template_configs_path):
    """
    Retrieves the pipeline config mapping from the pipeline config repo
    Args:
        oneoff_configs_path: Path to the one-off config yaml
        template_configs_path: Path to the template config yaml
    Returns:
        Merged dictionary of the one-off and templatized pipelines
    """
    with open(oneoff_configs_path) as f:
        oneoff_pipes = ruamel.yaml.safe_load(f)

    with open(template_configs_path) as f:
        template_pipes = ruamel.yaml.safe_load(f)

    configs = dict()
    for pipelines in [oneoff_pipes, template_pipes]:
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
                '--ca-cert=' +\
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

        # Set the pipeline
        subprocess.call(
            [
                fly_path, 'set-pipeline',
                '--non-interactive',
                '--target', config['team'],
                '--pipeline', pipeline,
                '--config', config['config_file'],
                '--load-vars-from', params_file
            ] + var_args
        )

        # Unpause the pipeline
        subprocess.call([
            fly_path, 'up',
            '--target', config['team'],
            '--pipeline', pipeline
        ])

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

def send_summary(slack_token, owners, maj_comp_name, branch_name,
    pipelines, hotfix_repo_path, concourse_url):
    """
    Sends a summary notifcation with branch and pipeline information to the
    author of the PR and any owners specified in the config
    Args:
        slack_token: Token for slack API
        owners: list of owners read from hotfix config
        maj_comp_name: name of the major component being fixed
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
            "fallback": "{} hotfix pipelines sucessfully created.".\
                format(maj_comp_name),
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
        'ONEOFF_CONFIGS_PATH',
        'TEMPLATE_CONFIGS_PATH',
        'PARAMS_FILE_PATH',
        'MAJOR_COMPS_PATH',
        'MINOR_COMPS_PATH',
        'VV_REPO',
        'CONCOURSE_URL',
        'CONCOURSE_USER',
        'CONCOURSE_PASS',
        'CI_INTEG_ENV',
        'SMOTAINER_COMP_NAME'
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
    maj_comps = load_yaml(args['major_comps_path'])
    min_comp_mappings = load_yaml(args['minor_comps_path'])

    # Retrieve latest hotfix file added to the hotfix repo
    hotfix = get_hotfix(args['hotfix_repo_path'])
    env = hotfix.get('environment')
    vv_env = None
    # if env doesn't exist, make sure vv_environment exists
    if not env:
        if hotfix.get('vv_environment'):
            vv_env = hotfix['vv_environment']
        else:
            print('environment or vv_environment does not exist')
            exit(1)
    # Default mds_config is mzone_mds_config_template
    if 'mds_config' in hotfix:
        mdsconfig = hotfix['mds_config']
    else:
        mdsconfig = 'mzone_mds_config_template'
    # Default genctl_release_build is prepare-release-bundle.yaml file
    if 'genctl_release_build' in hotfix:
        genctlreleasebuild = hotfix['genctl_release_build']
    else:
        genctlreleasebuild = 'prepare-genctl-release-bundle'

    # Default genctl_release_method is 'no-orda'
    if 'genctl_release_method' in hotfix:
        genctlreleasemethod = hotfix['genctl_release_method']
    else:
        genctlreleasemethod = 'no-orda'

    # Default genctl_release_branch is master
    genctlreleasebranch_major = 'master'
    genctlreleasebranch_minor = 'master'

    owners = hotfix['owners'] if 'owners' in hotfix.keys() else list()

    maj_comp_name = hotfix['major_component']['name']
    if 'sha' in hotfix['major_component']:
        maj_comp_sha = hotfix['major_component']['sha']
    elif 'release' in hotfix['major_component']:
        maj_comp_sha = hotfix['major_component']['release'].split('_')[-1]

    min_comps = list()
    if 'minor_components' in hotfix.keys():
        min_comps = hotfix['minor_components']

    pipelines = dict()
    branch_name = 'stable-' + maj_comp_sha[0:8]

    # Create infrastructure for major components
    maj_comp_config = maj_comps[maj_comp_name]

    # Create branch on major component repo
    maj_comp_repo = gh.get_repo(maj_comp_config['repository'])
    create_branch(maj_comp_repo, branch_name, maj_comp_sha)

    # Create major component pipeline(s)
    maj_comp_org_name = maj_comp_config['repository'].split('/')[0]
    maj_comp_repo_name = maj_comp_config['repository'].split('/')[1]

    # If major_comp is genctl (non-orda), use the stable branch for genctl-release
    if maj_comp_name == 'genctl':
        genctlreleasebranch_major = branch_name

    for pipe_type, pipe_config in maj_comp_config['pipeline_config'].items():
        maj_pipe_name = f"{maj_comp_name}-release" +\
            f"{'-bundle' if maj_comp_name == 'genctl' else ''}" +\
            f"-{pipe_type}-hotfix-{maj_comp_sha[0:8]}"
        maj_pipe_config = os.path.join(
            args['genctl_ci_repo_path'], pipe_config)
        maj_pipe_vars = {
            "workspace-org-name": maj_comp_org_name,
            "workspace-repo-name": maj_comp_repo_name,
            "workspace-branch": branch_name,
            "hotfix-branch": branch_name,
            "release-branch": branch_name,
            "genctl-vetted-versions-file": f"{env}.yaml" if env else f"{vv_env}.yaml",
            "mds-config-template-file": mdsconfig + '.yaml',
            "genctl-release-bundle-build-file": genctlreleasebuild + '.yaml',
            "genctl-release-branch": genctlreleasebranch_major,
            "genctl-release-method": genctlreleasemethod
        }
        pipelines[maj_pipe_name] = format_pipeline(
            maj_pipe_config, maj_pipe_vars)

    # Create infrastructure for minor components
    for min_comp in min_comps:
        min_comp_org_repo = min_comp['name']
        min_comp_org = min_comp_org_repo.split('/')[0]
        min_comp_name = min_comp_org_repo.split('/')[1]

        maj_comp_inv_config = maj_comp_config['inventory']

        # Allow user to override minor component sha
        if 'sha' in min_comp.keys():
            min_comp_sha = min_comp['sha']
        else:
            min_comp_sha = find_min_comp_sha(min_comp_name, maj_comp_repo,
                branch_name, maj_comp_inv_config, min_comp_mappings)

        # Create branch on minor component repo
        min_comp_repo = gh.get_repo(min_comp_org_repo)
        create_branch(min_comp_repo, branch_name, min_comp_sha)

        # Change min_comp_name to 'genctl-release-hotfix-legacy' to read the legacy pipeline config
        min_comp_name_orig = min_comp_name
        if maj_comp_name == 'genctl-orda-legacy' and min_comp_name == 'genctl-release':
            min_comp_name = 'genctl-release-hotfix-legacy'

        # Create minor component pipeline(s)
        pipeline_configs = get_pipeline_configs(args['oneoff_configs_path'],
            args['template_configs_path'])

        pipe_types = ['merge']
        if maj_comps[maj_comp_name]['create_minor_pr_pipeline']:
            pipe_types.append('pr')

        for pipe_type in pipe_types:
            if min_comp_name not in pipeline_configs.keys():
                logger.error("Pipeline config could not be found for " +\
                    f"{min_comp_name}. Ensure it is referenced in " +\
                    args['oneoff_configs_path'])
                exit(1)

            elif pipe_type not in pipeline_configs[min_comp_name].keys():
                logger.error(f"{pipe_type} config " +\
                    f"not found for {min_comp_name}")
                if pipe_type == 'pr': continue
                else: exit(1)

            min_pipe_config = os.path.join(args['genctl_ci_repo_path'],
                pipeline_configs[min_comp_name][pipe_type])

            # Restore the min_comp_name to not affect the further flow
            min_comp_name = min_comp_name_orig

            min_pipe_name = f"{min_comp_name}-{pipe_type}-" +\
                f"hotfix-{maj_comp_sha[0:8]}"
            min_pipe_vars = {
                "workspace-org-name": min_comp_org,
                "workspace-repo-name": min_comp_name,
                "workspace-branch": branch_name,
                "hotfix-branch": branch_name,
                "hotfix-major-component": maj_comp_name,
                "genctl-vetted-versions-file": f"{env}.yaml" if env else f"{vv_env}.yaml",
                "ddt-config-template-file": ddtconfig + '.hjson',
                "genctl-release-bundle-build-file": genctlreleasebuild + '.yaml',
                "genctl-release-branch": genctlreleasebranch_minor,
                "genctl-release-method": genctlreleasemethod
            }
            if 'branch_var_override' in maj_comps[maj_comp_name]:
                branch_var = maj_comps[maj_comp_name]['branch_var_override']
                min_pipe_vars[branch_var] = branch_name

            pipelines[min_pipe_name] = format_pipeline(
                min_pipe_config, min_pipe_vars)

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
        maj_comp_name,
        branch_name,
        pipelines,
        args['hotfix_repo_path'],
        args['concourse_url']
    )

if __name__ == "__main__":
    main()
