#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

"""
Script to process the output of some git commands in order to build the details added to the ${GIT_HASH}.txt file in
the genctl-change-history repository
"""

###############################################################################
# I M P O R T S ###############################################################
###############################################################################

import argparse
import datetime
import logging
import pygit2
import sys

##############
# CONSTANTS
##############
# GLOBALS
logger = logging


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
    # This gives more info for debugging
    # formatter = logging.Formatter('%(asctime)s {%(funcName)s:%(lineno)d} %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger_setup = logging.getLogger()
    logger_setup.addHandler(handler)
    logger_setup.setLevel(logging.DEBUG if debug_enabled is True else logging.INFO)
    logger_setup.info("Logger level set to \"{}\"".format(logger_setup.level))

    return logger_setup


def parse_args():
    """
    Parse the arguments passed when calling this file.
    :return:
    """
    parser = argparse.ArgumentParser(description="Parser to take required and optional values for the script")
    parser.add_argument('-d', '--debug', help="When used, enables debug mode. No args", required=False,
                        dest="debug", default=False, action='store_true')
    parser.add_argument('-c', '--component', help="Indicates what the workspace component is to this script",
                        required=False, dest="component", default="")
    parser.add_argument('-p', '--prior-hash', help="The previous Git hash of the component",
                        required=True, dest="prior_hash", default="")
    parser.add_argument('-n', '--new-hash', help="The new Git hash of the component", required=True,
                        dest="new_hash", default="")
    parser.add_argument('-l', '--location', help="The path of the component workspace", required=False,
                        dest="component_path", default="./")
    args = parser.parse_args()
    return args


def parse_commits(hash_start="", hash_end="", component="", component_path="./"):
    """
    Takes input of the start hash, end hash, and optionally the component name \n
    start_hash: The hash to start from, this should be the hash of the commit with the later date (MOST RECENT) \n
    end_hash: The hash to end at, this should be the hash of the commit with the earlier date (LEAST RECENT) \n
    component: The name of the component, if included will output the full file contents rather than only the commits \n
    Return result: output with lines equal to the size of commits between start and end hash minus one. \n
    """
    component_repository = pygit2.Repository(component_path)  # defaults to current path if not set

    # Code for local testing
    # component_repository = pygit2.Repository('../../genctl-release')
    # hash_start = component_repository.head.target.hex
    # hash_end = component_repository.revparse("HEAD~5").from_object.hex
    # component = "component-name"

    # Do some checks on the inputs
    if hash_start is None or hash_start == "" or hash_end is None or hash_end == "":
        logger.error("One of the required hashes was not set to a valid value")
        sys.exit(1)

    commit_list = list()

    start_adding = False

    output_string = ""

    for commit in component_repository.walk(component_repository.head.target, pygit2.GIT_SORT_TOPOLOGICAL):

        if commit.hex == hash_start:
            logger.debug(f"found the start {commit.hex}")
            start_adding = True

        if commit.hex == hash_end:
            logger.debug(f"found the end {commit.hex}")
            break

        if start_adding:
            commit_list.append(commit)

    # Verify we have a non-zero list. If it is zero, then the output is empty and something is wrong
    if len(commit_list) == 0:
        logger.error("Something went wrong, no valid commits were found")
        sys.exit(1)

    # If the component was passed, include it in the output, if not, assume it will be added by something else
    if component != "":
        output_string += f"{component}:\n"

    # <short commit hash> <date> <author email> <first line of commit>
    for commit in commit_list:
        commit_date = datetime.datetime.fromtimestamp(commit.commit_time) + datetime.timedelta(
            hours=(commit.commit_time_offset / 100))
        commit_msg = commit.message.split('\n')[0]
        output_string += f'  {commit.hex[0:8]} {commit_date.strftime("%Y-%m-%d")} {commit.committer.email} {commit_msg}\n'

    return output_string


def main():
    """
    Main function, determines what the script should do when called
    """
    # Setup variables
    args = parse_args()
    debug = args.debug
    new_hash = args.new_hash
    prior_hash = args.prior_hash
    component = args.component
    component_path = args.component_path

    ##################
    # CONSTANTS
    ##################

    global logger

    #####################
    # COMMANDS
    #####################
    logger = setup_logger(debug)
    logger.debug("prior_hash: " + prior_hash)
    logger.debug("new_hash: " + new_hash)

    text_to_return = parse_commits(new_hash, prior_hash, component, component_path)

    # print so that the returned text is the "output" of this script
    logger.info(f"\n{text_to_return}")
    print(text_to_return)

    return text_to_return


###############################################################################
# M A I N #####################################################################
###############################################################################


if __name__ == "__main__":
    main()
