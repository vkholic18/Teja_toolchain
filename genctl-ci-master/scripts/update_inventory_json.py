#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#


import json
import sys
import logging

def setup_logger():
    """
    Configures logger and formatting
    Returns:
        logger: logger object
    """

    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

    return logger

submodule = sys.argv[1]
git_ref = sys.argv[2]
url  = sys.argv[3]
infile  = sys.argv[4]
outfile = sys.argv[5]

logger = setup_logger()
with open(infile) as orig_file:
    data = json.load(orig_file)

# update git ref
try:
    data[submodule]['hash'] = git_ref
except KeyError:
    logger.error("Component does not exist in the inventory file. It's not a part of the release")
    exit(1)

# update git url
if url:
    data[submodule]['url'] = url

with open(outfile, 'w') as new_file:
    json.dump(data, new_file, indent=4)
