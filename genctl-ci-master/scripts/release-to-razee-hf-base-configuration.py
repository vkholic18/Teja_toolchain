#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

import sys
import yaml

infile = sys.argv[1]
update_feature_flag = sys.argv[2]
new_version = sys.argv[3]

do_exist = False

with open(infile, 'r') as data:
    base_environment = yaml.safe_load(data)

feature_flags = base_environment["apps"]["feature_flags"]["vpc-ci"]
for feature_flag in feature_flags:
    ff_name = feature_flag["name"]
    if update_feature_flag == feature_flag["name"]:
        feature_flag["default"]["variation_value"] = new_version
        do_exist = True
        try:
            for rule in feature_flag["rules"]:
                for clause in rule["clauses"]:
                    if clause["attribute"] == "mzone":
                        rule["variation_value"] = new_version
        except KeyError:
            print(f"rule attribute is not found for: {ff_name} Continue ...")
        break

# Add missing feature flag if it doesn't already exist
if do_exist == False:
    new_feature_flag = {'name': update_feature_flag, 'default': {'variation_value': new_version}}
    feature_flags.append(new_feature_flag)

with open(infile, 'w') as new_file:
    yaml.dump(base_environment, new_file, sort_keys=False)