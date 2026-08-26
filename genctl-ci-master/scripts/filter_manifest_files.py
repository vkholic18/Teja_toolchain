#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
#(C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# Description:
    # Filter prepared by nextgen-deploy tool manifests by manifests relevant for given component.
    # For given component loop though the component-input/components.json
    # if "manifest_label" firld exist it will be the base name for search in the manifest files
    # if not the "name" is the base for search


import json
import sys
import logging
import glob
import shutil
import os



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
aorta_manifests = sys.argv[3]
aorta_manifests_fltered = sys.argv[4]

if not os.path.exists(aorta_manifests_fltered):
    os.makedirs(aorta_manifests_fltered)

logger = setup_logger()
with open(infile) as orig_file:
    data = json.load(orig_file)

for component in data:
    if submodule == component['name']:
        try:
            base_manifest_name = component['manifest_label']
            base_manifest_name = base_manifest_name.replace(":", "_")
        except KeyError:
            base_manifest_name = component['name']
            pass
        file_pattern = aorta_manifests + '/*' + base_manifest_name + '.yaml'
        for manifest_file in glob.glob(file_pattern):
            shutil.copy(manifest_file, aorta_manifests_fltered)

