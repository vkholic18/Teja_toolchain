#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# /usr/local/bin/python3
"""
* git related methods - forking/cloning/checking for hub install/configuration
"""

###############################################################################
# I M P O R T S ###############################################################
###############################################################################

import io
import json
import logging
import os
import re
import subprocess
import sys

try:
    import pycurl
except ImportError:
    IMPORT_PYCURL = ('PYCURL_SSL_LIBRARY=openssl LDFLAGS="-L/usr/local/opt/openssl/lib"'
                     'CPPFLAGS="-I/usr/local/opt/openssl/include" pip install --no-cache-dir pycurl')

    print("pycurl must be installed to use this module.")
    print("You can do this from the below (virtual env preferable):\nurl: {}".format(IMPORT_PYCURL))

    sys.exit(1)

from os.path import expanduser
from concourse.user_exceptions import ExecutionError, ConfigError
from ruamel.yaml import YAML

###############################################################################
# G L O B A L S ###############################################################
###############################################################################

IBM_GITHUB_API_URL = "https://api.github.ibm.com"


###############################################################################
# F U N C T I O N S ###########################################################
###############################################################################

def is_hub_installed_and_configured():
    """
    * check to make sure hub is installed and the config file is in place
    *
    :return: path to config
    """
    # resources
    #https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line/
    #http://cloudlab-confluence.canlab.ibm.com:8090/pages/viewpage.action?pageId=11745173
    #http://cloudlab-confluence.canlab.ibm.com:8090/display/DevOps/Forking+a+Repository+using+Hub
    #https://hub.github.com/

    logger = logging.getLogger()

    hub_chk_cmd = ['which', 'hub']

    logger.info("Checking is HUB is installed and configured")

    # check if hub is installed
    # if not, tell the user how to get it installed
    process = subprocess.Popen(hub_chk_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)

    std_output, err_output = process.communicate()

    logger.debug(std_output)
    logger.debug(err_output)

    return_code = process.returncode

    if return_code > 0:
        err_msg = """HUB was not found to be installed. Please ensure it is installed and in your path:
        For installation, please refer to: https://hub.github.com/"""
        raise ConfigError(err_msg)

    # if hub is installed, is it configured?
    # check ~/.config/hub
    cfg_path = "{}/.config/hub".format(expanduser("~"))

    if not os.path.isfile(cfg_path):
        lab_wiki = "http://cloudlab-confluence.canlab.ibm.com:8090/display/DevOps/Forking+a+Repository+using+Hub"
        raise ConfigError("The hub config file ({}) needs to exist and be configured according to: {}".format(cfg_path,
                                                                                                              lab_wiki))

    return cfg_path


def clone_and_fork_repo(git_repo, sandbox_dir):
    """
    * clone and fork a repo
    :param git_repo: repo to clone
    :param sandbox_dir: where to put the cloned repos
    :return: None
    """

    logger = logging.getLogger()

    if not os.path.isdir(sandbox_dir):
        try:
            os.makedirs(sandbox_dir)
        except OSError as e:
            logger.error("The sandbox directory did not exist and we were unable to create it! : {}".format(e))
            raise

    try:
        # change to the sandbox and we will start forking repos
        os.chdir(sandbox_dir)

        logger.info("Creating clone of repo: {}".format(git_repo))

        clone_dir = clone_repo(git_repo)

        current_dir = os.getcwd()

        os.chdir(clone_dir)

        logger.info("Creating fork of repo: {}".format(git_repo))

        fork_repo(git_repo)

        os.chdir(current_dir)

    except (ValueError, ExecutionError) as e:
        logger.error(e)
        raise
    except OSError as e:
        logger.error("Error changing directory to create fork: {}".format(e))
        raise


def clone_repo(git_repo):
    """
    * clone a given repo - ssh method
    *
    :param git_repo: url of the repo to clone
    :return: the dir created in cloning
    """

    logger = logging.getLogger()

    clone_cmd = ['git', 'clone', git_repo]

    logger.debug("Clone cmd: {}".format(clone_cmd))

    # run clone command
    process = subprocess.Popen(clone_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)

    std_output, err_output = process.communicate()

    logger.debug(std_output)
    logger.debug(err_output)

    return_code = process.returncode

    # make sure the clone completed ok
    if return_code > 1:
        raise ExecutionError("Unable to clone repo using cmd: {}\n{}".format(clone_cmd, err_output))

    # find the repo created and return it
    pattern = r".*\/(.*)\.git$"
    match_obj = re.match(pattern, git_repo, re.I)

    if match_obj:
        return match_obj.group(1)

    raise ValueError("Unable to determine dir created from clone of repo: {}".format(git_repo))


def fork_repo(git_repo):
    """
    * fork a git repo
    *
    :param git_repo: repo to fork
    :return: None
    """

    fork_cmd = ['hub', 'fork', git_repo]

    # run fork command
    process = subprocess.Popen(fork_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    _, err_output = process.communicate()

    return_code = process.returncode

    # make sure the fork completed ok
    if return_code > 1 :
        raise ExecutionError("Unable to fork repo using cmd: {}\n{}".format(fork_cmd, err_output))


def get_user_owned_repos(oauth_token, forks_only=False):
    """
    * query the ibm github server for all user related public/owned repos
    *
    :param oauth_token: users auth token for query
    :param forks_only: grabs just those that are forked
    :return: list of user owned repos
    """

    if not oauth_token:
        raise ValueError("A valid oauth token must be supplied to query user repos")

    buf = io.BytesIO()

    curl_header = "Authorization: token {}".format(oauth_token)
    github_user_pub_owned_repos = "{}/user/repos?visibility=public&affiliation=owner".format(IBM_GITHUB_API_URL)

    curl_request = pycurl.Curl()
    curl_request.setopt(pycurl.URL, github_user_pub_owned_repos)
    curl_request.setopt(pycurl.WRITEFUNCTION, buf.write)
    curl_request.setopt(pycurl.CONNECTTIMEOUT, 5)
    curl_request.setopt(pycurl.TIMEOUT, 8)
    curl_request.setopt(pycurl.HTTPHEADER, [curl_header, 'Content-Type: application/json', 'Accept: application/json'])

    curl_request.perform()

    data = json.loads(buf.getvalue().decode('utf-8'))

    buf.close()

    user_repos = list()

    for repo in data:
        if forks_only is False or (forks_only is True and repo['fork'] is True):
            user_repos.append((repo['url'], repo['ssh_url']))

    return user_repos


def delete_user_repo(repo, git_user, oauth_token):
    """
    * delete a given github repo
    :param repo: repo fork to delete
    :param git_user: github user
    :param oauth_token: token for github access
    :return: None
    """
    # ie.
    # curl -H "Authorization: token <token>" -X "DELETE" https://api.github.ibm.com/repos/eric-w-gustafson/test

    if not oauth_token:
        raise ValueError("A valid oauth token must be supplied to query user repos")

    if not git_user:
        raise ValueError("A valid git user be supplied to query user repos")

    buf = io.BytesIO()

    # make sure the user is in the repo name - just as an added sanity check
    if not re.search(git_user, repo):
        raise ValueError("Git user ({}) was not found in repo: {}".format(git_user, repo))

    curl_header = "Authorization: token {}".format(oauth_token)

    curl_request = pycurl.Curl()
    curl_request.setopt(pycurl.URL, repo)
    curl_request.setopt(pycurl.WRITEFUNCTION, buf.write)
    curl_request.setopt(pycurl.CONNECTTIMEOUT, 5)
    curl_request.setopt(pycurl.TIMEOUT, 8)
    curl_request.setopt(pycurl.HTTPHEADER, [curl_header])
    curl_request.setopt(pycurl.CUSTOMREQUEST, "DELETE")

    curl_request.perform()

    http_status = curl_request.getinfo(pycurl.HTTP_CODE)

    if http_status not in (200, 204): # 204 is good but no content
        raise ExecutionError("Failed to delete github repository. Http status code: {}".format(http_status))


def get_creds_from_hub_config(hub_config_path):
    """
    * from the hub config, parse the git user and oauth token
    :param config_path: location of hub config
    :return: git user/oauth tuple
    """

    hub_config = ""

    try:
        with open(hub_config_path, "r") as myfile:
            yaml = YAML()  # default, if not specfied, is 'rt' (round-trip)
            hub_config = yaml.load(myfile)

    except:
        raise ConfigError("Unable to parse yaml: {}".format(hub_config_path))

    return hub_config['github.ibm.com'][0]['user'], hub_config['github.ibm.com'][0]['oauth_token']
