import base64
from datetime import datetime
import json
import os
import time
from github import Github
import git
import requests
import logging

import yaml

from pathlib import Path
from configure_featureflags import load_yaml_file
from configure_featureflags import combine_flags
from requests.packages.urllib3.exceptions import InsecureRequestWarning 


WORKSPACES = ["global-dev", "global-integ", "global-staging", "global-prod"]
ENCODED_CREDS = base64.b64encode(f"c3cvsg97@ca.ibm.com:{os.environ.get('JIRA_TOKEN', '')}".encode("utf-8")).decode("utf-8")
JIRA_REQUEST_HEADERS = {"Content-type": "application/json", 'Accept': 'application/json', 'Authorization': f'Basic {ENCODED_CREDS}'}
JIRA_ENDPOINT = "https://ibm-iaas.atlassian.net"
JIRA_API_ENDPOINT = JIRA_ENDPOINT + "/rest/api/3"

resource_team = {
    "instance": "RCS",
    "geography": "RCS",
    "metal": "METAL",
    "network": "RNOS",
    "endpoint-gateway": "RNOS",
    "template": "RCS",
    "volume": "RSOS",
    "storage-": "RSOS",
    "subnet": "RNOS",
    "vpc-routing-table": "RCS",
    "dedicated-host": "RDCS",
    "group": "RCS",
    "instance-group": "RCS",
    "placement-group": "RCS",
    "zonemap": "RCS",
    "route": "RNOS",
    "sdn": "RNOS",
    "snap": "RSNAP",
    "rnos": "RNOS",
    "rfos": "RFOS",
    "rcos": "RCS",
    "zos": "RCS",
    "baas": "RSOS",
    "rsos": "RSOS",
    "share": "RSOS",
    "key": "BYOK",
    "cblm": "CBLM",
    "image": "RIOS",
    "gw": "DNLB",
    "public-gateway": "DNLB",
    "public-address-gateway": "DNLB",
    "floating-ip": "RNOS",
    "vpn": "VPN",
    "vpn-server": "VPN",
    "load-balancer": "DNLB",
    "metadata": "RMDS",
    "network-acl": "RCOS",
    "security-group": "RNOS",
    "endpoint-gateway": "DNLB",
    "dedicated-host-group": "RDCS",
    "instance-template": "RCS",
    "flow-log": "RSOS",
    "backup-policy": "RSOS",
    "private-path-service-gateway": "DNLB",
    "vpe": "RNOS",
    "virtual-network-interface": "RNOS",
    "reservation": "CRS",
    "sb-": "SB",
    "acadia": "AARCH",
    "biw": "TEL",
    "bss": "TEL",
    "service-broker": "SB",
    "distributed-load-balancer": "DNLB",
    "export-job": "RSOS",
    "cluster-network": "RNOS",
    "zvsi": "RCS",
    "zscpbloc": "RSOS",
    "localdisk": "RSOS",
    "featureflag": "IMF",
    "migration": "RNOS",
    "telemetry": "TEL",
    "billing": "TEL",
    "logging": "TEL",
    "hypersync": "TEL",
    "health": "RHS",
    "vpc": "RNOS",
    "gateway": "RNOS",
    "feature-": "IMF",
    "iam": "IMF"
}

exemption_list = {
    "is-image-archive-create-phase1", 
    "is-features-allowlisted",
    "is-vpc-operations",
    "is-vpc-operations-node-properties",
    "is-vpc-operations-actions-refactor",
    "is-vpc-operations-node-evacuate",
    "is-image-allow-obsolete-public-image-provisions",
    "is-acadia-pool-image-import"
}

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(os.path.basename(__file__))

def create_update_github_issue(git_info):
    gh = Github(
        login_or_token= os.environ["GIT_TOKEN"],
        base_url= os.environ["GHE_API_URL"]
    )

    issue_link_template = "https://github.ibm.com/genctl/{}/issues/{}"
    
    gh_repo = gh.get_repo('genctl/' + git_info["team"])

    ff_label = gh_repo.get_label('featureflags-retiring')
    repo = gh_repo.get_label(git_info["workspace"])

    issue_list = gh_repo.get_issues(state="open", labels=[ff_label, repo])

    for _, issue in enumerate(issue_list):
        try:
            if git_info["flag"] in issue.title:
                    logger.info(f'Leaving a comment for existing GIT issue: {issue.number} for featureflag: {git_info["flag"]} under the {git_info["team"]} repository')
                    issue.create_comment(git_info["body"])
                    return issue_link_template.format(git_info["team"], issue.number)
        except:
            pass

    issue = gh_repo.create_issue(title=git_info["title"], body=git_info["body"], labels=[ff_label, repo], assignees=["Bassem-Shaker"])
    logger.info(f'New GIT issue: {issue.number} has been created for featureflag: {git_info["flag"]} under the {git_info["team"]} repository')

    return issue_link_template.format(git_info["team"], issue.number)

def convert_to_adf(text):
  return {
    "content": [
      {
        "content": [
          {
            "text": text,
            "type": "text"
          }
        ],
        "type": "paragraph"
      }
    ],
    "type": "doc",
    "version": 1
  }

def get_jira_issue(jira_info):
    url = "{}/search/jql?maxResults=1&jql=labels in ('{}') AND summary~'{}' AND status not in (Closed, Resolved)".format(JIRA_API_ENDPOINT, jira_info["workspace"], jira_info["flag"]) 
    issue_key = ""

    try: 
        response = requests.get(url, headers=JIRA_REQUEST_HEADERS, params={"fields": "key"}, verify=False)
        if response.ok:
            issue_details = response.json()
            if len(issue_details['issues']) > 0:
                issue_key = issue_details['issues'][0]['key']
                logger.info(f'Found existing jira issue: {str(issue_key)}')
            else:
                logger.info(f'No JIRA issue found for flag {jira_info["flag"]} under project {jira_info["project"]} for the {jira_info["workspace"]} repository')   
        else:
           raise logger.fatal(f'Failed to retrieve JIRA issue details for flag {jira_info["flag"]} under team {jira_info["project"]} for the {jira_info["workspace"]} repository: {response.status_code} - {response.reason}')         
    except requests.exceptions.RequestException as e:
        raise ValueError("Failed to retrieve JIRA issue details for flag {} under team {}: {}".format(jira_info["flag"], jira_info["project"], e))

    return issue_key

def add_comment_to_jira_issue(jira_info, issue_key):
    
    payload = {
      "body": convert_to_adf(jira_info["description"])
     }

    url = "{}/issue/{}/comment".format(JIRA_API_ENDPOINT, str(issue_key))
    issue_url = ""

    try:
        response = requests.post(url, headers=JIRA_REQUEST_HEADERS, data=json.dumps(payload), verify=False)
        if response.ok:
            logger.info(f'Leaving a comment for existing JIRA issue {issue_key} for featureflag: {jira_info["flag"]} under the {jira_info["workspace"]} repository')
            issue_url = "{}/browse/{}".format(JIRA_ENDPOINT, str(issue_key))
        else:
            logger.fatal(f'Failed to add comment to JIRA issue {issue_key} for featureflag {jira_info["flag"]} under project {jira_info["project"]} for the {jira_info["workspace"]} repository: {response.status_code} - {response.reason}')
    except requests.exceptions.RequestException as e:
        raise ValueError("Failed to add comment to JIRA issue {} for featureflag {} under project {}: {}".format(issue_key, jira_info["flag"], jira_info["project"], e))
    
    return issue_url

def get_jira_project_lead_id(jira_info):

    url = "{}/project/{}/".format(JIRA_API_ENDPOINT, jira_info["project"])
    lead_id = ""

    try:
        response = requests.get(url, headers=JIRA_REQUEST_HEADERS, verify=False)
        if response.ok:
            lead_id = response.json()["lead"]["displayName"]
        else:
            logger.fatal(f'Failed to get lead id for featureflags under JIRA project {jira_info["project"]}: {response.status_code} - {response.reason}')
        
        if lead_id == "":
            logger.fatal(f'Lead id is empty for JIRA project {jira_info["project"]}')

    except requests.exceptions.RequestException as e:
        raise ValueError("Failed to get lead id for featureflags under JIRA project {}: {}".format(jira_info["project"], e))
    
    return lead_id

def create_jira_issue(jira_info):

    payload = {
        "fields": {
            "assignee": {
              "name": jira_info["lead_id"]
            },
            "project": {
                "key": jira_info["project"]
            },
            "summary": jira_info["summary"],
            "description": convert_to_adf(jira_info["description"]),
            "issuetype": {
                "name": jira_info["issue_type"]
            },
            "labels": ["featureflags-retiring", jira_info["workspace"]]
        }
    }

    url = "{}/issue".format(JIRA_API_ENDPOINT)
    issue_url = ""

    try:
        response = requests.post(url, headers=JIRA_REQUEST_HEADERS, data=json.dumps(payload), verify=False)
        if response.ok:
            issue_key = response.json()["key"]
            issue_url = "{}/browse/{}".format(JIRA_ENDPOINT, str(issue_key))
            logger.info(f'New JIRA issue: {issue_key} has been created for featureflag: {jira_info["flag"]} under the {jira_info["workspace"]} repository')
        else:
            logger.fatal(f'Failed to create new JIRA issue for project {jira_info["project"]} under the {jira_info["workspace"]} repository : {response.status_code} - {response.reason}')
    except requests.exceptions.RequestException as e:
        raise ValueError("Failed to create new JIRA issue for project {}: {}".format(jira_info["project"], e))

    return issue_url

def create_update_jira_issue(jira_info):
   issue_key = get_jira_issue(jira_info)
   time.sleep(3) #Mitigate JIRA rate limiting
   return add_comment_to_jira_issue(jira_info, issue_key) if issue_key else create_jira_issue(jira_info)


def create_issue(flag: str, description: str, issue_type: str, git_workspace: str, project: str):

    summary = "Retirement of featureflag: {} in {} repo under nextgen-environments org and other repos".format(flag, git_workspace)

    jira_info = {
        "summary": summary,
        "description": description,
        "workspace": git_workspace,
        "issue_type": 'Task',
        "project": project,
        "flag": flag
    }

    git_info = {
     "title": summary,
     "body": description,
     "workspace": git_workspace,
     "team": project,
     "flag": flag
    }

    issue_link = ""

    if 'GIT' in issue_type:
        issue_link = create_update_github_issue(git_info)
    elif 'JIRA' in issue_type:
        jira_info["lead_id"] = get_jira_project_lead_id(jira_info)
        time.sleep(3) #Mitigate JIRA rate limiting
        issue_link = create_update_jira_issue(jira_info)
        time.sleep(3) #Mitigate JIRA rate limiting
    else:
        raise ValueError('Unsupported issue type')
    
    logger.info(f'The link to the issue is {issue_link}')

def find_last_commit_date(flag_name, workspace, team):

    gh_repo = git.Repo("./repos/" + workspace)
    commits_list = ""
    if team == "":
        commits_list = gh_repo.blame('HEAD', "environment.yaml")
    else:
        commits_list = gh_repo.blame('HEAD', "service-flags/" + team + ".yaml")

    #finding commit date of the flag
    for commit, lines in commits_list:
        for line in lines:
            if flag_name in line:
                return datetime.fromtimestamp(commit.committed_date)

    return datetime.today()

def fetch_workspace_flag_names(workspace):
             
    env_base_path = workspace + "/environment.yaml"
    service_base_path = workspace + "/service-flags/"
    
    env_data = combine_flags(env_base_path, service_base_path)
    flags = env_data['apps']['feature_flags']['vpc']
    flag_names = []

    for flag in flags:
        flag_names.append(flag["name"])

    return flag_names


def check_flags_retirement(workspace, flags, team):
   
   is_prod_flags = ("prod" in workspace)

   next_workspace = ""
   next_workspace_flag_names = {}

   if not is_prod_flags:
    next_workspace = WORKSPACES[WORKSPACES.index(workspace)+1]
    next_workspace_flag_names = fetch_workspace_flag_names(next_workspace)

   for flag in flags:
        
        flag_name = flag["name"]

        if flag_name in exemption_list:
            logger.info(f'{flag_name} has been exempted from retirement check for {workspace} workspace')
            continue

        issue_type = "JIRA"
        team_issue = team

        if team_issue == "":
          team_issue = find_flag_project(flag_name)
        if team_issue == "IMF":
            issue_type = "GIT"
        
        description = get_issue_description(is_prod_flags, 
                                            workspace, next_workspace, 
                                            next_workspace_flag_names, team, flag)
        
        if description != "":
                logger.info(f'{flag_name} should be retired in {workspace} workspace')
                create_issue(flag_name, description + 
                             " Retirement is needed to reduce featureflags configmap as much as possible.", 
                             issue_type, workspace, team_issue)



def get_issue_description(is_prod_flags, workspace, next_workspace, next_workspace_flag_names, team, flag):

    flag_name = flag["name"]
    flag_is_on = flag["on"]
    default_flag_value = flag["default"]["variation_value"]

    #any typed flag with useless allowlist
    flag_should_be_retired = False
    if flag_is_on and default_flag_value and flag.get("rules"):
        rules = flag["rules"]
        flag_should_be_retired = True
        for rule in rules:
            if rule["variation_value"] != default_flag_value:
                flag_should_be_retired = False
                break

    if flag_should_be_retired:
        return "Flag has allowlist(s) defined unnecessarily."

    if is_prod_flags:
        return get_prod_issue_description(flag)
    else: 
        return get_non_prod_issue_description(workspace, next_workspace, next_workspace_flag_names, team, flag_name)


def get_prod_issue_description(flag):
    default_flag_value = flag["default"]["variation_value"]
    flag_is_on = flag["on"]
    
    #Flags reaching terminal state in prod
    if flag_is_on and isinstance(default_flag_value, bool)  and \
    default_flag_value and not flag.get("rules"): #true boolean flag with no allowlist 
        return "Boolean flag has reached its final state in production with no allowlist."
    elif flag_is_on and isinstance(default_flag_value, dict) and \
            default_flag_value.get("maturity") == "ga" and not flag.get("rules") : #flag with ga maturity and no allowlist
                return "Maturity flag has reached its final state in production with no allowlist." 
    return ""

def get_non_prod_issue_description(workspace, next_workspace, next_workspace_flag_names, team, flag_name):
    
    commit_date = find_last_commit_date(flag_name, workspace, team)

    #file search for flag in next env in env yaml and service flags
    #if not there compare date to now if today_date - commit_date > 30 days, 90 days for
    #dev, and if yes should be retired
    
    if not (flag_name in next_workspace_flag_names) :
        difference = datetime.today() - commit_date
        if ("dev" in workspace) and difference.days > 90:
            return "Flag has not been promoted from {} to {} in over 90 days.".format(workspace, next_workspace)
        elif difference.days > 30:
            return "Flag has not been promoted from {} to {} in over 30 days.".format(workspace, next_workspace)
        
    return ""
    

def check_service_flags_retirement(git_workspace):
    service_flags_path = git_workspace + "/service-flags/"
    if os.path.isdir(service_flags_path) and os.listdir(service_flags_path):
        logger.info(f'Reading in service flags directory: {service_flags_path}')
        filenames = os.listdir(service_flags_path)
        for filename in filenames:
            if filename == "ibm-services-vpc-onboarding.yaml":
                continue
            filepath = service_flags_path + filename
            logger.info(f'Reading in featureflags service file: {filepath}')
            file_flag_data = load_yaml_file(filepath)
            check_flags_retirement(git_workspace, file_flag_data['apps']['feature_flags']['vpc'], Path(filepath).stem)

def find_flag_project(flag_name):
    flag_name_lowercase = flag_name.lower()
    for resource, project in resource_team.items():
        if resource in flag_name_lowercase:
            return project
    return "IMF"

def check_environment_flags_retirement(git_workspace):
    env_flags_path = git_workspace + "/environment.yaml"
    env_yaml = Path(env_flags_path)
    if env_yaml.exists() and env_yaml.is_file():
        logger.info(f'Reading in featureflags environment flags file: {env_flags_path}')
        file_flag_data = load_yaml_file(env_flags_path)
        check_flags_retirement(git_workspace, file_flag_data['apps']['feature_flags']['vpc'],"")

def download_flag_repositories():
   
   os.makedirs("./repos")

   for workspace in WORKSPACES:
    git.Git("./repos/").clone("git@github.ibm.com:nextgen-environments/{}.git".format(workspace))

   gh = Github(
        login_or_token= os.environ["GIT_TOKEN"],
        base_url=os.environ["GHE_API_URL"]
    )

   for workspace in WORKSPACES:
        os.makedirs(workspace + "/service-flags")

        gh_repo = gh.get_repo('nextgen-environments/' + workspace)

        ff_env_file = gh_repo.get_contents('environment.yaml')
        ff_flags_files = gh_repo.get_contents('service-flags')

        ff_flags_files.append(ff_env_file)

        for ff_flags_file in ff_flags_files:
                ff_env_data = base64.b64decode(ff_flags_file.content).decode("utf-8")
                file_out = open("{}/{}".format(workspace, ff_flags_file.path), "w+")
                file_out.write(ff_env_data)
                file_out.close()

   logger.info('Completed download of all global-XXX repos')

if __name__ == "__main__":

    requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    download_flag_repositories()
    
    for workspace in WORKSPACES:
        check_environment_flags_retirement(workspace)
        check_service_flags_retirement(workspace)
