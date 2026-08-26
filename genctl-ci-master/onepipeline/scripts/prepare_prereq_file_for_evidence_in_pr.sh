#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script creates a file that is used for being able to collect evidence on PR pipelines

# #############################################
# # The following environment variables need to be set before executing the script:
# # PIPELINE_TEMPLATE_TYPE

if [[ "${PIPELINE_TEMPLATE_TYPE}" == "razee" ]]
then
    # If we are in razee pipeline we can assume that we already checked vetted files and even more, that we have the JSON and we can use it to extract info
    
    # Some logic and vars needed to check the file
    GIT_SHA=$(load_repo app-repo commit)
    SHORT_SHA=${GIT_SHA:0:12}
    JSON_FILE_NAME="${CANDIDATE_FILES_JSON_FILE_NAME_PREFIX}_${SHORT_SHA}.json"

    # Move to the TMP folder 
    pushd "${CI_TEMP_DIR}"

    # Check file exists

    if [[ -f "${PWD}/${JSON_FILE_NAME}" ]]
    then
        # Set the full path to the file in a variable
        FPTF="${PWD}/${EVIDENCE_IN_PR_PREREQ_COMMANDS_FILE_NAME}"

        echo "We are on a razee workspace; pre-requisites file for evidence in PR will have information from the dev-integration run"

        MERGE_TO_DEV_INT_PIPELINE_ID=$(jq '.commons.pipeline_id' "${PWD}/${JSON_FILE_NAME}")
        MERGE_TO_DEV_INT_PIPELINE_RUN_ID=$(jq '.commons.pipeline_run_id' "${PWD}/${JSON_FILE_NAME}")

        # Create a file that we will use later (This is important: file is only created, not sourced yet)
        # IMPORTANT: 
        # Though the name indicates root_pipeline_id and root_pipeline_run_id this is actually the pipeline_id and pipeline_run_id of the merge to dev-integration
        # Seems OnePipeline uses those names in the background to link with the asset of the merge to dev-int 
        {   
            echo "set_env root_pipeline_id ${MERGE_TO_DEV_INT_PIPELINE_ID}";
            echo "export_env root_pipeline_id";
            echo "set_env root_pipeline_run_id ${MERGE_TO_DEV_INT_PIPELINE_RUN_ID}";
            echo "export_env root_pipeline_run_id";
        } >> "${FPTF}" && chmod +x "${FPTF}"

        echo "Succesfully created file ${FPTF}"
        echo "Content of the file is the following"
        cat "${FPTF}" 
    else
        echo "At this point we expected to have a file ${PWD}/${JSON_FILE_NAME}"
        echo "Will exit with error"
        exit 1
    fi

    # Come back
    popd
else
    echo "No implementation yet"
fi
