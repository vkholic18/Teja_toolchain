#! /usr/bin/env python3
## ==============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2021, 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## ==============================================================================================

import argparse
import yaml
import re
import os.path
import sys
from os import walk
from os import path
from pathlib import Path

def parse_dir(dir):
    """
    Parses a directory and returns files and directories present in the current directory.
    """
    if not path.exists(dir):
        print("Error: path '{}' doesn't exist".format(dir))
        sys.exit(0)
    _,dirnames,files = next(walk(dir))
    return dirnames,files

def get_file_path(opt):
    """ 
    Gets the file path from an url under spec->requests-options in remote-resource file
    """
    try:
        loc = opt['options']['url']
        path_arr = loc.split("/")
        #The script assumes that every remote resource yaml file would have similar format
        # {{{cos-url}}}/{{{cos-bucket-name}}}/<workspace_name>/{{image-version}}/<mustache template file path>
        path_arr[0] = "cos-url"
        path_arr[1] = "cos-bucket-name"
        path_arr[2] = "workspace"
        path_arr[3] = "image-version"
        loc = "/".join(path_arr).replace(" ","")
        paths = loc.replace("cos-url/cos-bucket-name/workspace/image-version/",workspaceRazeeDir)
        return paths
    except Exception as e:
        print("Error occurred while parsing the remote resource file's urls")
        print("Error:",e)

def validate_file_paths(path,files):
    """ 
    Validates if all the files in a given path exist
    """
    print("Validating remote resource file: {:<60}\n".format(path))
    print("{:<150} {:<20}".format("File:","Exists"))
    status = True
    for p in files:
        f = Path(p)
        if status == True:
            status = f.is_file()
        print("{:<150} {:<20}".format(p,is_file(f.is_file())))
    print("\n")
    return status

def is_file(status):
    if status != 0:
        return "Yes"
    else:
        return "No"

def strip_handlebars_conditionals(yaml_str):
    return re.sub(' {{[^{]*}}', '', yaml_str)

def validate_remote_resource(path):
    """ 
    Reads the remote-resource yaml file and validates the urls.
    """ 
    try:
        with open(path,'r') as f:
            doc = yaml.safe_load(f)
        if 'templates' in doc['spec'].keys():
            req = doc['spec']['templates'][0]['spec']['requests']
        elif 'strTemplates' in doc['spec'].keys():
            yaml_str = strip_handlebars_conditionals(doc['spec']['strTemplates'][0])
            new_doc = yaml.safe_load(yaml_str)
            req = new_doc['spec']['requests']            
        fileNames = map(get_file_path,req)
        return validate_file_paths(path,fileNames)
    except KeyError as e:
        print("Key Error: {0}\nInvalid remote-resource file: {1}\n".format(e,path))
    except Exception as e:
        print("Error: {0}\nInvalid remote-resource file: {1}\n".format(e,path))
    
def return_result(status):
    if not status:
        print("Validation failed")
        sys.exit(1)
    else:
        print("Validation successful")
        sys.exit(0)
 
def get_resource_file_paths(dir,fnList):
    """
    returns all the remote-resource files present in current directory and sub-directories
    """
    print("Finding remote-resource file in {0}\n".format(dir))
    dirNames,filesInPath = parse_dir(dir)
    if len(set(filesInPath)) > 0:
        for x in filesInPath:
            if "remote-resource" in x:
               fnList.add(dir+x)
    if len(dirNames) > 0:
        for d in dirNames:
            d = dir+d+"/"
            get_resource_file_paths(d,fnList)
    return fnList


def main():
    parser = argparse.ArgumentParser(
        usage=(
            """
            (Example) Use command below to validate razee remote resource files in keyreact-workspace using params:

            python3 scripts/validate_remote_resource/validate_remote_resource.py --workspaceRazeeDir=keyreact-workspace/hack/deploy/razee/
            """
        ),
    )

    parser.add_argument("--workspaceRazeeDir", help="input the name of the workspace's razee directory")
    args = parser.parse_args()
    global workspaceRazeeDir 
    workspaceRazeeDir = args.workspaceRazeeDir

    fl = set()
    ls = get_resource_file_paths(workspaceRazeeDir,fl)
    status = True
    for f in ls:
        res = validate_remote_resource(f)
        if res != True:
            status = res
    return_result(status)

if __name__ == "__main__":
    main()
