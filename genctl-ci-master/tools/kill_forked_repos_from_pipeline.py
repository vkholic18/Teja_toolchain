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
* 1.) Accept 1 or multiple test oriented yaml files
* 2.) For each yaml file, parse it and make note of the git urls
* 3.) Contact github and get all user repos that are 1.) owned by them 2.) is a fork
* 4.) From both lists, compare the two and denote the similarities
* 5.) If we found any, ask the user if they wish to delete them
* 6.) If yes, delete all repos located in both lists
"""

###############################################################################
# I M P O R T S ###############################################################
###############################################################################

import argparse
import logging
import sys

from concourse.concourse_pipeline import ConcoursePipeline
from concourse.user_exceptions import ExecutionError, ConfigError
from concourse.git_functions import get_user_owned_repos, delete_user_repo

###############################################################################
# F U N C T I O N S ###########################################################
###############################################################################


def setup_logger(debug_enabled=False):
    """
    * Setup up the logger and return a handle
    """
    # set the logger to show the time/level/message
    # stdout logging is sufficient

    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.DEBUG if debug_enabled is True else logging.INFO)

    return logger


def main():
    """
    * 1.) Accept 1 or multiple test oriented yaml files
    * 2.) For each yaml file, parse it and make note of the git urls
    * 3.) Contact github and get all user repos that are 1.) owned by them 2.) is a fork
    * 4.) From both lists, compare the two and denote the similarities
    * 5.) If we found any, ask the user if they wish to delete them
    * 6.) If yes, delete all repos located in both lists
    """

    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", dest="debug", action="store_true",
                        help="Increase verbosity", default=False)
    required_args = parser.add_argument_group('required named arguments:')
    required_args.add_argument("--yaml", action="append", required=True,
                               help=("Concourse pipeline config to scan for git forks. Can be used multiple times. "
                                     "Absolute path"))
    required_args.add_argument("--oauth", required=True,
                               help="OAuth user token for github")
    required_args.add_argument("--gituser", required=True,
                               help="Your Github username")

    args = parser.parse_args()

    logger = setup_logger(debug_enabled=True if args.debug is True else False)

    logger.debug("options : {}".format(args))

    concourse_configs = list()

    # we are ONLY interested in the git (test) repo's that are identified in the supplied yaml file(s)
    for yaml_file in args.yaml:
        try:
            concourse_configs.append(ConcoursePipeline(yaml_file, sandbox_dir=None, git_user=args.gituser))
        except ConfigError as e:
            logger.error(e)
            sys.exit(1)

    # parse each yaml, swap out vars as test, and skip writing out content - we don't need it.
    for pipeline in concourse_configs :
        pipeline.parse_config_as_test(write_out_test_yamls=False)

    # now that the configs are parsed/translated, we should have a list of repos to compare to
    for pipeline in concourse_configs:
        for fork in pipeline.git_forks:
            logger.debug("yaml fork: {}".format(fork))

    repos_to_delete = list()

    try:
        user_repos = get_user_owned_repos(args.oauth, forks_only=True)

        for api_url, ssh_url in user_repos:
            logger.debug("api_url: {}".format(api_url))
            logger.debug("ssh_url: {}".format(ssh_url))

            if ssh_url in pipeline.git_forks:
                repos_to_delete.append((api_url, ssh_url))

        if repos_to_delete:
            logger.warning("The following forked repos will be deleted:")
            for repo in repos_to_delete:
                logger.warning("\t{}".format(repo[1]))

            logger.warning("")
            logger.warning("Are you sure you wish to proceed (y/[n]): ")

            response = input(':')
            if response in ['y', 'Y']:
                # start deleting
                for repo in repos_to_delete:
                    logger.info("deleting repo: {}".format(repo[1]))
                    delete_user_repo(repo[0], args.gituser, args.oauth)
        else:
            logger.info("There were no repos found to be deleted")

    except (ValueError, ExecutionError) as e:
        logger.error(e)
        sys.exit(1)


###############################################################################
# M A I N #####################################################################
###############################################################################
if __name__ == "__main__":
    main()
