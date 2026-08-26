#!/usr/bin/env python
#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# This script formats the go package list as json
import os
import json


print("Creating a list of go packages.")
pkgs = []
for line in os.popen('go list -f "{{.Name}} {{.ImportPath}}" ...').readlines():
    pkgs.append({
        "GO_PKG_NAME": line.split()[0],
        "GO_PKG_IMPORT_PATH": line.split()[1]
    })

data = {"GO_PKGS": pkgs}

print("Writing the list to the manifest.")
with open("manifest.json", "r+") as manifest:
    manifest.write(json.dumps(data, indent=4, sort_keys=False))