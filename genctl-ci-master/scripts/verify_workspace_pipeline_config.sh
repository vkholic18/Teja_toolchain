#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script verifies the pipeline.yaml file

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE

#Set flags
set -u

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

START=$(date +%s)

${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/verify_workspace_pipeline_yaml.sh ${PATH_TO_WORKSPACE_REPO} true

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Validate pipeline yaml took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"