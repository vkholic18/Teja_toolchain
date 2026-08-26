#!/usr/bin/env python3

##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2019
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

"""
" this script will pull the jira ticket number and title from a commit
"""

###############################################################################
# I M P O R T S
###############################################################################

import collections
import sys
import logging
import subprocess
import re

###############################################################################
# C L A S S E S
###############################################################################

class RelInfoException(Exception):
    """ Exception Wrapper """

###############################################################################
# F U N C T I O N S
###############################################################################

def local_cmd(cmd, log_stdout=False, log_stderr=False, throw_exc=True, stdin=None):
    """
    execute cmd on local system.  Based on a
    similar version of this func from hostos-common-tools
    """
    # run cmd as utf-8 and convert back
    cmd2 = cmd.encode('utf-8')
    stdin = stdin.encode('utf-8') if stdin else None
    proc = subprocess.Popen(
        cmd2, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, close_fds=True, shell=True)
    result = proc.communicate(stdin)
    stdout = result[0].decode('utf-8') if result[0] else ''
    stderr = result[1].decode('utf-8') if result[1] else ''

    if (log_stdout and stdout) or (log_stderr and stderr):
        logger = logging.getLogger()
        logger.info('Command: {}'.format(cmd))
        if proc.returncode != 0:
            logger.warning('command failed with rc {}.'.format(proc.returncode))
        if log_stdout and stdout:
            logger.info('stdout: {}'.format(stdout))
        if log_stderr and stderr:
            logger.info('stderr: {}'.format(stderr))

    # raise exception if requested
    if proc.returncode != 0 and throw_exc:
        raise RelInfoException(result[1].splitlines()[0])

    return proc.returncode, stdout, stderr

def find_string_and_write_to_file(regex, string_to_search, filename):
    """
    " find a match, using regex, in string_to_search, and write out the match to filename
    """
    logger = logging.getLogger()

    logger.debug(f"std_out: {string_to_search}")

    for line in string_to_search.splitlines():
        logger.debug('Searching commit line: {}'.format(line))
        match_obj = re.search(regex, line)
        break

    if match_obj:
        matched_string = match_obj.group(1).upper().strip()
        logger.info(f"jira meta match: {matched_string}")
    else:
        raise ValueError(f"we were unable to locate a valid jira meta in commit: {string_to_search}")

    try:
        with open(filename, 'w') as meta_f:
            meta_f.write(matched_string)

    except IOError:
        logger.error("Unable to open file for writing ({}): reason: {}".format(filename, sys.exc_info()[0]), file=sys.stderr)
        sys.exit(1)

def main():
    """
    " from the commit, grab the jira number and title
    """
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger()

    search_methods = collections.OrderedDict()
    search_methods['subject'] = 's'
    search_methods['body'] = 'b'

    for key, val in search_methods.items():

        logger.info(f"searching the commit {key} for the jira metadata")

        cmd = f"git log -n 1 --pretty=tformat:\"%{val}\" HEAD" # test using 6833889548528b1836b14a2a30740c8d45a5ded3 on genctl-ci repo
        logger.debug('cmd: {}'.format(cmd))
        ret_code, std_out, _ = local_cmd(cmd)

        if ret_code != 0:
            logger.error('cmd: {} failed with rc {}'.format(cmd, ret_code))
            sys.exit(1)

        try:
            find_string_and_write_to_file(r':(.*):', std_out, 'jira_id')

            find_string_and_write_to_file(r':(.*)', std_out, 'pr_title')

            break # skip the loop if we came through cleanly
        except ValueError as e:
            logger.error(e)
            continue
    else:
        logger.error("We failed to find the jira metadata in the merge commit")
        sys.exit(1)

###############################################################################
# M A I N
###############################################################################

if __name__ == '__main__':
    main()
