#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Source lock utils
source ${PATH_TO_GENCTL_CI}/tools/lock_and_queue_utils/lock.sh

# Source tekton api utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/tekton_api_utils.sh

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="razee"

export PIPELINE_TYPE="pr"

# Define the repositories to be cloned
REPOS_TO_CLONE="
RESOURCELOCK
INTEGRATION_TESTING
GENCTL_GLOBALS
RIAS_GLOBALS
DEV_REGIONS
RIAS_ETCD_RELEASE
"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Clone required repos
clone_repos_from_env_vars "${IBM_HTTPS_BASE_URL}" "${WORKSPACE}" "${REPOS_TO_CLONE}" 

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_RESOURCELOCK_REPO="${WORKSPACE}/${RESOURCELOCK_REPO_NAME}"
export PATH_TO_INTEGRATION_TESTING_REPO="${WORKSPACE}/${INTEGRATION_TESTING_REPO_NAME}"
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_RIAS_ETCD_RELEASE_REPO="${WORKSPACE}/${RIAS_ETCD_RELEASE_REPO_NAME}"
export PATH_TO_GENCTL_GLOBALS_REPO="${WORKSPACE}/${GENCTL_GLOBALS_REPO_NAME}"
export PATH_TO_DEV_REGIONS_REPO="${WORKSPACE}/${DEV_REGIONS_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Configuration required for working with the git remote (Needed for release lock)
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

function ensure(){
    # This function does what is needed to "tear-down" the run of the dynamic scan
    # It receives arguments used to release the lock
    COS_FFSLD_STTAUS=${1}
    ALR=${2} # The name of the lock acquired
    B_P=${3} # The path to the lock directory
    LCM=${4} # String used for git commit when releasing
    ATT=${5} # Max attempts to release lock
    SLP=${6} # Sleep time between attempts for lock release

    if [[ ${COS_FFSLD_STTAUS} == false ]]
    then
        ### Scale up ###
        export FF_SETLD_REPLICAS=${RAZEE_FF_SETLD_REPLICAS_MAX}
        ${PATH_TO_GENCTL_CI}/scripts/scale_ffsld_controller.sh

        if [[ $? -eq 0 ]] ; then
            ### Roll to dev-integration ###
            ${PATH_TO_GENCTL_CI}/scripts/rollback_environment_to_dev_integration.sh
        fi

        # If needed, release lock
        release_lock_if_acquired ${ALR} ${B_P} "${LCM}" ${ATT} ${SLP}
    else
        echo "cos enablement status is : ${COS_FFSLD_STTAUS}"
        echo "trapped for ensure with executed code: ${EXIT_CODE}"
        echo "Proceeding to reconnect cos remote resource"
        
        if [[ "${USE_QZ2_WORKER}" == true ]]; then
            # Source tekton api utils
            source ${PATH_TO_GENCTL_CI}/onepipeline/utils/tekton_api_utils.sh
            
            # Set few variables
            MAX_ATTEMPTS_BUSY_WAIT=${MAX_ATTEMPTS_BUSY_WAIT:-960}
            SLEEP_TIME_BUSY_WAIT=${SLEEP_TIME_BUSY_WAIT:-30}
            ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)
            BASE_URL="api.${ENDPOINT}.devops.cloud.ibm.com"

            CURRENT_PIPELINE_RUNS=$(get_data pending-tasks)

            FORMATTED_PIPELINES=""
            COUNTER=1
            for pipeline_id in ${CURRENT_PIPELINE_RUNS}; do
                # Remove "async-" prefix if present
                clean_id=${pipeline_id#"async-"}
                # Add to formatted string with genctl-env-N prefix
                if [ -z "${FORMATTED_PIPELINES}" ]; then
                    FORMATTED_PIPELINES="genctl-env-${COUNTER}/${clean_id}"
                else
                    FORMATTED_PIPELINES="${FORMATTED_PIPELINES} genctl-env-${COUNTER}/${clean_id}"
                fi
                COUNTER=$((COUNTER + 1))
            done

            # Update the variable with the formatted version
            GENCTL_CLEANUP_PIPELINES="${FORMATTED_PIPELINES}"

            echo "Formatted pipeline IDs: ${GENCTL_CLEANUP_PIPELINES}"

            #track_for_completion
            wait_until_all_pipeline_runs_finish "${BASE_URL}" \
            "${PIPELINE_ID}" "${GENCTL_CLEANUP_PIPELINES}" \
            "${MAX_ATTEMPTS_BUSY_WAIT}" "${SLEEP_TIME_BUSY_WAIT}"
        fi

        ${PATH_TO_GENCTL_CI}/scripts/reconnect_cos_remote_resource.sh

        # If needed, release lock
        release_lock_if_acquired ${ALR} ${B_P} "${LCM}" ${ATT} ${SLP}
    fi
}

# Set exit on task
export EXIT_ON_TASK_FAILURE="true"

# We assume that the lock we acquired is the one defined in the pipeline.yaml
export PARENT_PIPELINE_ACQUIRE_LOCK_RESULT="${BRT_ENVIRONMENT_NAME}"

# We get from the parent pipeline the claimed msg, this is used to release the lock
export PARENT_PIPELINE_LOCK_CLAIMED_MSG=$(get_env ci_parent_pipeline_lock_claimed_msg)

source ${PATH_TO_GENCTL_CI}/onepipeline/jobs/evaluate_status_of_cos_ffsld.sh

# In the ensure function we could just access them as they are environment variables, but we prefer pass them to make this little bit safer...
trap 'ensure ${COS_FFSLD_ENABLED} ${PARENT_PIPELINE_ACQUIRE_LOCK_RESULT} ${PATH_TO_BRT} "${PARENT_PIPELINE_LOCK_CLAIMED_MSG}" 360 10' EXIT

#trigger separete dynamic scan pipelines

PIPELINE_YAML_FILE="${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml"

# # This is required because since at this point pipeline_namespace is still PR; OnePipeline does not create the asset for us
# # We need to explicitly create the asset
# merge_to_dev_int_pipeline_id=$(get_env root_pipeline_id) # This is actually the pipeline_id of the merge to dev-integration
# merge_to_dev_int_pipeline_run_id=$(get_env root_pipeline_run_id) # This is actually the pipeline_run_id of the merge to dev-integration
# pipeline_run_str="pipelinerun://${merge_to_dev_int_pipeline_id}/${merge_to_dev_int_pipeline_run_id}" # This is the format that create_pipeline_asset uses

# echo "We will explicitly call create_pipeline_asset with the following parameter:"
# echo ${pipeline_run_str}

# # Temporary fix for evidence issues
# source "${ONE_PIPELINE_PATH}/tools/pipeline_utils"
# init_cos_env

# source "${ONE_PIPELINE_PATH}/internal/pipeline/create_pipeline_asset"
# create_pipeline_asset "${pipeline_run_str}"

# # Setting the pipeline_namespace property to ci 
# set_env pipeline_namespace ci

echo -e "${BYellow}Dynamic scan starts at: $(date)............. ${NC}"
START=$(date +%s)

export CURRENT_PIPELINE_RUN_ID=${PIPELINE_RUN_ID}


# Actual execution of dynamic scan
if yq -e '.dynamic_scan[0].category' "${PIPELINE_YAML_FILE}" > /dev/null 2>&1; then
    echo "New config detected"
    mapfile -t API_CATEGORY_NAMES < <(yq -r '.dynamic_scan[].category' "$PIPELINE_YAML_FILE")
    mapfile -t API_FILE_NAMES     < <(yq -r '.dynamic_scan[].api_file_name' "$PIPELINE_YAML_FILE")
    mapfile -t API_PROFILES       < <(yq -r '.dynamic_scan[].profiles | join(",")' "$PIPELINE_YAML_FILE")
    ENDPOINTS_TYPE=$(yq -r '.dynamic_scan[0].endpoints | type' "$PIPELINE_YAML_FILE")
    
    if [[ "$ENDPOINTS_TYPE" == "array" ]]; then
        # Check if first element is an object
        FIRST_ELEM_TYPE=$(yq -r '.dynamic_scan[0].endpoints[0] | type' "$PIPELINE_YAML_FILE")
        if [[ "$FIRST_ELEM_TYPE" == "object" ]]; then
            mapfile -t API_ENDPOINTS < <(yq -r '.dynamic_scan[].endpoints | tojson' "$PIPELINE_YAML_FILE")
        else
            mapfile -t API_ENDPOINTS < <(yq -r '.dynamic_scan[].endpoints | join(",")' "$PIPELINE_YAML_FILE")
        fi
    else
        mapfile -t API_ENDPOINTS < <(yq -r '.dynamic_scan[].endpoints' "$PIPELINE_YAML_FILE")
    fi
    mapfile -t API_EXCLUDE_ENTRIES < <(yq -r '.dynamic_scan[].exclude_entries // [] | tojson' "$PIPELINE_YAML_FILE")

    check-evidence-for-reuse --tool-type "owasp-zap" \
    --evidence-type "com.ibm.dynamic_scan" \
    --asset-type "artifact" \
    --asset-key "app-image" 

    if [[ $? -eq 0 ]]
    then
        echo "Will re-use evidence, no need to run UT"
    else 
        echo "No evidence found for reuse, executing dynamic scan"
        
        # Initialize associative array to track captured task IDs
        declare -A CAPTURED_TASK_IDS_MAP
        
        for i in "${!API_CATEGORY_NAMES[@]}"; do
            echo "Entry ${i}"
            echo "Category: ${API_CATEGORY_NAMES[$i]}"
            echo "API File: ${API_FILE_NAMES[$i]}"
            echo "Profiles: ${API_PROFILES[$i]}"
            echo "Endpoints: ${API_ENDPOINTS[$i]}"
            echo "Exclude Entries: ${API_EXCLUDE_ENTRIES[$i]}"

            CATEGORY="${API_CATEGORY_NAMES[$i]}"
            VAR_NAME="${CATEGORY}_SUBPIPELINE_ID"

            export DYNAMIC_SCAN_STAGE_NAME=${DYNAMIC_SCAN_STAGE_NAME:-"categorical-dynamic-scan-as-subpipeline"}
            export DYNAMIC_SCAN_TRIGGER_TO_USE=${DYNAMIC_SCAN_TRIGGER_TO_USE:-"taas-worker-trigger"}
            export WAIT_FOR_FINISH="false"

            export CATEGORY_NAME="${API_CATEGORY_NAMES[$i]}"
            export FILE_NAME="${API_FILE_NAMES[$i]}"
            export PROFILES="${API_PROFILES[$i]}"
            export ENDPOINTS="${API_ENDPOINTS[$i]}"
            EXCLUDE_VAL="${API_EXCLUDE_ENTRIES[$i]:-[]}"
            if [[ "$EXCLUDE_VAL" != "[]" ]]; then
                export EXCLUDE_ENTRIES="$EXCLUDE_VAL"
            else
                export EXCLUDE_ENTRIES="[]"
            fi
            export MAX_ATTEMPTS_BUSY_WAIT=1200
            CUSTOM_SUB_PIPELINE_CONFIG="onepipeline/pipelines/templatized/razee/pr_and_ci_master_v11/.pipeline-config-subpipeline-configurations.yaml"

            ${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_for_ds.sh ${DYNAMIC_SCAN_STAGE_NAME} ${DYNAMIC_SCAN_TRIGGER_TO_USE} ${WAIT_FOR_FINISH} ${CATEGORY_NAME} ${FILE_NAME} ${PROFILES} ${ENDPOINTS} ${CUSTOM_SUB_PIPELINE_CONFIG} "${EXCLUDE_ENTRIES}"
            
            # Enhanced task ID extraction with retry logic and proper tracking
            MAX_TASK_FETCH_RETRIES=3
            TASK_FETCH_RETRY_DELAY=10
            TASK_ID_CAPTURED=""
            
            for attempt in $(seq 1 $MAX_TASK_FETCH_RETRIES); do
                echo "Attempt $attempt: Fetching pending tasks for category ${CATEGORY}..."
                sleep $TASK_FETCH_RETRY_DELAY
                
                # Get space-separated task IDs from get_data
                CURRENT_TASKS_RAW=$(get_data pending-tasks 2>/dev/null || echo "")
                
                # Debug: Show what we got
                echo "Raw output from get_data: '$CURRENT_TASKS_RAW'"
                
                # Filter out only lines that contain async- task IDs
                CURRENT_TASKS_FILTERED=$(echo "$CURRENT_TASKS_RAW" | grep -oE 'async-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | tr '\n' ' ')
                
                echo "Filtered task IDs: '$CURRENT_TASKS_FILTERED'"
                echo "Already captured: ${!CAPTURED_TASK_IDS_MAP[@]}"
                
                # Convert space-separated to array for easier processing
                read -ra CURRENT_TASKS_ARRAY <<< "$CURRENT_TASKS_FILTERED"
                
                # Find a new task ID that hasn't been captured yet
                for task_id in "${CURRENT_TASKS_ARRAY[@]}"; do
                    # Skip empty strings
                    [[ -z "$task_id" ]] && continue
                    
                    # Validate task ID format (async- prefix with UUID)
                    if [[ "$task_id" =~ ^async-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]]; then
                        # Check if this task_id has already been captured
                        if [[ -z "${CAPTURED_TASK_IDS_MAP[$task_id]}" ]]; then
                            TASK_ID_CAPTURED="$task_id"
                            # Mark this task ID as captured
                            CAPTURED_TASK_IDS_MAP[$task_id]=1
                            echo "Successfully captured task ID: $TASK_ID_CAPTURED for category: ${CATEGORY}"
                            echo "Total captured task IDs so far: ${#CAPTURED_TASK_IDS_MAP[@]}"
                            break 2  # Break out of both loops
                        fi
                    fi
                done
                
                # If we didn't find a new task ID, check if we should retry
                if [[ -z "$TASK_ID_CAPTURED" ]]; then
                    echo "Attempt $attempt: No new task ID found yet (already captured: ${#CAPTURED_TASK_IDS_MAP[@]} tasks)..."
                    if [[ $attempt -eq $MAX_TASK_FETCH_RETRIES ]]; then
                        echo "Error: Failed to capture valid task ID for category ${CATEGORY} after $MAX_TASK_FETCH_RETRIES attempts"
                        echo "Raw output: '$CURRENT_TASKS_RAW'"
                        echo "Filtered task IDs: '$CURRENT_TASKS_FILTERED'"
                        echo "Already captured task IDs: ${!CAPTURED_TASK_IDS_MAP[@]}"
                        exit 1
                    fi
                fi
            done
            
            # Export the captured task ID for this category
            export "$VAR_NAME=$TASK_ID_CAPTURED"
            echo "$VAR_NAME=${!VAR_NAME}"
        done
        
        echo "CURRENT_TASKS_RAW_NEW"
        CURRENT_TASKS_RAW_NEW=$(get_data pending-tasks)
        echo $CURRENT_TASKS_RAW_NEW

        # By now, pass if NG passes
        ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)
        BASE_URL="api.${ENDPOINT}.devops.cloud.ibm.com"
        SLEEP_TIME_BUSY_WAIT=${SLEEP_TIME_BUSY_WAIT:-30}

        RESULT=()

        echo "Building pipeline mapping from captured task IDs..."
        for i in "${API_CATEGORY_NAMES[@]}"; do
            KEY="${i}_SUBPIPELINE_ID"
            VAL="${!KEY}"
            
            # Remove any whitespace
            VAL="$(printf "%s" "$VAL" | tr -d '[:space:]')"
            
            # Validate the value exists
            if [[ -z "$VAL" ]]; then
                echo "Error: environment variable '$KEY' is empty or whitespace." >&2
                exit 1
            fi
            
            # Strip the 'async-' prefix to get just the UUID
            VAL="${VAL#async-}"
            
            # Validate UUID format after stripping prefix
            if [[ ! "$VAL" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]]; then
                echo "Error: Invalid UUID format for '$KEY': $VAL" >&2
                exit 1
            fi
            
            # Build category/uuid pair
            RESULT+=("${i}/${VAL}")
            echo "Added mapping: ${i}/${VAL}"
        done

        # Create space-separated pipeline mapping string
        export PIPELINE_MAPPING="$(printf "%s " "${RESULT[@]}" | sed 's/ $//')"
        echo "Pipeline mapping before build_pipeline_mapping: $PIPELINE_MAPPING"

        wait_until_all_pipeline_runs_finish "${BASE_URL}" \
        "${PIPELINE_ID}" "${PIPELINE_MAPPING}" \
        "${MAX_ATTEMPTS_BUSY_WAIT}" "${SLEEP_TIME_BUSY_WAIT}"

        DOWNLOAD_DIR="dynamic-scan-evidences-local"
        mkdir -p "$DOWNLOAD_DIR"
    
        # Get parent pipeline information
        get_parent_pipeline_info
        echo "PIPELINE_RUN_ID after get_parent_pipeline_info"
        echo $PIPELINE_RUN_ID

        echo $CURRENT_PIPELINE_RUN_ID

        COS_PREFIX="dynamic-scan-evidences/$CURRENT_PIPELINE_RUN_ID/"

        # Download scan results from COS
        ${PATH_TO_GENCTL_CI}/scripts/generic_cos_operations/generic_cos_wrapper.sh download $COS_PREFIX ./$DOWNLOAD_DIR

        # Build collect-evidence command with all attachments
        COLLECT_CMD=(
        collect-evidence
        --tool-type "owasp-zap"
        --evidence-type "com.ibm.dynamic_scan"
        --asset-key "app-image"
        --asset-type "artifact"
        --status "success"
        )

        # Add each downloaded file as an attachment
        while IFS= read -r -d '' attachment_file; do
            COLLECT_CMD+=(--attachment "$attachment_file")
            echo "Adding attachment: $attachment_file"
        done < <(find "${DOWNLOAD_DIR}" -type f -print0)

        # Print as a single command string
        echo "Executing command: ${COLLECT_CMD[*]}"

        # Execute the command
        "${COLLECT_CMD[@]}"

    fi
else
    echo "Old config detected (dynamic_scan.endpoints exists)"
    run_task "false" ${CHECKS_PREFIX} "DYNAMIC_SCAN" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/zap/trigger_zap_scans.sh

    # # Bring back the pipeline_namespace property to its original value
    # set_env pipeline_namespace pr
fi

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Dynamic scan ends at: $(date)............. ${NC}"
echo -e "${BYellow}Dynamic scan took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete............. ${NC}"