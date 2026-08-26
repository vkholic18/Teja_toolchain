#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
#(C) Copyright IBM Corp. 2020
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
infile  = sys.argv[2]

logger = setup_logger()
with open(infile) as orig_file:
    data = json.load(orig_file)

if submodule in data:
    logger.info("Attribute {} exist ".format(submodule))
    sys.exit(0)
else:
    logger.info("Attribute {} does not exist".format(submodule))
    sys.exit(100)


