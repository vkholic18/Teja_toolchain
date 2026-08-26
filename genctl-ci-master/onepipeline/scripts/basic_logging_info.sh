#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# First check if the file wieh basic logging info exists:
# If yes, just nothing to do
# If no, need to do some logic and create it

basic_logging_file_path="${CI_TEMP_DIR}/basic_logging_info.sh" 

if [[ ! -f "${basic_logging_file_path}" ]]
then
    # Additional check to proceed to create file only if we have PIPELINE_TYPE
    if [[ ! -z "${PIPELINE_TYPE}" ]]
    then
        # Go to genctl-ci and get the branch and sha
        pushd "${PATH_TO_GENCTL_CI}"
        genctl_ci_branch=$(git rev-parse --abbrev-ref HEAD)
        genctl_ci_sha=$(git rev-parse --verify HEAD)
        popd 

        # Create file with info
        {
            echo "## CI_INFO_FOR_SEARCH $(date) | "
            echo "repo_of_run_name=${ORG_AND_REPO} | "
            echo "pipeline_run_number=${BUILD_NUMBER} | "
            echo "repo_of_run_pipeline_type=${PIPELINE_TYPE} | "
            echo "repo_of_run_template_used=${PIPELINE_TEMPLATE_TYPE} | " 
            echo "repo_of_run_sha=$(load_repo app-repo commit) | "
            echo "genctl-ci_branch=${genctl_ci_branch} |"
            echo "genctl-ci_SHA=${genctl_ci_sha} |"
            echo "pipeline_stage_of_ci_info_file_creation=${STAGE} |"
            echo "pipeline_run_url=${PIPELINE_RUN_URL} ##"

        } >> "${basic_logging_file_path}"

        # Show the file content
        # This will appear in the pipeline output but mostly is helpful for searching in logs with IBM Cloud logs
        echo $(cat "${basic_logging_file_path}")
    fi
fi