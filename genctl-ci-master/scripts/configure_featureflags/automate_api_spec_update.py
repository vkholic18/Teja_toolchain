import argparse
import yaml
import logging
from git import GitConfigParser, Repo
from github import Github
import re
from pathlib import Path
import os
import requests
import shutil
import hashlib

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(os.path.basename(__file__))
template_path = 'global-xxx_pr_template.mustache'
repo_owner = "nextgen-environments"
label_name = "api spec version update"
github_token = os.getenv("NEXTGEN_ENVIRONMENTS_GITHUB_PAT")
ghe_api_url = os.getenv("GHE_API_URL")
nextgen_ff_alerts_webhook = os.getenv("NEXTGEN_FF_ALERTS_WEBHOOK")

staging_template_hash_value = "2065192b9a35d7f448c61fb4bf69f6f36619e749a9aaf3d47db516757ef8c372"
prod_template_hash_value    = "28778c5b1135503c71ed10a1268a695add0acd65b71d317e30d18a1fdf18574c"

def get_last_merged_pr_with_label(repo_name):
    headers = {
        "Authorization": f"Bearer {os.environ['NEXTGEN_ENVIRONMENTS_GITHUB_PAT']}",
        "Accept": "application/vnd.github+json"
    }

    url = f"{ghe_api_url}/repos/{repo_owner}/{repo_name}/pulls"
    params = {
        "state": "closed",
        "labels": label_name,
        "per_page": 50,
        "sort": "updated",
        "direction": "desc"
    }

    response = requests.get(url, headers=headers, params=params)
    response.raise_for_status()
    prs = response.json()

    for pr in prs:
        if pr.get("merged_at"):
            labels_url = pr["_links"]["issue"]["href"] + "/labels"
            labels_resp = requests.get(labels_url, headers=headers)
            labels_resp.raise_for_status()
            labels = [label["name"] for label in labels_resp.json()]
            if label_name in labels:
                return {
                    "title": pr["title"],
                    "number": pr["number"],
                    "url": pr["html_url"]
                }

    return None

def generate_pr_description(pr_html_url, template_file_path):
    try:
        if not template_file_path.exists():
            raise FileNotFoundError(f"{template_file_path} not found in repo")

        file_contents = template_file_path.read_text()
        file_contents = re.sub(r"- \[\s\] All Regions", "- [x] All Regions", file_contents)
        file_contents = re.sub(r"(Is the code in the regions.*?\n)- \[.\] Yes", r"\1- [x] Yes", file_contents,
                               flags=re.DOTALL)
        file_contents = re.sub(r"(Is there a dependency\?.*?\n.*?\n)- \[.\] No", r"\1- [x] No", file_contents,
                               flags=re.DOTALL)

        items_to_uncheck = ["feature change"]
        for item in items_to_uncheck:
            pattern = rf"(\- )\[x\]\s+{re.escape(item)}(.*)"
            replacement = r"\1[ ] " + item + r"\2"
            file_contents = re.sub(pattern, replacement, file_contents, flags=re.IGNORECASE)

        for items_to_check in ["configuration change"]:
            pattern = rf"- \[ \] {items_to_check}"
            replacement = f"- [x] {items_to_check}"
            file_contents = re.sub(pattern, replacement, file_contents, flags=re.IGNORECASE)

        items_to_check = [
            "Previous Change Information",
            "Previous Test Evidence"
        ]
        for item in items_to_check:
            pattern = rf"(\- )\[\s\]\s+{re.escape(item)}(.*)"
            replacement = r"\1[x]  " + item + r"\2"
            file_contents = re.sub(pattern, replacement, file_contents, flags=re.IGNORECASE)

        file_contents = re.sub(re.escape("[Please provide previous change info]"), pr_html_url, file_contents)
        file_contents = re.sub(re.escape("""[Please provide previous test evidence link as well as a
      screenshot with 100% of tests passing]"""), pr_html_url, file_contents)
        return file_contents
    except Exception as error:
        print(f"Failed to read or process {template_file_path}: {error}")
        raise

def update_env_yaml(env_file_path, release_tag, file_to_be_added, repo_name):
    try:
        env_file_path = Path(env_file_path)
        content = env_file_path.read_text(encoding='utf-8')
        updated_content = re.sub(r'(\s*api_spec_version:\s*).*', rf'\1{release_tag}', content)
        env_file_path.write_text(updated_content, encoding='utf-8')

        repo_path = Path.cwd() / repo_name
        repo = Repo(repo_path)

        repo.git.add(file_to_be_added)
        commit = repo.index.commit(f"chore: IMF-000: New Commit with Updated api spec version - {release_tag}")
        return commit.hexsha

    except Exception as e:
        logger.error(e)
        raise RuntimeError('Error occurred during file update or Git operations') from e


def get_api_spec_bump_pr(repo_owner, repo_name, label_name, state):
    logger.info('Searching for Existing PRs...')
    pull_request_number = None
    pull_request_branch = None

    try:
        gh = Github(
            login_or_token=os.environ["NEXTGEN_ENVIRONMENTS_GITHUB_PAT"],
            base_url=os.environ["GHE_API_URL"]
        )
        repo = gh.get_repo(f"{repo_owner}/{repo_name}")
        pulls = repo.get_pulls(state=state)

        for pr in pulls:
            labels = pr.get_labels()
            if labels.totalCount > 0 and labels[0].name == label_name:
                pull_request_number = pr.number
                pull_request_branch = pr.head.ref
                break

    except Exception as e:
        logger.error(e)
        raise RuntimeError('Error occurred while searching for existing PRs') from e

    return pull_request_number, pull_request_branch

def get_current_release_version(env_file_path):
    try:
        with open(env_file_path, 'r', encoding='utf-8') as f:
            data = f.read()
        match = re.search(r'\s*api_spec_version:\s*r[0-9]*', data)
        if match:
            return match.group(0).strip()
        else:
            raise ValueError("api_spec_version not found in file.")
    except Exception as e:
        raise RuntimeError(f"Failed to read or parse: {env_file_path}") from e

def compute_file_hash(file_path, algorithm='sha256'):
    hash_func = hashlib.new(algorithm)
    
    with open(file_path, 'rb') as file:
        while chunk := file.read(8192):
            hash_func.update(chunk)
    
    return hash_func.hexdigest()

def create_or_update_api_spec_bump_pr(api_spec_version, pr_html_url, repo_name, base_branch):
    if not github_token or not ghe_api_url:
        raise EnvironmentError("GitHub credentials not found in environment variables.")

    pr_number, pr_branch = get_api_spec_bump_pr(repo_owner, repo_name, label_name, state="open")
    pr_exists = bool(pr_number and pr_branch)

    gh = Github(login_or_token=github_token, base_url=ghe_api_url)
    gh_repo = gh.get_repo(f"{repo_owner}/{repo_name}")

    repo_url = f"https://{github_token}@github.ibm.com/{repo_owner}/{repo_name}.git"
    clone_dir = Path.cwd() / repo_name
    env_file_path = clone_dir / "environment.yaml"
    template_file_path = clone_dir / '.github' / 'pull_request_template.md'
    logger.info("template_file_path")
    logger.info(template_file_path)

    try:
        logging.info("Cloning repository...")
        if pr_exists:
            Repo.clone_from(repo_url, clone_dir, branch=pr_branch)
        else:
            Repo.clone_from(repo_url, clone_dir)

        repo = Repo(clone_dir)
        config_path = Path(repo.git_dir) / "config"

        # Configure Git user locally
        with GitConfigParser(config_path, read_only=False) as config:
            config.set_value("user", "name", "vpciamdev")
            config.set_value("user", "email", "vpciamdev@ibm.com")

        current_template_hash_value = compute_file_hash(template_file_path, 'sha256')
        previous_template_hash_value = staging_template_hash_value if repo_name == "global-staging" else prod_template_hash_value

        if current_template_hash_value != previous_template_hash_value:
            errMsg = f"Template file checksum failed, The Pull Request template for {repo_name} repository has been changed."
            slackMsg = f""":alert1: The Pull Request template for {repo_name} repository has been updated. :alert1:
            Please update the corresponding template checksum in the repository: https://github.ibm.com/genctl-cicd/genctl-ci"""
            send_slack_message(nextgen_ff_alerts_webhook, slackMsg)
            logging.error(errMsg)
            raise RuntimeError(errMsg)

        if pr_exists:
            logging.info("Updating existing PR...")
            latest_version = f"api_spec_version: {api_spec_version}"
            current_version = get_current_release_version(env_file_path)

            if current_version == latest_version:
                logging.info(f"No api_spec_version change detected in {repo_name} . Exiting...")
                return False

            repo.git.checkout(pr_branch)
            updated_commit = update_env_yaml(env_file_path, api_spec_version, 'environment.yaml', repo_name)
            repo.git.reset('--hard', updated_commit)
            repo.git.push('origin', pr_branch)

            pr = gh_repo.get_pull(pr_number)
            pr.edit(
                title=f"chore: IMF-000: Automated PR - Update api spec version to {api_spec_version}",
                body=generate_pr_description(pr_html_url, template_file_path),
                state="open",
                base=base_branch
            )
            pr.create_issue_comment(f"Automated PR - Updated api spec version to {api_spec_version}")
            logging.info(f"Updated PR #{pr.number}")

        else:
            logging.info("Creating new PR...")
            new_branch = api_spec_version
            repo.git.checkout('-b', new_branch)
            update_env_yaml(env_file_path, api_spec_version, 'environment.yaml', repo_name)
            repo.git.push('--set-upstream', 'origin', new_branch)

            pr = gh_repo.create_pull(
                title=f"chore: IMF-000: Automated PR - Update api spec version to {api_spec_version}",
                body=generate_pr_description(pr_html_url, template_file_path),
                head=new_branch,
                base=base_branch
            )
            pr.add_to_labels(label_name)
            logging.info(f"Created PR #{pr.number}: {pr.title} ({pr.html_url})")

    except Exception as e:
        logging.error(f"Error during PR creation or update: {e}")

def read_global_api_spec_version(repo_name):
    clone_dir = f"clone-{repo_name}"
    repo_url = f'git@github.ibm.com:nextgen-environments/{repo_name}.git'

    if os.path.exists(clone_dir):
        shutil.rmtree(clone_dir)

    try:
        repo = Repo.clone_from(repo_url, clone_dir)
        repo.remotes.origin.fetch()
        if repo.head.is_detached:
            main_branch = "main" if repo_name == "global-staging" else "master"
        else:
            head_ref = next((ref for ref in repo.remotes.origin.refs if ref.name.endswith("HEAD")), None)
            if not head_ref or not head_ref.reference:
                raise ValueError("Could not determine default branch from HEAD reference.")
            main_branch = head_ref.reference.name.split("/")[-1]
        repo.git.pull("origin", main_branch)
        file_blob = repo.tree()["environment.yaml"]
        file_content = file_blob.data_stream.read().decode("utf-8")
        data = yaml.safe_load(file_content)

        if 'api_spec_version' in data['apps']['feature_flags']:
            current_version = data['apps']['feature_flags'].get('api_spec_version')
            logger.info(f'Current version in {repo_name}: {current_version}')
            return current_version
    except Exception as e:
        logger.info(f'Error processing api-spec-version in {repo_name}: {e}')

def trigger_prs_to_global_staging_prod(integ_api_spec_version):
    staging_api_spec_version = read_global_api_spec_version("global-staging")
    prod_api_spec_version = read_global_api_spec_version("global-prod")

    if None not in (integ_api_spec_version, staging_api_spec_version, prod_api_spec_version):
        if (integ_api_spec_version >= staging_api_spec_version) and (staging_api_spec_version > prod_api_spec_version):
            pr = get_last_merged_pr_with_label("global-staging")
            pr_html_url = pr.get("url")
            logger.info(f"Last merged PR for api-spec-version change in global-staging:{pr_html_url}")
            logger.info(f'Triggering api-spec-version PR update for global-prod...')
            create_or_update_api_spec_bump_pr(staging_api_spec_version, pr_html_url, "global-prod", "master")
        else:
            logger.info(f'No update needed for global-prod. api-spec-version {prod_api_spec_version} is up to date'
                        f' with global-staging')

        if integ_api_spec_version > staging_api_spec_version:
            pr = get_last_merged_pr_with_label("global-integ")
            pr_html_url = pr.get("url")
            logger.info(f"Last merged PR for api-spec-version change in global-integ:{pr_html_url}")
            logger.info(f'Triggering api-spec-version PR update for global-staging...')
            create_or_update_api_spec_bump_pr(integ_api_spec_version, pr_html_url, "global-staging", "main")
        else:
            logger.info(f'No update needed for global-staging. api-spec-version {staging_api_spec_version} '
                        f'is up to date with global-integ')
    else:
        raise ValueError("One or more api-spec-version values are None")

def send_slack_message(webhook_url: str, message: str):
    payload = {"text": message}
    response = requests.post(webhook_url, json=payload)
    if response.status_code != 200:
        raise Exception(f"Slack webhook failed with {response.status_code}: {response.text}")

def main():
    integration_api_spec_ver = read_global_api_spec_version("global-integ")
    if integration_api_spec_ver != "":
        trigger_prs_to_global_staging_prod(integration_api_spec_ver)
    else:
        logger.info(f'api-spec-version for global-integ is not set')

if __name__ == "__main__":
    main()
