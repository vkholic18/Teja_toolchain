# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Process swagger definition

#   If for all the branches, all the configuration matches, exit 0
#   If not, prints the properties that do not match the expected, and exit 1
#
# Env:
#    GHE_API_TOKEN: Token for Github API
#    GHE_API_URL: Url for the GitHub API
#    PROFILES: The profiles to filter with
#    API_FILE_NAME: The API file name
#
# Use:
#    python3 swagger_def.py ${PROFILES}

import sys
import subprocess
import base64
import re
import json
import os
import github
import logging
from ci_python_tools import general_tools
from datetime import datetime
import re


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
        'PROFILES'  ,
        'API_FILE_NAME'
    ]

    args = general_tools.parse_env(required_vars)

    return args

def get_file(gh_obj, api_file_name):

    repo=gh_obj.get_repo('cloud-api-docs/vpc')

    branch="production"
    
    ref = repo.get_git_ref(f'heads/{branch}')
    tree = repo.get_git_tree(ref.object.sha, recursive='/' in "/").tree

    sha = [x.sha for x in tree if x.path == api_file_name]
    if sha:
        content=repo.get_git_blob(sha[0])
        b64 = base64.b64decode(content.content)
        decoded_content=b64.decode("utf8")
    else:
        print("file does not exists")
    data = json.loads(decoded_content)
    return data

def filter_paths(data,zap_dir,filter_list):
    for d in list(data):
        if d == 'paths':
            filtered_path={}
            for i in data[d]:
                for j in filter_list:
                    if re.match(j,i):
                        filtered_path[i]=data[d][i]
            data.pop(d)
            data.update({d:filtered_path})
    with open(os.path.join(zap_dir,"raw_file.json"), 'w') as infile:
        json.dump(data,infile)

def reduce_size(zap_dir):
    with open(os.path.join(zap_dir,"resolved_references.json"), encoding="utf-8") as infile:
            jsonFile = json.load(infile)
    for value in list(jsonFile):
        if value == 'components':
            jsonFile.pop(value)
    with open(os.path.join(zap_dir,"Definitions_without_version.json"), 'w') as infile:
        json.dump(jsonFile,infile)

# setting the version parameter to the current date.  
def setting_current_date(value):
    current_date = datetime.today().strftime('%Y-%m-%d')
    for l in value['parameters']:
        if l['name']=='version':
            for key,val in l.items():
                if key=='schema':
                    val.update({"default":current_date})

def update_version(zap_dir):
    with open(os.path.join(zap_dir,"Definitions_without_version.json"), encoding="utf-8") as infile:
            file = json.load(infile)
    for k1,v1 in file.items():
        if k1=='paths':
            for k2,v2 in file[k1].items():
                if 'parameters' in v2:
                    setting_current_date(v2)
                else:
                    for k3,v3 in v2.items():
                        setting_current_date(v3)
    with open(os.path.join(zap_dir,"Definition.json"), 'w') as infile:
        json.dump(file,infile)

def main():
    # Define logger and parse environment vars
    logger = general_tools.set_up_logger(logging.INFO)
    args = parse_env()

    # Instantiate GitHub object
    gh = github.Github(
        login_or_token=args['ghe_api_token'],
        base_url=args['ghe_api_url']
    )

    profiles = sys.argv[1:]

    # Filter list
    filter_list = ["/"+re.sub("[^a-z_$]","",profile)+"/*" for profile in profiles[1:-1] if re.match("[^a-z_$]",profile)]

    # Show
    logger.info(f"List of filter profiles is {str(filter_list)}")

    # We assume zap_dir is the directory where this script is sitting
    zap_dir=os.path.dirname(os.path.realpath(__file__))
    logger.info(f"zap_dir is {zap_dir}")

    data = get_file(gh, args['api_file_name'])
    filter_paths(data,zap_dir,filter_list)
    
    # Set paths for subprocess command
    raw_file_path=os.path.join(zap_dir,"raw_file.json")
    resolved_references_path=os.path.join(zap_dir,"resolved_references.json")

    subprocess.run(f"json-refs resolve {raw_file_path} > {resolved_references_path}", shell=True)
    reduce_size(zap_dir)
    update_version(zap_dir)

if __name__ == "__main__":
    main()