#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

import sys
import yaml

infile = sys.argv[1]
component = sys.argv[2]
new_version = sys.argv[3]

with open(infile, 'r') as data:
    vetted_versions = yaml.safe_load(data)

# check if we are using the new vetted versions format
if vetted_versions.get("apps"):
    bundles = vetted_versions["apps"]["release_bundles"]
    for bundle in bundles:
        if bundle["name"] == component:
            bundle["version"] = new_version
else:
    for versions, bundles in vetted_versions.items():
        for bundle_name, bundle_ver in bundles.items():
            if bundle_name == component:
                bundles[bundle_name] = new_version

with open(infile, 'w') as new_file:
    yaml.dump(vetted_versions, new_file, sort_keys=False)
