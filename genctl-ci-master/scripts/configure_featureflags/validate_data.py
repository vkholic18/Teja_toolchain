import os
import logging
import base64
import argparse
import configure_features_api_data
import shutil, yaml, git, re, sys
import time
import requests
from pathlib import Path

from requests.packages.urllib3.exceptions import InsecureRequestWarning 

max_size_kb = 800
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(os.path.basename(__file__))

ENCODED_CREDS = base64.b64encode(f"c3cvsg97@ca.ibm.com:{os.environ.get('JIRA_TOKEN', '')}".encode("utf-8")).decode("utf-8")
JIRA_REQUEST_HEADERS = {"Content-type": "application/json", 'Accept': 'application/json', 'Authorization': f'Basic {ENCODED_CREDS}'}
JIRA_ENDPOINT = "https://ibm-iaas.atlassian.net"
JIRA_API_ENDPOINT = JIRA_ENDPOINT + "/rest/api/3"

def get_repo_name(workspace):
    match = re.search(r'global-\w+', workspace)
    return match.group(0) if match else None

def validate_api_spec_release_version(environment_file , current_api_spec_ver: str):
    repo_name = get_repo_name(environment_file)
    clone_dir = "clone-repo"
    repo_url = f'git@github.ibm.com:nextgen-environments/{repo_name}.git'

    if os.path.exists(clone_dir):
        shutil.rmtree(clone_dir)
    try:
        repo = git.Repo.clone_from(repo_url, clone_dir)
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
            master_api_spec_ver = data['apps']['feature_flags']['api_spec_version']
            if current_api_spec_ver < master_api_spec_ver:
                raise ValueError(f"PR contains api_spec_version {current_api_spec_ver} which is older than what is in the master branch {master_api_spec_ver}")
    except Exception as e:
        raise RuntimeError(f"An error occurred while processing the repository: {e}")

def get_directory_size(directory):
    total_size = 0
    for dirpath, dirnames, filenames in os.walk(directory):
        for f in filenames:
            file_path = os.path.join(dirpath, f)
            if not os.path.islink(file_path):
                total_size += os.path.getsize(file_path)
    return total_size


def validate_data_size(env_yaml_path, service_flags_path):
    if not os.path.isfile(env_yaml_path) and (
            not os.path.isdir(service_flags_path) or not os.listdir(service_flags_path)):
        raise FileNotFoundError(f"no file found at {env_yaml_path} and {service_flags_path}")

    file_size_kb = (os.path.getsize(env_yaml_path) + get_directory_size(service_flags_path)) / 1024
    if file_size_kb > max_size_kb:
        raise ValueError(
            f'total size of files at {env_yaml_path} and {service_flags_path} is {file_size_kb} KB and \
            exceeds the maximum file size limit of {max_size_kb} KB.')

    logger.info(f'total size of {env_yaml_path} and all files in {service_flags_path} is valid.')

def get_jira_project(project):
    if project == "IMF" or project == "ibm-services-vpc-onboarding":
        return

    url = "{}/project/{}/".format(JIRA_API_ENDPOINT, project)
    response = requests.get(url, headers=JIRA_REQUEST_HEADERS, verify=False)

    if not response.ok:
        raise ValueError("Failed to get JIRA project {}: {} - {}".format(project, response.status_code, response.reason))

def validate_service_flags_file_name(service_flags_path):
  filenames = os.listdir(service_flags_path)
  for filename in filenames:
      get_jira_project(Path(filename).stem)
      time.sleep(3) #Mitigate JIRA rate limiting

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-yaml-path", help="Path to the environment.yaml file",
                        default="workspace-repo/environment.yaml")
    parser.add_argument("--service-flags-path", help="Path to the service flags directory",
                        default="workspace-repo/service-flags/")
    args = parser.parse_args()

    requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    validate_data_size(args.env_yaml_path, args.service_flags_path)
    release_version = configure_features_api_data.get_api_spec_release_version(args.env_yaml_path)
    validate_api_spec_release_version(args.env_yaml_path, release_version)
    validate_service_flags_file_name(args.service_flags_path)
