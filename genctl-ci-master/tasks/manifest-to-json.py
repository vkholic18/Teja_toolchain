#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

import os
import json

lines = os.popen('dpkg -l | grep "^ii"').read().split('\n')[5:-1]
i = 0
while len([l for l in lines[i].split('  ') if l]) != 5:
   i += 1
offsets = [lines[i].index(l) for l in lines[i].split('  ') if len(l)]
pkgs = {}
for line in lines:
    parsed = []
    for i in range(len(offsets)):
        if len(offsets) == i + 1:
            parsed.append(line[offsets[i]:].strip())
        else:
            parsed.append(line[offsets[i]:offsets[i + 1]].strip())
    pkgs.update({'BUILD_ENV_PKG_NAME':parsed[1]:{'BUILD_ENV_PKG_ARCH':parsed[3],'BUILD_ENV_PKG_VER':parsed[2],'BUILD_ENV_PKG_DESC':parsed[4]}})

print (json.dumps(pkgs))
