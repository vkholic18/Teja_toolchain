# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020-2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Reads the latest semantic version tag from the workspace, determines which
#    version section needs to be bumped (major, minor, or patch) based on the
#    conventional commit message, and tags a new release with
#    the bumped version
#
# Env:
#    WORKSPACE_PATH: Path to the git repository on the filesystem
#    HOTFIX_VERSION: Version from which a hotfix is being created
#    DEFAULT_BRANCH: The default git branch (typically master or main)
#    GITHUB_API_KEY: Api key to access GitHub API
#    GITHUB_API_URL: Url of GitHub API
#    CREATE_TAG_MODE: The mode of the semver (Should be either semver or gomod)
#
# Use:
#    python3 auto_semver.py
#

import sys
import semver
import logging
import os,sys
import github
import json
import re
from git import Repo, GitCommandError
from changelog_updater import parse_issues


# Constants
TAGGED_BRANCHES = ['master', 'dev-integration', 'temp_dev-integration_temp']
PRE_RELEASE_TOKEN = "dev"
DEFAULT_VERSION = "1.0.0"
BUMP_TYPES = {
    "minor": {
        "feat",
        "refactor",
        "chore",
        "vuln",
        "fix",
        "docs"
    },
    "patch": {}
}
RELEASE_REGEX = r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$'
CREATE_TAG_MODES = ['semver','gomod']

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


def parse_hotfix_version(hotfix_ver):
    """
    Parses and returns the major/minor version of the hotfix version
    Args:
        hotfix_ver: Inputted hotfix version
    Returns:
        Major/minor version of the hotfix version
    """
    logger = logging.getLogger()
    dot_count = hotfix_ver.count('.')

    if dot_count == 2:
        hotfix_ver = hotfix_ver[:hotfix_ver.rindex('.')+1]
    elif dot_count != 1:
        logger.error(f"Invalid hotfix version {hotfix_ver}")
        exit(1)

    logger.info(f"Parsed hotfix major/minor version: {hotfix_ver}")
    return hotfix_ver


def generate_commit_regex():
    """
    Generates a conventional commit regex pattern from the bump_types const
    Returns:
        Regex pattern string
    """
    change_types = list()

    for bump_type in BUMP_TYPES.items():
        change_types += bump_type[1]

    return f"({'|'.join(change_types)})(!)?(\\(.+\\))?:.+"


def parse_bump_type(commit_message):
    """
    Parses the conventional commit message to determine which version section
    should be bumped (major, minor, or patch)
    Args:
        commit_message: Commit message string
    Returns:
        Version section to be bumped
    """
    logger = logging.getLogger()
    logger.info("Parsing commit for change type")

    regex = re.compile(generate_commit_regex())
    commit_message_lines = list(filter(None, commit_message.splitlines()))

    logger.info(f"Commit message:{commit_message_lines}")

    for message in commit_message_lines:
        match = regex.match(message)
        if match:
            if match.group(2):
                logger.info("Breaking change; bumping major version")
                return "major"

            elif match.group(1):
                for bump_type, change_types in BUMP_TYPES.items():
                    if match.group(1) in change_types:
                        logger.info(f"Change type: {match.group(1)}; " +
                                    f"bumping {bump_type} version")
                        return bump_type

        elif len(commit_message_lines) == 1:
            logger.error(f"Commit message, \"{commit_message.strip()}\" " +
                         "not in conventional format")
            exit(1)
    # This code was added to ensure there is logging being output in case the other checks are not hit.
    logger.warning("Failed to match a case for bump type, is it in conventional commit format?")

def validate_tag(latest_tag_name, tags, sha):
    """
    Validates whether the current commit sha is already tagged
    Args:
        latest_tag_name: The name of the latest tag
        tags: List of all tag objects from repo
        sha: Latest commit sha
    """
    logger = logging.getLogger()
    latest_tag = next((t for t in tags if t.name == latest_tag_name))
    current_commit_sha = sha

    if str(latest_tag.commit.sha) == current_commit_sha:
        logger.warning(f"Current commit, {current_commit_sha} " +
                       f"already tagged as latest version, {latest_tag}")


def get_branch_head_tag(repo, active_branch="master"):
    """
    If the active branch head has a tag, returns it, if not, returns None
    Args:
        repo: gitPython repo object
        active_branch: Name of the branch to get the head commit from
    Returns:
        Either None or the tag found for the branch head
    """
    # Assume there is no tag
    result = None

    logger = logging.getLogger()
    branch_head_commit = repo.get_branch(active_branch).commit.sha
    logger.info(f"Will check if there is already a tag for commit {branch_head_commit}")
    branch_tags = repo.get_tags()
    for tag in branch_tags:
        if tag.commit.sha == branch_head_commit:
            logger.info(f"Found tag {tag.name} for commit {branch_head_commit}")
            result = tag.name
    
    # Return
    return result

def is_valid_semver(tag,tag_mode):
    """
    Determines whether the given tag is valid semver
    Args:
        tag: Tag string
    Returns
        True/False whether the tag is valid semver
    """
    logger = logging.getLogger()

    try:
        if tag_mode == 'gomod':
            tag = tag.lstrip("v")
        semver.VersionInfo.parse(tag)
        return True

    except ValueError:
        logger.info(f"{tag} does not match expected format")
        return False


def get_all_tagged_branches_commits(gh_repo, tagged_branches):
    """
    Get all unique sorted commits from the supported tagged branches
    Args:
        gh_repo pyGithub repo object

    Returns:
        list of commits sorted by commit datetime
    """
    all_commits = []
    branch_names = [branch.name for branch in gh_repo.get_branches()]
    for branch in tagged_branches:
        if branch in branch_names:
            for commit in gh_repo.get_commits(sha=branch):
                if commit not in all_commits:
                    all_commits.append(commit)

    # sort commits by the commit datetime
    all_commits.sort(key=lambda c: c.commit.committer.date, reverse=True)
    return all_commits


def get_latest_tag(git_repo, gh_repo, tagged_branches,tag_mode,branch="", validate=True, base_tag=None, tag_regex=None):
    """
    Parses the git repository for the latest tag
    Args:
        git_repo: gitPython repo object to parse
        gh_repo: pyGithub repo object
        branch: Name of branch to parse for tags
        validate: Validate whether the current commit is tagged with latest
        tag_regex: If we want to use a regex to locate a tag variation - pre-release/release format
    Returns
        Latest tag name
    """
    # Note that this function is intended to fail in such a case where:
    # - dev-integration, master, and hotfix (stable) branches are not the only things that are tagged
    # In other words, the logic specifically looks at the values in the "TAGGED_BRANCHES" variable, and will create
    # a new tag based on the latest tag between the branch(es) in that variable.
    # This cannot conflict with stable branches (hotfixes) because those bump the X in 1.0.X,
    # whereas bumps to the TAGGED_BRANCHES branches bump the X in 1.X.0.
    # Ex. If branch "helloworld" has a tag of 1.1.0, and the latest between TAGGED_BRANCHES is "1.0.0", the code will
    # encounter an error, trying to tag 1.1.0.
    logger = logging.getLogger()
    on_branch = f" on {branch}" if branch else ""
    logger.info(f"Parsing repo for latest tag{on_branch}")
    commits = None
    if branch:
        commits = gh_repo.get_commits(sha=branch)
    else:
        commits = get_all_tagged_branches_commits(gh_repo,tagged_branches)
    tags = gh_repo.get_tags()

    latest_tag = None
    for commit in commits:
        for tag in tags:
            if commit == tag.commit and is_valid_semver(tag.name,tag_mode):
                if base_tag:
                    if tag.name.startswith(base_tag):
                        latest_tag = tag.name
                        break
                if tag_regex:
                    if re.match(tag_regex, tag.name):
                        latest_tag = tag.name
                        break    
                else:
                    latest_tag = tag.name
                    break

        if latest_tag:
            break

    if latest_tag and validate:
        validate_tag(
            latest_tag,
            tags,
            git_repo.head.object.hexsha
        )

    logger.info(f"Latest tag: {latest_tag}")
    return latest_tag


def bump_tag(previous_tag, bump_type):
    """
    Bumps the appropriate version section in the given tag
    If previous tag is empty, returns DEFAULT_VERSION
    Args:
        previous_tag: The tag string to be bumped
        bump_type: The version section to be bumped
    Returns:
        The updated tag string
    """
    if previous_tag:
        version = semver.VersionInfo.parse(previous_tag.lstrip("v"))
        if not bump_type:
            return strip_pre_rel(str(version))

        if bump_type == "prerelease":
            return str(version.bump_prerelease(token=PRE_RELEASE_TOKEN))
        return str(eval(f"version.bump_{bump_type}()"))

    else:
        logger = logging.getLogger()
        logger.info("Existing tag not found; " +
                    f"using default version, {DEFAULT_VERSION}")
        return DEFAULT_VERSION


def parse_org_repo_name(repo):
    """
    Parses org name and repo name from gitPython repo object
    Args:
        repo: gitPython repo object
    Returns:
        touple with org name and repo name
    """
    repo_url = repo.remote("origin").url

    # This is to support One-Pipeline way of cloning repos
    if repo_url.startswith("https://x-oauth-basic"):
        org_and_repo = repo_url.split("github.ibm.com/")[1]
        return org_and_repo.split("/")[0], org_and_repo.split("/")[1]
    else:
        url_regex = r'^(git@[^\/]+:)?(.+:\/\/[^\/]+\/)?([^\/]+)\/([^\/]+).git$'
        regex = re.compile(url_regex)
        match = regex.match(repo_url)
        return match.group(3), match.group(4)


def create_tag(repo, tag_name):
    """
    Creates and pushes a tag at the currently checked out commit
    Args:
        repo: gitPython repo object to parse
        tag_name: The name of the tag to create
    """
    logger = logging.getLogger()
    commit_sha = repo.head.object.hexsha

    msg_for_create_tag = repo.head.commit.message
    print(f"Head commit message length is {len(msg_for_create_tag)}")

    maximum_chars_to_allow = int(sys.maxsize / 10)

    print(f"Max chars to allow {maximum_chars_to_allow}")
    try:
        tag = repo.create_tag(
            tag_name,
            ref=commit_sha,
            message=(repo.head.commit.message[:65461])
        )
    except GitCommandError as gce:
        logger.error(gce.stderr)
        exit(1)

    # Capture the output of the command, so we can check if there was an issue with the push.
    # Necessary because the command won't result in a python error if there is a failure.
    info = repo.remotes.origin.push(tag)
    if info is not None:
        if "new tag" in info[0].summary:
            logger.info(f"Successfully tagged {commit_sha} with {tag_name}")
        else:
            logger.error(f"Failed to push the tag {tag_name} to {commit_sha}")
            logger.error(f"{info[0].summary}")
            exit(1)
    else:
        logger.error("info was null (None)")
        exit(1)


def format_table_row(key, value):
    """
    Formats an HTML row for the release notes
    Args:
        key: Key in the table row
        value: Value in the table row
    Returns:
        Formatted string of HTML
    """
    return f"<tr><td width=\"2%\"><b>{key}</b></td>" +\
        f"<td width=\"20%\">{value}</td></tr>"


def create_gh_release(gh_repo, tag_name, branch, issues):
    """
    Creates a github tag and release with the given name
    Args:
        gh_repo: Github repo object
        tag_name: Name of the tag/release to create
        branch: Name of the active branch
        issues: List of Jira issues resolves by this version
    """
    logger = logging.getLogger()

    release_body = '<table width="100%">' +\
        format_table_row("Branch", branch) +\
        format_table_row("Tag", tag_name) +\
        format_table_row("Resolves", ', '.join(issues)) +\
        "</table>"
    
    logger.info(f"Will try to create git release {tag_name} on branch {branch}")
    logger.info(f"The release body HTML is the following: ")
    logger.info(f"{str(release_body)}")

    gh_repo.create_git_release(
        tag=tag_name,
        name=tag_name,
        message=release_body
    )

    logger.info(f"Successfully released {tag_name}")


def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'WORKSPACE_PATH',
        'GITHUB_API_KEY',
        'GITHUB_API_URL',
        'DEFAULT_BRANCH',
        'CREATE_TAG_MODE'
    ]

    optional_vars = [
        'HOTFIX_VERSION',
        'CHANGELOG_CONFIG_PATH',
        'SKIP_RELEASE'  ,
        'ENABLE_TAG_CREATION_IN_ANY_BRANCH' ,
        'AUTO_SEMVER_DRY_RUN_MODE'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)
        
        if var == 'CREATE_TAG_MODE' and os.environ[var] not in CREATE_TAG_MODES:
            logger.error(f"CREATE_TAG_MODE should be one of the following: {str(CREATE_TAG_MODES)}")
            exit(1)

    for var in optional_vars:
        if var in os.environ.keys():
            args[var.lower()] = os.environ[var]
        else:
            args[var.lower()] = ""

    return args


def strip_pre_rel(tag):
    """
    Strips pre-release and build information from semver tag
    Args:
        tag: Semver tag string
    Returns
        Tag with only major, minor, and patch version
    """
    ver = semver.VersionInfo.parse(tag)
    return f"{ver.major}.{ver.minor}.{ver.patch}"


def parse_pre_rel_tag(master_tag, branch_tag, bump_type):
    """
    Parses pre-release tag to determine basis for next pre-release version
    Args:
        master_tag: Latest tag on default branch
        branch_tag: Latest tag on current branch
        bump_type: Type of bump based on conventional commit
    Returns:
        Base version for pre-release bump
    """
    if not branch_tag:
        return DEFAULT_VERSION
    if not master_tag:
        return branch_tag

    stripped_branch_tag = strip_pre_rel(branch_tag)
    bumped_master_tag = bump_tag(master_tag, bump_type)

    ver_comp = semver.compare(stripped_branch_tag, bumped_master_tag)
    if ver_comp >= 0:
        return branch_tag
    else:
        return bumped_master_tag


def get_active_branch(repo):
    """
    Gets the current branch
    Args:
        repo: gitPython repo object
    Returns:
        The name of the branch
    """
    commit_sha = repo.head.object.hexsha
    branches = repo.git.branch(contains=commit_sha).splitlines()
    for branch in branches:
        if branch.strip() == DEFAULT_VERSION:
            return DEFAULT_VERSION
    if len(branches) == 1:
        active_branch = branches[0].replace("*", "").strip()
    else:
        active_branch = branches[1].strip()
    return active_branch


def output_changelog_config(file_path, repo_name, tag_name, branch, issues):
    """
    Outputs the changelog config json file
    Args:
        file_path: Path to the json file
        repo_name: Name of the repository
        tag_name: Name of the current tag
        branch: Name of the active branch
        issues: List of Jira issues resolves by this version
    """
    config = {
        "repo_name": repo_name,
        "current_tag": tag_name,
        "branch": branch,
        "issues": issues
    }

    with open(file_path, 'w') as f:
        json.dump(config, f)

def release_exists_for_a_tag(gh_repo, tag_to_check):
    logger = logging.getLogger()
    logger.info(f"Will check if there is already a release for tag {tag_to_check}")

    # Initially assume there is no existing release
    existing_release = None

    # Try to get existing release if any
    try:
        existing_release = gh_repo.get_release(tag_to_check)
    except github.GithubException as e:
        logger.info(f"Could not find a GH release for tag {tag_to_check}")
    
    if existing_release is None:
        return False
    else:
        return True    

def main():
    logger = set_up_logger()
    args = parse_env()

    tagged_branches = ['dev-integration', args['default_branch'], 'temp_dev-integration_temp']

    repo = Repo(args['workspace_path'])
    commit_message = repo.head.commit.message
    active_branch = get_active_branch(repo)
    bump_type = None

    gh = github.Github(
        login_or_token=args['github_api_key'],
        base_url=args['github_api_url']
    )
    org_name, repo_name = parse_org_repo_name(repo)
    gh_repo = gh.get_repo(f"{org_name}/{repo_name}")
    logger.info(f"Active branch is {active_branch}")
    
    # Initialize base_tag in None which is the default
    base_tag = None
    
    # If we are in gomod mode add the V prefix
    if args['create_tag_mode'] == 'gomod':
        base_tag = 'v'

    # Hotfixes
    if args['hotfix_version']:
        logger.info("This version is a hotfix")
        hotfix_ver = parse_hotfix_version(args['hotfix_version'])
        previous_tag = get_latest_tag(
            repo, gh_repo, tagged_branches,args['create_tag_mode'],active_branch, True, hotfix_ver)
        bump_type = "patch"

    # Integration branches
    elif active_branch != args['default_branch']:
        if active_branch not in tagged_branches:
            logger.info(f"Current branch {active_branch} is not any of the following: {str(tagged_branches)}")
            if args['enable_tag_creation_in_any_branch'] == "true":
                logger.info("However, ENABLE_TAG_CREATION_IN_ANY_BRANCH is true, so continue with Auto-Semver")
            else:
                logger.info(f"By default, we only allow creation of tags for the following branches: {str(tagged_branches)} and for hotfixes")
                logger.info(f"If you still want to create tag for branch {active_branch}, use flag of ENABLE_TAG_CREATION_IN_ANY_BRANCH")
                sys.exit(0)
            
        logger.info("This version is a pre-release")
        prev_master_tag = get_latest_tag(
            repo, gh_repo, tagged_branches,args['create_tag_mode'],args['default_branch'], False,base_tag)
        prev_pre_rel_tag = get_latest_tag(repo, gh_repo, tagged_branches,args['create_tag_mode'],active_branch,base_tag=base_tag)
        bump_type = parse_bump_type(commit_message)

        previous_tag = parse_pre_rel_tag(
            prev_master_tag, prev_pre_rel_tag, bump_type
        )
        bump_type = "prerelease"

    else:
        previous_tag = get_latest_tag(repo, gh_repo, tagged_branches,args['create_tag_mode'],base_tag=base_tag)
        if previous_tag and PRE_RELEASE_TOKEN not in previous_tag:
            bump_type = parse_bump_type(commit_message)

    if bump_type != "prerelease":
        previous_tag_on_branch = get_latest_tag(
            repo, gh_repo, tagged_branches,args['create_tag_mode'],active_branch,False,base_tag,RELEASE_REGEX)

    new_tag = bump_tag(previous_tag, bump_type)
    
    # For "gomod" mode, we need to add the v prefix
    if args['create_tag_mode'] == 'gomod':
        new_tag = f"v{new_tag}"

    logger.info(f"Bump type: {bump_type}")
    branch_head_tag = get_branch_head_tag(gh_repo, active_branch)
    
    # Create tag if needed
    if branch_head_tag is not None:
        logger.info(f"tag {branch_head_tag} already exists for sha {repo.head.object.hexsha}; no need to create tag")
        logger.info(f"This AutoSemver run seems to be a re-run on same commit that we already run...")
        
        # If is not prerelease, prepare vars used in release
        if bump_type != "prerelease":
            # This gives us last tag
            tag_to_use_for_release_to = branch_head_tag
            
            # This should give us the previous tag before the last
            all_tags=gh_repo.get_tags()
            tag_to_use_for_release_from = [t.name for t in list(all_tags) if PRE_RELEASE_TOKEN not in t.name][1]
    else:
        if args['auto_semver_dry_run_mode'] == "true":
            logger.info(f"We are in dry run mode !!! - We would have created tag {new_tag}")
        else:
            create_tag(repo, new_tag)

            # If is not prerelease, prepare vars used in release
            if bump_type != "prerelease":
                tag_to_use_for_release_to = new_tag
                tag_to_use_for_release_from = previous_tag_on_branch

    # Handle GH release
    if args['auto_semver_dry_run_mode'] == "true":
        logger.info(f"We are in dry run mode !!! - In dry run mode we don't handle GH releases")
    else:
        # only release a version on master merge releases
        if bump_type != "prerelease":
            logger.info("Parsing Jira issues from " +
                        f"{tag_to_use_for_release_from} -> {tag_to_use_for_release_to}")
            issues = parse_issues(
                args['github_api_key'],
                f"{org_name}/{repo_name}",
                tag_to_use_for_release_from,
                tag_to_use_for_release_to
            )
            if 'changelog_config_path' in args.keys():
                output_changelog_config(
                    args['changelog_config_path'],
                    repo_name, tag_to_use_for_release_to, active_branch, issues)
            # releasing a hotfix version causes the release page sorting to be off
            # the releases are sorted by date
            if not args['hotfix_version'] and args['skip_release'] == "false":
                if release_exists_for_a_tag(gh_repo,tag_to_use_for_release_to):
                    logger.info(f"A release already exists for tag {tag_to_use_for_release_to}")
                else:
                    logger.info(f"Creating a new release: {tag_to_use_for_release_to}")
                    create_gh_release(gh_repo, tag_to_use_for_release_to, active_branch, issues)

if __name__ == "__main__":
    main()
