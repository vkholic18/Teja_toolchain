# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#   Contains functions to facilitate generating and updating the nextgen
#   cloud changelog
#

import logging
import os
import ruamel.yaml
import subprocess
import semver
import github

from io import StringIO

# Constants
TEMPLATE_PATH="changelog.tmpl"


def read_markdown(contents):
    """
    Reads GH page markdown and translates to dict
    Args:
        file_path: Path to GH page markdown file
    Returns:
        changelog dict
    """
    yaml_str = contents.decode("utf-8").replace("---", "")
    return ruamel.yaml.round_trip_load(yaml_str)
    

def get_changelog_page(repo, component_type, component_name):
    """
    Gets changelog page data
    Returns template if it doesn't already exist
    Args:
        repo_path: Path to GH page git repository
        component: Name of the component
    Returns:
        changelog dict
    """
    file_path = os.path.join(component_type, f"{component_name}.md")

    try:
        file = repo.get_contents(file_path)
        return read_markdown(file.decoded_content), file.sha

    except github.UnknownObjectException:
        file = repo.get_contents(TEMPLATE_PATH)
        template = read_markdown(file.decoded_content)
        template['title'] = component_name
        template['parent'] = component_type.capitalize()
        template['permalink'] = f"/{component_type}/{component_name}"
        return template, None


def format_markdown(contents):
    """
    Writes GH page markdown from dict
    Args:
        contents: Contents of changelog dict
    """
    str_contents = ruamel.yaml.round_trip_dump(contents)
    return f"---\n{str_contents}---"


def parse_issues(api_key, component, last_tag, curr_tag):
    """
    Parses Jira issues between tags
    Args:
        api_key: GitHub api key
        component: Name of the component
        last_tag: Tag from previous commit
        curr_tag: Tag from current commit
    Returns:
        List of Jira issues
    """
    logger = logging.getLogger()

    # This code appears to operate such that: if there is not a current tag, instead of erring out,
    # write an empty string to the changelog.
    if not curr_tag and last_tag:
        return list()

    # Covers the case where there were not any existing tags in the repo. The tag would be created but would result
    # in an error when attempting to create the changelog since there wouldn't be a last_tag without this code chunk
    if not last_tag:
        return list()

    last_tags = last_tag.split('/')
    curr_tags = curr_tag.split('/')

    if len(last_tags) != len(curr_tags):
        logger.error("Previous and current env have different number of tags")
        raise Exception

    env = dict(os.environ, GITHUB_API_KEY=api_key)

    issues = list()
    for i in range(0, len(curr_tags)):
        base = last_tags[i]
        head = curr_tags[i]

        try:
            str_issues = subprocess.check_output([
                "changeloggen",
                "generate",
                "-n", component,
                "-b", base,
                "-v", head
            ], env=env).decode("utf-8").strip('\n')

            logger.info(f"Parsed issues: {str_issues}")
            issues += str_issues.split(', ')

        except:
            logger.warning(f"Unable to parse issues for {base} -> {head}")

    return list(dict.fromkeys(issues)) # Remove duplicates


def find_release_index(name, release_page):
    """
    Finds at which index a release belongs in the changelog based on semver
    Args:
        name: Name of release
        release_page: Release page dict
    Returns:
        Index number
    """
    logger = logging.getLogger()

    try:
        for idx, rel in enumerate(release_page['releases']):
            ver_comp = semver.compare(name.strip('v'), rel['name'].strip('v'))
            if ver_comp > 0:
                return idx
            elif ver_comp == 0:
                logger.error(f"{name} already exists in log")
                exit(1)

    except ValueError:
        pass
    
    return 0

def update_changelog_repo(repo, path, page, sha):
    """
    Updates or creates the changelog file in the github repository
    Args:
        repo: GitHub repo object
        path: Path to the changelog file
        page: Contents of the changelog page
        sha: Commit sha of the previous commit
    """
    contents = format_markdown(page)

    if sha:
        repo.update_file(
            path,
            f"Update {path}",
            contents,
            sha
        )

    else:
        repo.create_file(
            path,
            f"Create {path}",
            contents
        )


def update_changelog(changelog_org_repo, component_type, component_name,
    version, tag, branch, gh_url, gh_token, issues=None):
    """
    Updates the changelog for a component with the new release
    Args:
        changelog_repo_path: Path to the changelog repo on disk
        component_type: Type of the components, e.g. bundles, workspaces
        component_name: Name of the component
        version: The new version to add
        tag: The tag of the new version (sometimes ==version)
        branch: The name of the branch from which this version was released
        gh_url: The GitHub API endpoint
        gh_token: Token for the GitHub API
        issues: List of Jira issues resolved by new version
    """
    logger = logging.getLogger()
    gh = github.Github(login_or_token=gh_token, base_url=gh_url)
    repo = gh.get_repo(changelog_org_repo)

    rel_page, sha = get_changelog_page(
        repo,
        component_type,
        component_name
    )

    index = find_release_index(version, rel_page)
    if gh_token and type(issues) is type(None):
        issues = parse_issues(
            gh_token,
            component_name,
            rel_page['releases'][index]['tag'],
            tag
        )

    release = {
        "name": version,
        "branch": branch,
        "tag": tag,
        "issues": issues
    }

    logger.info(f"Inserting {component_name} at index {index}")
    rel_page['releases'].insert(index, release)

    update_changelog_repo(
        repo,
         os.path.join(component_type, f"{component_name}.md"),
         rel_page,
         sha
    )
