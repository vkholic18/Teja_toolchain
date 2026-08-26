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
* 1.) scan through all the config
* 2.) read each 'resource' block in each config
* 3.) for any that appear to have hardcodes, extract it out and replace it with a substitution variable
* 4.) write out a new pipeline config that can be used for test (devoid of hardcodes)
* 5.) write out a new credentials/environment yaml that contains all the substitutions made from the pipeline config
"""

###############################################################################
# I M P O R T S ###############################################################
###############################################################################

import logging
import os
import sys
import argparse

from concourse.git_functions import is_hub_installed_and_configured, get_creds_from_hub_config
from concourse.user_exceptions import ExecutionError, ConfigError
from concourse.concourse_pipeline import ConcoursePipeline

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


def discover_yamls(yamldir, user_specified_yamls):
    """
    * locate all the yamls to parse and send back to caller
    """
    logger = logging.getLogger()

    if yamldir is not None:
        logger.debug("changing directory to: {}".format(yamldir))
        os.chdir(yamldir)

    logger.info("Searching for pipeline configs in dir: {}".format(os.getcwd()))

    yamls = list()

    extensions = ['.yaml', '.yml']

    for artifact in os.listdir(os.getcwd()):

        logger.debug("Discovered artifact: {}".format(artifact))

        if os.path.isfile(artifact) is True:
            if user_specified_yamls:
                if os.path.basename(artifact) in user_specified_yamls:
                    logger.info("Candidate for parsing: {}".format(artifact))
                    yamls.append(artifact)
            else:
                if os.path.splitext(artifact)[1] in extensions:
                    logger.info("Candidate for parsing: {}".format(artifact))
                    yamls.append(artifact)

    return yamls


def main():
    """
    * 1.) scan through all the config - or those specifid solely with --yaml
    * 2.) read each 'resource' block in each config
    * 3.) for any that appear to have hardcodes, extract it out and replace it with a substitution variable
    * 4.) write out a new pipeline config that can be used for test (devoid of hardcodes)
    * 5.) write out a new credentials/environment yaml that contains all the substitutions made from the pipeline config
    * 6.) for all git repos found, clone and fork and put those in to be used for test
    """

    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", dest="debug", action="store_true",
                        help="Increase verbosity", default=False)
    parser.add_argument("--yaml", action="append",
                        help="Include a specific Concourse pipeline config. Can be used multiple times. Relative path.")
    parser.add_argument("--skip_clone_and_fork", dest="skip_clone_and_fork", action="store_true",
                        help="Skip cloning and forking the repos - just translate the yaml file", default=False)
    parser.add_argument("--sandboxdir",
                        help="Directory (created if does not exist) that will contain all Git test forks")
    required_args = parser.add_argument_group('required named arguments:')
    required_args.add_argument("--yamldir", required=True,
                               help=("Directory that contains the pipeline yaml's. All config found, unless --yaml is"
                                     "used, will be processed"))

    args = parser.parse_args()

    logger = setup_logger(debug_enabled=True if args.debug is True else False)

    logger.debug("options : {}".format(args))

    if not args.skip_clone_and_fork and not args.sandboxdir:
        logger.error("--sandboxdir must be provided (will contain user forked repos)")
        parser.print_usage()
        sys.exit(1)

    # check for pre-requisite of HUB being installed and mention to the user
    # https://hub.github.com/
    # brew install hub
    config_path = ""

    try:
        config_path = is_hub_installed_and_configured()
    except ConfigError as e:
        logger.error(e.value)
        sys.exit(1)

    (git_user, _) = get_creds_from_hub_config(config_path)

    # if no yaml switch is used, send an empty list

    yamls = discover_yamls(args.yamldir, [] if args.yaml is None else args.yaml)

    concourse_configs = list()

    for yaml_file in yamls:
        try:
            concourse_configs.append(ConcoursePipeline(yaml_file, args.sandboxdir, git_user))
        except ConfigError as e:
            logger.error(e)
            sys.exit(1)

    # parse each yaml, swap out vars as test, and write out the updated file (and its constituent sub vars file)
    for pipeline in concourse_configs:
        pipeline.parse_config_as_test()

    if not args.skip_clone_and_fork:
        for pipeline in concourse_configs:
            try:
                pipeline.create_git_clones_and_forks()
            except (ValueError, ExecutionError, OSError) as e:
                logger.error(e)
                sys.exit(1)


###############################################################################
# M A I N #####################################################################
###############################################################################
if __name__ == "__main__":
    main()
