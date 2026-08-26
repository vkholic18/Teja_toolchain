#!/usr/bin/env python
#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# This script formats the build environment package list as json

import os
import json


def find_col_widths(inpstr):
    """
    Given a string, finds the length of substrings composed of "="
    :param inpstr: input string
    :return: list of columns with start and end indexes
    """

    def add_col(a_cols, char, index, length):
        """
        Adds column to the list of columns
        :param a_cols: list of columns
        :param char: substring character
        :param index: substring index
        :param length: substring length
        :return: list of columns
        """
        a_cols.append({
            "char": char,
            "start": index,
            "end": index + length
        })
        return a_cols

    cols = []
    sub_length = 1
    sub_index = 0
    for i in range(1, len(inpstr)):
        if inpstr[i] == inpstr[i-1]:
            sub_char = inpstr[i]
            sub_length += 1
            if i == len(inpstr)-1:
                add_col(cols, sub_char, sub_index, sub_length)
        else:
            add_col(cols, sub_char, sub_index, sub_length)
            sub_length = 1
            sub_index = i
            sub_char = inpstr[i]

    # Filter out columns that don't contain "="
    cols[:] = [d for d in cols if d["char"] == "="]

    return cols


print("Creating a list of build environment packages.")
lines = []
for line in os.popen('dpkg -l').readlines():
    if line.startswith("++"):
        col_widths = find_col_widths(line)
    if line.startswith("ii"):
        lines.append(line.rstrip("\n"))
pkgs = []
for line in lines:
    pkgs.append({
        "BUILD_ENV_PKG_NAME": line[col_widths[0]["start"]:col_widths[0]["end"]].strip(),
        "BUILD_ENV_PKG_VER": line[col_widths[1]["start"]:col_widths[1]["end"]].strip(),
        "BUILD_ENV_PKG_ARCH": line[col_widths[2]["start"]:col_widths[2]["end"]].strip(),
        "BUILD_ENV_PKG_DESC": line[col_widths[3]["start"]:col_widths[3]["end"]].strip()
    })

data = {"buildenv": [
    {
        "BUILD_ENV_NAME": "golang-ci",
        "BUILD_ENV_PKGS": pkgs
    }
]}

print("Writing the list to the manifest.")
with open("manifest.json", "r+") as manifest:
    manifest.write(json.dumps(data, indent=4, sort_keys=False))
