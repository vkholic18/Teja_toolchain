#!/usr/bin/env bash
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# This script validates YAML files in the genctl-cicd repo

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI

# Helper function
function file_ends_with_newline() {
    [[ $(tail -c1 "$1" | wc -l) -gt 0 ]]
}

# Define paths to the files to be validated
PIPELINE_PARAMS_FILE_PATH="${PATH_TO_GENCTL_CI}/params/pipeline-params.yaml"
PIPELINE_OVERRIDES_FILE_PATH="${PATH_TO_GENCTL_CI}/params/pipeline-overrides.yaml"

# Put them together on a list
FILES_TO_VALIDATE_STRUCTURE="${PIPELINE_PARAMS_FILE_PATH} ${PIPELINE_OVERRIDES_FILE_PATH}"

# Iterate and check that each file is valid, if find a non valid file, exit 1
for file_to_validate in ${FILES_TO_VALIDATE_STRUCTURE}
do 
    python3 -c 'import yaml,sys;yaml.safe_load(sys.stdin)' < "${file_to_validate}"  > /dev/null 2>&1
    if [[ $? -eq 0 ]]
    then
        echo "File ${file_to_validate} is a valid YAML file"
    else
        echo "File ${file_to_validate} is not a valid YAML file"
        echo "Please check the changes you are doing to the file and fix them in order to be a valid YAML file"
        exit 1
    fi
done

# Check that the pipeline-params.yaml file ends with a new line
if ! file_ends_with_newline "${PIPELINE_PARAMS_FILE_PATH}"
then
    echo "${PIPELINE_PARAMS_FILE_PATH} should end with a new line character"
    exit 1
fi