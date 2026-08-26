#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023, 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script is used for moving files related to the inventory candidate files flow

# This script supports:
    # Moving JSON, ZIP & packages from pre-release to vetted (merge to dev-integration pipeline razee and regular merge of non-razee)
    # Moving ZIP & packages from vetted to final location (merge to master razee - and packages also for regular merge of non-razee)

# The script requires to get the following argument
# MOVE_FILES_MODE

# The following environment variables need to be set before executing this script

# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO, ORG_AND_REPO, PIPELINE_TYPE, SKIP_MOVE_INVENTORY_FILES
# PIPELINE_TEMPLATE_TYPE
# ARTIFACTORY_BASE_URL, CC_ARTIF_ACCESS_TOKEN
# ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH, ARTIFACTORY_GENERIC_REPO_PATH
# CANDIDATE_FILES_JSON_FILE_NAME_PREFIX, CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX
# CANDIDATE_FILES_PRE_RELEASE_DIR, CANDIDATE_FILES_VETTED_DIR
# ZIP_FINAL_LOCATION_DIR

MOVE_FILES_MODE=$1

# In additional the following variables are optional and if not have values they will take the default
MOVE_FILES_DRY_RUN=${MOVE_FILES_DRY_RUN:-"false"}
OVERRIDE_ORG_RESTRICTION_MOVE_FILES=${OVERRIDE_ORG_RESTRICTION_MOVE_FILES:-"false"}
MOVE_FILES_SKIP_MOVE_PACKAGES=${MOVE_FILES_SKIP_MOVE_PACKAGES:-"false"} # By default we DO want to move packages so therefore, skip=false
SKIP_MOVE_PACKAGES_FROM_VETTED_TO_FINAL_DESTINATION=${SKIP_MOVE_PACKAGES_FROM_VETTED_TO_FINAL_DESTINATION:-"false"} # By default we DO want to move packages from vetted to final destination so therefore, skip=false

supported_move_files_modes="move_from_pre_release_to_vetted move_from_vetted_to_final_destination"

if [[ "$supported_move_files_modes" =~ (^|[[:space:]])$MOVE_FILES_MODE($|[[:space:]]) ]]
then
    echo "Move mode is: ${MOVE_FILES_MODE}"
    
    # Source tools
    source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

    # Skip if needed
    generic_skip $SKIP_MOVE_INVENTORY_FILES

    # Check if repo is production org & flag
    if ! repo_is_from_prod_org ${PATH_TO_WORKSPACE_REPO}
    then
        if [ "$OVERRIDE_ORG_RESTRICTION_MOVE_FILES" == "true" ]; then
            echo "Repo is not a production repo, however, OVERRIDE_ORG_RESTRICTION_MOVE_FILES is true, so proceeding to move files..."
        else
            echo "By default, move files is not enabled for organizations that are not 'production'"
            echo "It might be the case that your repository is a fork..."
            echo "If you want to run move files anyway, set OVERRIDE_ORG_RESTRICTION_MOVE_FILES flag to true" 
            exit 0
        fi
    fi

    if [[ "${PIPELINE_TEMPLATE_TYPE}" == "razee" ]]
    then
        # Check in which pipeline type we are and configure to move accordingly
        if [ "$PIPELINE_TYPE" = "dev-integration-merge" ]
        then
            echo "This is a razee merge to dev-integration pipeline, will move ZIP and JSON from pre-release to vetted"

            # In merge to dev-integration we want to always move (Override each time)
            CHECK_IF_FILE_EXISTS_BEFORE_MOVING="false"

            # Get the SHA
            GIT_SHA=$(load_repo app-repo commit)

            # Take a "shorter" version of the SHA
            SHORT_SHA=${GIT_SHA:0:12}

            # Set the name of the files
            JSON_FILE_NAME="${CANDIDATE_FILES_JSON_FILE_NAME_PREFIX}_${SHORT_SHA}.json"
            ZIP_FILE_NAME="${CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX}_${SHORT_SHA}.zip"

            BASE_PATH_TO_MOVE_FROM="${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_PRE_RELEASE_DIR}/${ORG_AND_REPO}"
            BASE_PATH_TO_MOVE_TO="${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_VETTED_DIR}/${ORG_AND_REPO}"

            # Set the files to move
            FILES_TO_MOVE="${JSON_FILE_NAME} ${ZIP_FILE_NAME}"

        elif [ "$PIPELINE_TYPE" = "merge" ]
        then
            echo "This is a razee merge to master pipeline, will move ZIP from vetted to its final location"

            # In merge to master; we don't want to move the file if the file already exists on the location we wanted to move to (In other words, we don't override)
            CHECK_IF_FILE_EXISTS_BEFORE_MOVING="true"

            if [[ ! -z "${RESULT_DEV_INT_SHA}" ]]
            then
                echo "Equivalent dev-integ SHA is: ${RESULT_DEV_INT_SHA}"
                
                # Since on the upload script we cut the SHA to the first 12 characters, we need to do the same here to find & move
                SHORT_DEV_INT_SHA=${RESULT_DEV_INT_SHA:0:12}

                # Set the name of the ZIP file
                ZIP_FILE_NAME="${CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX}_${SHORT_DEV_INT_SHA}.zip"

                BASE_PATH_TO_MOVE_FROM="${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_VETTED_DIR}/${ORG_AND_REPO}"
                BASE_PATH_TO_MOVE_TO="${ARTIFACTORY_GENERIC_REPO_PATH}/${ZIP_FINAL_LOCATION_DIR}/${ORG_AND_REPO}"

                # Set the files to move
                FILES_TO_MOVE="${ZIP_FILE_NAME}"
            else
                echo "At this point, expected to have the equivalent dev-integ SHA on variable RESULT_DEV_INT_SHA, but is empty"
                echo "Will exit with error..."
                exit 1
            fi
        else
            echo "Pipeline type $PIPELINE_TYPE not recognized, exiting with error !!!"
            exit 1
        fi
    elif [[ "${PIPELINE_TEMPLATE_TYPE}" == "globals" ]]
    then
        # Get the SHA
        GIT_SHA=$(load_repo app-repo commit)

        # Take a "shorter" version of the SHA
        SHORT_SHA=${GIT_SHA:0:12}

        # Set the name of the files
        JSON_FILE_NAME="${CANDIDATE_FILES_JSON_FILE_NAME_PREFIX}_${SHORT_SHA}.json"
        ZIP_FILE_NAME="${CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX}_${SHORT_SHA}.zip"

        # For globals if we move from pre-release to vetted, need to move both JSON and ZIP; if not, only the ZIP
        if [[ "${MOVE_FILES_MODE}" == "move_from_pre_release_to_vetted" ]]
        then
            # Move ZIP and JSON from pre_release to vetted
            BASE_PATH_TO_MOVE_FROM="${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_PRE_RELEASE_DIR}/${ORG_AND_REPO}"
            BASE_PATH_TO_MOVE_TO="${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_VETTED_DIR}/${ORG_AND_REPO}"

            # Set the files to move
            FILES_TO_MOVE="${JSON_FILE_NAME} ${ZIP_FILE_NAME}"
        else
            # Move only ZIP from vetted to final destination
            BASE_PATH_TO_MOVE_FROM="${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_VETTED_DIR}/${ORG_AND_REPO}"
            BASE_PATH_TO_MOVE_TO="${ARTIFACTORY_GENERIC_REPO_PATH}/${ZIP_FINAL_LOCATION_DIR}/${ORG_AND_REPO}"

            # Set the files to move
            FILES_TO_MOVE="${ZIP_FILE_NAME}"
        fi
    elif [[ "${PIPELINE_TEMPLATE_TYPE}" == "uuc-ci" ]]
    then
        # Get the SHA
        GIT_SHA=$(load_repo app-repo commit)

        # Take a "shorter" version of the SHA
        SHORT_SHA=${GIT_SHA:0:12}

        # Set the name of the files
        JSON_FILE_NAME="${CANDIDATE_FILES_JSON_FILE_NAME_PREFIX}_${SHORT_SHA}.json"
        ZIP_FILE_NAME="${CANDIDATE_FILES_ZIP_FILE_NAME_PREFIX}_${SHORT_SHA}.zip"

        # For globals if we move from pre-release to vetted, need to move both JSON and ZIP; if not, only the ZIP
        if [[ "${MOVE_FILES_MODE}" == "move_from_pre_release_to_vetted" ]]
        then
            # Move ZIP and JSON from pre_release to vetted
            BASE_PATH_TO_MOVE_FROM="${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_PRE_RELEASE_DIR}/${ORG_AND_REPO}"
            BASE_PATH_TO_MOVE_TO="${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_VETTED_DIR}/${ORG_AND_REPO}"

            # Set the files to move
            FILES_TO_MOVE="${JSON_FILE_NAME} ${ZIP_FILE_NAME}"
        else
            # Move only ZIP from vetted to final destination
            BASE_PATH_TO_MOVE_FROM="${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_VETTED_DIR}/${ORG_AND_REPO}"
            BASE_PATH_TO_MOVE_TO="${ARTIFACTORY_GENERIC_REPO_PATH}/${ZIP_FINAL_LOCATION_DIR}/${ORG_AND_REPO}"

            # Set the files to move
            FILES_TO_MOVE="${ZIP_FILE_NAME}"
        fi
    else
        if [[ $PIPELINE_TYPE == *"merge"* ]]
        then
            # This scenario is a merge pipeline for non-razee workspaces
            # First we need to check if we are moving from vetted to final destination
            # If that is the case then nothing to do because the JSON we keep it in vetted and the ZIP is not relevant because is not razee
            if [[ "${MOVE_FILES_MODE}" == "move_from_vetted_to_final_destination" ]]
            then
                echo "We are in a merge pipeline for a non razee workspace"
                echo "We are moving from vetted to final destination; so nothing to do regarding JSON and deployment ZIP"
            else

                # We need to move the .JSON file with the artifacts information from pre-release to vetted
                # In merge pipeline of non-razee workspaces we always want to move
                CHECK_IF_FILE_EXISTS_BEFORE_MOVING="false"

                # Get the SHA
                GIT_SHA=$(load_repo app-repo commit)

                # Take a "shorter" version of the SHA
                SHORT_SHA=${GIT_SHA:0:12}

                # Set the name of the files
                JSON_FILE_NAME="${CANDIDATE_FILES_JSON_FILE_NAME_PREFIX}_${SHORT_SHA}.json"

                BASE_PATH_TO_MOVE_FROM="${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_PRE_RELEASE_DIR}/${ORG_AND_REPO}"
                BASE_PATH_TO_MOVE_TO="${ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${CANDIDATE_FILES_VETTED_DIR}/${ORG_AND_REPO}"

                # Set the files to move
                FILES_TO_MOVE="${JSON_FILE_NAME}"
            fi
        else
            echo "Should not be running move files fo type of pipeline $PIPELINE_TYPE and template type $PIPELINE_TEMPLATE_TYPE"
            echo "Exiting with error !!!"
            exit 1
        fi
    fi

    # Iterate and move
    for ftm in ${FILES_TO_MOVE}
    do
        FROM="${BASE_PATH_TO_MOVE_FROM}/${ftm}"
        TO="${BASE_PATH_TO_MOVE_TO}/${ftm}"

        if [[ $MOVE_FILES_DRY_RUN = true ]]; then
            echo "DRY RUN MODE !!! - We would have moved from ${FROM} to ${TO}"
        else
            # For uuc-ci, check if source file exists before attempting to move
            if [[ "${PIPELINE_TEMPLATE_TYPE}" == "uuc-ci" ]] && [[ "${ftm}" == *".zip" ]]
            then
                echo "Checking if source ZIP file exists for uuc-ci..."
                if file_exists_in_artifactory ${CC_ARTIF_ACCESS_TOKEN} ${ARTIFACTORY_BASE_URL} ${FROM}
                then
                    echo "Source file ${FROM} exists in ${ARTIFACTORY_BASE_URL}; proceeding to move"
                    move_in_artifactory ${CC_ARTIF_ACCESS_TOKEN} ${ARTIFACTORY_BASE_URL} ${FROM} ${TO}
                else
                    echo "Source file ${FROM} does not exist in ${ARTIFACTORY_BASE_URL}; skipping move for this file"
                fi
            elif [[ "${CHECK_IF_FILE_EXISTS_BEFORE_MOVING}" == "true" ]]
            then
                if file_exists_in_artifactory ${CC_ARTIF_ACCESS_TOKEN} ${ARTIFACTORY_BASE_URL} ${TO}
                then
                    echo "File ${TO} already exists in ${ARTIFACTORY_BASE_URL}; no need to move"
                else
                    echo "File ${TO} does not exist in ${ARTIFACTORY_BASE_URL}; so we proceed to move from ${FROM} to ${TO}"
                    move_in_artifactory ${CC_ARTIF_ACCESS_TOKEN} ${ARTIFACTORY_BASE_URL} ${FROM} ${TO}
                fi
            else
                echo "Moving without checking if it exists first..."
                move_in_artifactory ${CC_ARTIF_ACCESS_TOKEN} ${ARTIFACTORY_BASE_URL} ${FROM} ${TO}
            fi
        fi
    done

    ### PACKAGES ###
    if [[ "${MOVE_FILES_SKIP_MOVE_PACKAGES}" == "false" ]]
    then
        if [[ "${PIPELINE_TEMPLATE_TYPE}" == "razee" ]]
        then
            if [ "$PIPELINE_TYPE" = "dev-integration-merge" ]
            then
                echo "This is a razee merge to dev-integration pipeline, will move packages from pre-release to vetted"

                ${PATH_TO_GENCTL_CI}/scripts/process_build_meta_new/process_build_meta_packages_new.sh "move_from_pre_release_to_vetted"
            elif [ "$PIPELINE_TYPE" = "merge" ]
            then
                if [[ "${SKIP_MOVE_PACKAGES_FROM_VETTED_TO_FINAL_DESTINATION}" == "true" ]] 
                then 
                    echo "Skipping moving packages from vetted to final destination..."
                else
                    echo "This is a razee merge to master pipeline, will move packages from vetted to its final location"

                    # Since we are in a merge to master razee pipeline, we need to find the packages with the dev-int SHA
                    # At this point, the dev-int SHA should be in RESULT_DEV_INT_SHA, so we export it for the process_build_meta code to prefer it
                    export SHA_TO_USE_FOR_SEARCH_PACKAGES=${RESULT_DEV_INT_SHA}

                    ${PATH_TO_GENCTL_CI}/scripts/process_build_meta_new/process_build_meta_packages_new.sh "move_from_vetted_to_final_destination"
                fi
            else
                echo "Pipeline type $PIPELINE_TYPE not recognized, exiting with error !!!"
                exit 1
            fi
        else
            if [[ "${SKIP_MOVE_PACKAGES_FROM_VETTED_TO_FINAL_DESTINATION}" == "true" ]] && [[ "${MOVE_FILES_MODE}" == "move_from_vetted_to_final_destination" ]]
            then 
                echo "Skipping moving packages from vetted to final destination..."
            else
                ${PATH_TO_GENCTL_CI}/scripts/process_build_meta_new/process_build_meta_packages_new.sh "${MOVE_FILES_MODE}"
            fi
        fi
    else
        echo "Won't move packages..."
    fi
else
    echo "Mode ${MOVE_FILES_MODE} is not supported..."
    echo "Will exit with error !!!"
    exit 1
fi
