# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Sets up env to run the merge_vetted_version_environment_yaml.py file and then runs
#              it
#
# Use:
#    source merge_vetted_version_environment_yaml.py environment.yaml vetted_versions.yaml generated_environment.yaml
#
# Args
#     $1 - Environment.yaml
#     $2 - vetted_versions.yaml file
#     $3 - output generated_environment.yaml file
#

#!/bin/bash

export BASE_ENVIRONMENT_PATH=$1
export VETTED_VERSIONS_PATH=$2
export MERGE_OUTPUT_PATH=$3

python3 ${PATH_TO_DEV_REGIONS_REPO}/scripts/merge_vetted_version_environment_yaml.py
