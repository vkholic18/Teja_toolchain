#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script verifies that the workspace dependencies file exists and is in the right format

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO

# This script also implements skipping logic through: SKIP_CONVENTIONAL_COMMIT_ENFORCEMENT

# =============================================================================================

# Set flags
set -e

# Source tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

START=$(date +%s)

# Skip if needed
generic_skip $SKIP_VERIFY_WORKSPACE_DEPENDENCIES_FILE

# If no WORKSPACE_DEPENDENCIES_FILE_NAME was exported before executing the script, give the default value
export WORKSPACE_DEPENDENCIES_FILE_NAME=${WORKSPACE_DEPENDENCIES_FILE_NAME:-"workspace-dependencies.yaml"}

# Move to the workspace
pushd ${PATH_TO_WORKSPACE_REPO}

# Verify if the file exists at all
if [[ -f "${WORKSPACE_DEPENDENCIES_FILE_NAME}" ]]
then
    echo "workspace dependencies file found, proceed to validate..."

    # Set full path to file
    FULL_PATH=${PWD}/${WORKSPACE_DEPENDENCIES_FILE_NAME}

    # Now we can come back
    popd

    # Install CI python tools
    python3 -m pip install -q ${PATH_TO_GENCTL_CI}/tools/ci_python_tools

    # Export required var to make it available in the python script
    export PATH_TO_WORKSPACE_DEPENDENCIES_FILE=${FULL_PATH}

    # Execute
    generic_python_execution ${PATH_TO_GENCTL_CI}/scripts/verify_workspace_dependencies_file ${PATH_TO_GENCTL_CI}/scripts/retry.sh
    END=$(date +%s)
    DIFF=$(( $END - $START ))
    echo -e "${BYellow}Verify workspace dependencies file took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
else
    echo "No workspace-dependencies file found in the root of the repository"
    exit 1
fi
