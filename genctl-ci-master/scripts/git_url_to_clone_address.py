#!/usr/bin/python3
#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

#**************************************************************************
#        NAME
#               git_url_to_clone_address.py
# DESCRIPTION
#               extract clone address of a git PR URL
#               This is required because forks use a different syntax and we
#               may need to extract the proper "org" from the string.
#       NOTES
#               Usage: python3 git_url_to_clone_address.py <pr-url>
#               ex:
#               $ python3 git_url_to_clone_address.py https://github.ibm.com/pbrightl/compute-workspace/pull/2
#               git@github.ibm.com:pbrightl/compute-workspace.git
#      RETURN
#               success: rc=0, output: git-clone-address
#               failure: rc=1, output: message with "ERROR" in it
#**************************************************************************
import json
import sys
import os
import urllib.parse

import requests

user     = os.environ.get('GHE_USERNAME', '')
password = os.environ.get('GHE_ACCESS_TOKEN', '')

rc = 0
if len(sys.argv) > 1 and sys.argv[1]:
    pr_url = sys.argv[1]

    try:
        # make a request to github with the PR url to retrieve the git clone url for
        # the source of the PR, so that we can support forks
        if '/api/v3/repos' not in pr_url:
            # modify the url to use the github API
            url_parts = urllib.parse.urlparse(pr_url)
            new_path = '/api/v3/repos' + url_parts.path.replace('pull', 'pulls')
            pr_url = url_parts._replace(path=new_path).geturl()
            r = requests.get(pr_url, auth=(user, password))

            git_url = r.json().get('head', {}).get('repo', {}).get('ssh_url')
            if git_url is None:
                rc = 1
                print("ERROR: could not convert git url to clone address")
            else:
                print(git_url)
    except Exception as e:
        rc = 1
        print("ERROR: exception processing "+pr_url)

else:
    rc = 1
    print("ERROR: no url passed")

sys.exit(rc)
