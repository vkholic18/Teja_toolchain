#!/usr/bin/env bash

# This script can be useful to see which workspaces implement a specific logic

# The way to find this is to find which override files have the key 
# (And optionally value) that we search and that will tell us the workspaces

# Example of use

# PATH_TO_OVERRIDE_FOLDER="/Users/davidfli/Repos/genctl-ci/params/pipeline-overrides"
# KEY_TO_SEARCH="skip-conventional-commit-enforcement"
# KEY_VALUE="false"

# The path to the folder where all the override files are stored
PATH_TO_OVERRIDE_FOLDER=""

# The name of the key to search (Mandatory)
KEY_TO_SEARCH=""

# The value of the key (Optional)
KEY_VALUE=""

# The line to search with grep starts with the key
LINE_TO_SEARCH="${KEY_TO_SEARCH}"

# If we have value, add it
if [[ -n "${KEY_VALUE}" ]]
then
    LINE_TO_SEARCH="${LINE_TO_SEARCH}: ${KEY_VALUE}"
fi

# Search (Basic)
grep -lri "${LINE_TO_SEARCH}" "${PATH_TO_OVERRIDE_FOLDER}" | sort

# Search (More complex, should list the "workspace")
# (Might be simpler/better ways using regex or similar, but this does the job)

# TYPES_OF_TEMPLATES="
#     s/-dev-integration-pr.yaml//g;
#     s/-pr.yaml//;
#     s/-dev-integration-merge.yaml//;
#     s/-merge.yaml//
# "
#grep -lri "${LINE_TO_SEARCH}" "${PATH_TO_OVERRIDE_FOLDER}" | sort | awk -F"/override-" '{print $NF}' | sed "${TYPES_OF_TEMPLATES}"
