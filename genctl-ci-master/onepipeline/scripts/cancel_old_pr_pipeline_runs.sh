#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script cancels old pipeline runs for the same PR to save infrastructure resources
# It will:
# 1. Cancel previously running pipelines (not cancelled or successful)
# 2. If 2 pipelines triggered on same commit of the PR, cancel the older one
# 3. Only cancel pipelines for the same PR
# 4. Cancel any subpipelines triggered by the cancelled parent pipeline runs

# The following environment variables need to be set before executing the script:
# PIPELINE_ID - Current pipeline ID
# PIPELINE_RUN_ID - Current pipeline run ID
# PIPELINE_RUN_URL - Current pipeline run URL
# GIT_COMMIT - Current commit SHA (from trigger)
# PR_NUMBER - Pull request number (from trigger)

set -e

# Source IAM utils for authentication
source "${PATH_TO_GENCTL_CI}/onepipeline/utils/iam_utils.sh"

# Ensure SSH is configured for git operations
if [[ -n "${GIT_PRIVATE_KEY}" ]]; then
    echo "Configuring SSH for git operations..."
    eval "$(ssh-agent -s)" >/dev/null 2>&1
    ssh-add - <<< "${GIT_PRIVATE_KEY}" 2>/dev/null || echo "Warning: Could not add SSH key"
    ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts 2>/dev/null || true
fi

# Extract the endpoint from PIPELINE_RUN_URL
ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)
# Function to get commit timestamp from GitHub API
get_commit_timestamp() {
    local COMMIT_SHA="$1"
    
    # Get org/repo from environment variables (set by pipeline)
    local ORG_REPO="${REPOSITORY_NAME:-${ORG_AND_REPO}}"
    
    # Fallback: Extract from git remote URL
    if [[ -z "${ORG_REPO}" ]]; then
        local REPO_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
        if [[ -n "${REPO_URL}" ]]; then
            ORG_REPO=$(echo "${REPO_URL}" | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#')
        fi
    fi
    
    # Fallback: Use GIT_ORG and GIT_REPO if available
    if [[ -z "${ORG_REPO}" ]] && [[ -n "${GIT_ORG}" ]] && [[ -n "${GIT_REPO}" ]]; then
        ORG_REPO="${GIT_ORG}/${GIT_REPO}"
    fi
    
    if [[ -z "${ORG_REPO}" ]]; then
        echo "  → Warning: Could not determine repository org/name" >&2
        echo "0"
        return 1
    fi
    
    echo "  → Fetching commit ${COMMIT_SHA:0:8} from ${ORG_REPO}..." >&2
    
    # Get commit details from GitHub API
    local COMMIT_DATE=$(curl -s \
        --header "Authorization: token ${GH_TOKEN}" \
        --header "Accept: application/vnd.github.v3+json" \
        "https://github.ibm.com/api/v3/repos/${ORG_REPO}/commits/${COMMIT_SHA}" \
        | jq -r '.commit.committer.date // .commit.author.date // empty' 2>/dev/null)
    
    if [[ -n "${COMMIT_DATE}" ]] && [[ "${COMMIT_DATE}" != "null" ]]; then
        # Convert ISO 8601 date to Unix timestamp
        # Handle both formats: 2026-04-15T14:57:53Z and 2026-04-15T14:57:53.123Z
        local DATE_CLEAN=$(echo "${COMMIT_DATE}" | sed 's/\.[0-9]*Z$/Z/' | sed 's/Z$//')
        
        # Try different date parsing methods (macOS vs Linux)
        local COMMIT_TS=0
        if date --version >/dev/null 2>&1; then
            # GNU date (Linux)
            COMMIT_TS=$(date -d "${COMMIT_DATE}" "+%s" 2>/dev/null || echo "0")
        else
            # BSD date (macOS)
            COMMIT_TS=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${DATE_CLEAN}" "+%s" 2>/dev/null || echo "0")
        fi
        
        echo "  → Commit timestamp: ${COMMIT_TS} (${COMMIT_DATE})" >&2
        
        if [[ "${COMMIT_TS}" != "0" ]] && [[ ${COMMIT_TS} -gt 0 ]]; then
            echo "${COMMIT_TS}"
            return 0
        else
            echo "  → Warning: Failed to parse commit date" >&2
            echo "0"
            return 1
        fi
    else
        echo "  → Warning: Could not get commit date from API" >&2
        echo "0"
        return 1
    fi
}

# Function to cancel a pipeline run
cancel_pipeline_run() {
    local RUN_ID_TO_CANCEL="$1"
    local COUNTER_FILE_PATH="$2"
    
    echo "Cancelling pipeline run: ${RUN_ID_TO_CANCEL}"
    CANCEL_RESPONSE=$(curl -s -X POST \
        --location \
        --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" \
        --header "Accept: application/json" \
        "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${RUN_ID_TO_CANCEL}/cancel")
    
    if echo "${CANCEL_RESPONSE}" | jq -e '.status' > /dev/null 2>&1; then
        CANCEL_STATUS=$(echo "${CANCEL_RESPONSE}" | jq -r '.status')
        echo "Pipeline cancellation initiated. New status: ${CANCEL_STATUS}"
        
        # Increment counter if counter file is provided
        if [[ -n "${COUNTER_FILE_PATH}" ]] && [[ -f "${COUNTER_FILE_PATH}" ]]; then
            CURRENT_COUNT=$(cat "${COUNTER_FILE_PATH}")
            echo "$((CURRENT_COUNT + 1))" > "${COUNTER_FILE_PATH}"
        fi
        
        return 0
    else
        echo "Warning: Failed to cancel pipeline run ${RUN_ID_TO_CANCEL}"
        echo "Response: ${CANCEL_RESPONSE}"
        return 1
    fi
}

BASE_URL="api.${ENDPOINT}.devops.cloud.ibm.com"

echo "=========================================="
echo "Checking for old pipeline runs to cancel"
echo "=========================================="
echo "Current Pipeline ID: ${PIPELINE_ID}"
echo "Current Pipeline Run ID: ${PIPELINE_RUN_ID}"
echo "Current PR Number: ${PR_NUMBER}"

# Check if we have PR_NUMBER, if not, skip cancellation
if [[ -z "${PR_NUMBER}" ]]; then
    echo "No PR_NUMBER found. This might not be a PR pipeline. Skipping cancellation check."
    exit 0
fi

# If GIT_COMMIT is not set, try to get it from trigger properties or PR_HEADSHA
if [[ -z "${GIT_COMMIT}" ]]; then
    echo "GIT_COMMIT not set, attempting to fetch from current pipeline run..."
    CURRENT_RUN_DETAILS=$(curl -s -X GET \
        --location \
        --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" \
        --header "Accept: application/json" \
        "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${PIPELINE_RUN_ID}")
    
    # Try to get from event_params_blob first
    CURRENT_EVENT_PARAMS=$(echo "${CURRENT_RUN_DETAILS}" | jq -r '.event_params_blob' 2>/dev/null)
    if [[ -n "${CURRENT_EVENT_PARAMS}" ]] && [[ "${CURRENT_EVENT_PARAMS}" != "null" ]]; then
        GIT_COMMIT=$(echo "${CURRENT_EVENT_PARAMS}" | jq -r '.pull_request.head.sha // .head.sha' 2>/dev/null)
        CURRENT_COMMIT_TIMESTAMP=$(echo "${CURRENT_EVENT_PARAMS}" | jq -r '.pull_request.updated_at // .updated_at' 2>/dev/null)
    fi
    
    # Get the current pipeline run's created timestamp
    PIPELINE_RUN_CREATED_AT=$(echo "${CURRENT_RUN_DETAILS}" | jq -r '.created_at' 2>/dev/null)
    
    # If still not found, try trigger properties
    if [[ -z "${GIT_COMMIT}" ]] || [[ "${GIT_COMMIT}" == "null" ]]; then
        GIT_COMMIT=$(echo "${CURRENT_RUN_DETAILS}" | jq -r '.trigger.properties[]? | select(.name=="commit" or .name=="GIT_COMMIT" or .name=="git-commit" or .name=="PR_HEADSHA" or .name=="pr-headsha") | .value' 2>/dev/null | head -n1)
    fi
    
    # If still not found, try using PR_HEADSHA environment variable
    if [[ -z "${GIT_COMMIT}" ]] || [[ "${GIT_COMMIT}" == "null" ]]; then
        if [[ -n "${PR_HEADSHA}" ]]; then
            GIT_COMMIT="${PR_HEADSHA}"
            echo "Using PR_HEADSHA as GIT_COMMIT: ${GIT_COMMIT}"
        else
            echo "Warning: Could not determine GIT_COMMIT or PR_HEADSHA. Will only cancel runs with different commits."
            GIT_COMMIT="unknown"
        fi
    else
        echo "Fetched GIT_COMMIT: ${GIT_COMMIT}"
    fi
else
    # Get commit timestamp for current run from environment or fetch it
    if [[ -z "${CURRENT_COMMIT_TIMESTAMP}" ]]; then
        CURRENT_RUN_DETAILS=$(curl -s -X GET \
            --location \
            --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" \
            --header "Accept: application/json" \
            "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${PIPELINE_RUN_ID}")
        
        CURRENT_EVENT_PARAMS=$(echo "${CURRENT_RUN_DETAILS}" | jq -r '.event_params_blob' 2>/dev/null)
        if [[ -n "${CURRENT_EVENT_PARAMS}" ]] && [[ "${CURRENT_EVENT_PARAMS}" != "null" ]]; then
            CURRENT_COMMIT_TIMESTAMP=$(echo "${CURRENT_EVENT_PARAMS}" | jq -r '.pull_request.updated_at // .updated_at' 2>/dev/null)
        fi
    fi
fi

# Now display the commit after we've determined it
echo "Current Commit: ${GIT_COMMIT}"
echo "=========================================="

# Get all pipeline runs for this pipeline
echo "Fetching all pipeline runs for pipeline ${PIPELINE_ID}..."
PIPELINE_RUNS=$(curl -s -X GET \
    --location \
    --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" \
    --header "Accept: application/json" \
    "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs?limit=100")

# Check if the API call was successful
if [[ -z "${PIPELINE_RUNS}" ]] || [[ "${PIPELINE_RUNS}" == "null" ]]; then
    echo "Failed to fetch pipeline runs or no runs found."
    exit 0
fi

# Extract pipeline runs that match our criteria for cancellation
echo "Analyzing pipeline runs..."

# Counter for cancelled runs (use temp file to persist across subshell)
COUNTER_FILE=$(mktemp)
echo "0" > "${COUNTER_FILE}"

# Process each pipeline run
while read -r run; do
    RUN_ID=$(echo "${run}" | jq -r '.id')
    RUN_STATUS=$(echo "${run}" | jq -r '.status')
    RUN_CREATED_AT=$(echo "${run}" | jq -r '.created_at')
    
    echo "Evaluating run: ${RUN_ID} (status: ${RUN_STATUS})"
    
    # Skip if this is the current run
    if [[ "${RUN_ID}" == "${PIPELINE_RUN_ID}" ]]; then
        echo "  → Skipping current run: ${RUN_ID}"
        continue
    fi
    
    # Only process runs that are in running or pending state
    if [[ "${RUN_STATUS}" != "running" ]] && [[ "${RUN_STATUS}" != "pending" ]] && [[ "${RUN_STATUS}" != "waiting" ]] && [[ "${RUN_STATUS}" != "queued" ]]; then
        echo "  → Skipping run with status: ${RUN_STATUS}"
        continue
    fi
    
    # Get full run details including event_params_blob
    RUN_DETAILS=$(curl -s -X GET \
        --location \
        --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" \
        --header "Accept: application/json" \
        "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${RUN_ID}")
    
    # Extract PR number, commit, and commit timestamp from event_params_blob
    EVENT_PARAMS=$(echo "${RUN_DETAILS}" | jq -r '.event_params_blob' 2>/dev/null)
    
    if [[ -n "${EVENT_PARAMS}" ]] && [[ "${EVENT_PARAMS}" != "null" ]]; then
        # First, try to get PR info from pipelinectl array (works for both parent and subpipelines)
        RUN_PR_NUMBER=$(echo "${EVENT_PARAMS}" | jq -r '
            try (
                .pipelinectl[]? |
                select(.name=="cocoa.string.pr_id") |
                .props[0].value |
                @base64d
            ) catch null' 2>/dev/null)
        
        # If not found in pipelinectl, try webhook payload (for parent runs)
        if [[ -z "${RUN_PR_NUMBER}" ]] || [[ "${RUN_PR_NUMBER}" == "null" ]]; then
            RUN_PR_NUMBER=$(echo "${EVENT_PARAMS}" | jq -r '.number // .pull_request.number' 2>/dev/null)
            # Treat "null" string as empty
            [[ "${RUN_PR_NUMBER}" == "null" ]] && RUN_PR_NUMBER=""
        fi
        
        # Get commit SHA from webhook payload (only available for parent runs)
        RUN_COMMIT=$(echo "${EVENT_PARAMS}" | jq -r '.pull_request.head.sha // .head.sha' 2>/dev/null)
        # Treat "null" string as empty
        [[ "${RUN_COMMIT}" == "null" ]] && RUN_COMMIT=""
        
        RUN_COMMIT_TIMESTAMP=$(echo "${EVENT_PARAMS}" | jq -r '.pull_request.updated_at // .updated_at' 2>/dev/null)
        [[ "${RUN_COMMIT_TIMESTAMP}" == "null" ]] && RUN_COMMIT_TIMESTAMP=""
    else
        # Fallback: try trigger properties (for older runs or different trigger types)
        RUN_PR_NUMBER=$(echo "${RUN_DETAILS}" | jq -r '.trigger.properties[]? | select(.name=="pr-number" or .name=="PR_NUMBER" or .name=="pr_number") | .value' 2>/dev/null | head -n1)
        RUN_COMMIT=$(echo "${RUN_DETAILS}" | jq -r '.trigger.properties[]? | select(.name=="commit" or .name=="GIT_COMMIT" or .name=="PR_HEADSHA") | .value' 2>/dev/null | head -n1)
        RUN_COMMIT_TIMESTAMP=""
    fi
    
    # Check if this is a subpipeline and adjust logging
    RUN_EVENT_LISTENER=$(echo "${RUN_DETAILS}" | jq -r '.trigger.event_listener // "unknown"')
    
    # Show PR and commit info (commit will be null for subpipelines)
    echo "  → Run PR: ${RUN_PR_NUMBER}, Run Commit: ${RUN_COMMIT:0:8}"
    
    # Add subpipeline identifier if applicable
    if [[ "${RUN_EVENT_LISTENER}" == "async-stage-listener" ]]; then
        echo "  → Type: Subpipeline (async-stage-listener) - inherits parent's PR/commit context"
    fi
    
    # Check if this run is for the same PR
    if [[ "${RUN_PR_NUMBER}" == "${PR_NUMBER}" ]]; then
        echo "  → Same PR detected (PR #${PR_NUMBER})"
        SHOULD_CANCEL=false
        CANCEL_REASON=""
        
        # Case 1: Different commit - determine which is newer using git
        if [[ -n "${RUN_COMMIT}" ]] && [[ -n "${GIT_COMMIT}" ]] && [[ "${RUN_COMMIT}" != "${GIT_COMMIT}" ]] && [[ "${GIT_COMMIT}" != "unknown" ]]; then
            # Use git to determine which commit is newer (ancestor check)
            # If RUN_COMMIT is an ancestor of GIT_COMMIT, then GIT_COMMIT is newer
            echo "  → Checking commit ancestry to determine which is newer..."
            
            # Fetch the commits from remote to ensure they're available locally
            echo "  → Fetching commits from remote..."
            # Try multiple fetch strategies
            if ! git fetch --depth=50 origin "+refs/pull/${PR_NUMBER}/head:refs/remotes/origin/pr/${PR_NUMBER}" 2>/dev/null; then
                echo "  → Could not fetch PR branch, trying individual commits..."
                git fetch origin "${RUN_COMMIT}" 2>/dev/null || true
                git fetch origin "${GIT_COMMIT}" 2>/dev/null || true
            fi
            
            # Verify commits are available
            if ! git cat-file -e "${RUN_COMMIT}" 2>/dev/null || ! git cat-file -e "${GIT_COMMIT}" 2>/dev/null; then
                echo "  → Warning: One or both commits not available locally after fetch"
            fi
            
            # Check if RUN_COMMIT is an ancestor of GIT_COMMIT
            if git merge-base --is-ancestor "${RUN_COMMIT}" "${GIT_COMMIT}" 2>/dev/null; then
                # RUN_COMMIT is ancestor of GIT_COMMIT, so GIT_COMMIT is newer
                # Cancel the run with older commit
                SHOULD_CANCEL=true
                CANCEL_REASON="Older commit (Run: ${RUN_COMMIT:0:8}, Current: ${GIT_COMMIT:0:8})"
                echo "  → Will cancel: Run has older commit (${RUN_COMMIT:0:8} is ancestor of ${GIT_COMMIT:0:8})"
            elif git merge-base --is-ancestor "${GIT_COMMIT}" "${RUN_COMMIT}" 2>/dev/null; then
                # GIT_COMMIT is ancestor of RUN_COMMIT, so RUN_COMMIT is newer
                # Cancel self (current run has older commit)
                echo "  → Skipping cancellation: Other run has newer commit (${RUN_COMMIT:0:8})"
                echo "  → Current run (${GIT_COMMIT:0:8}) is older (ancestor of ${RUN_COMMIT:0:8})"
                echo "=========================================="
                echo "Current run has older commit. Cancelling self to allow newer commit to proceed."
                echo "=========================================="
                # Cancel the current pipeline run (self-cancellation)
                cancel_pipeline_run "${PIPELINE_RUN_ID}" "${COUNTER_FILE}"
                exit 0
            else
                # Git ancestry failed - try GitHub API to get commit timestamps
                echo "  → Cannot determine commit ancestry, trying GitHub API..."
                
                # Get commit timestamps from GitHub API
                RUN_COMMIT_TS=$(get_commit_timestamp "${RUN_COMMIT}")
                CURRENT_COMMIT_TS=$(get_commit_timestamp "${GIT_COMMIT}")
                
                if [[ "${RUN_COMMIT_TS}" != "0" ]] && [[ "${CURRENT_COMMIT_TS}" != "0" ]] && [[ ${RUN_COMMIT_TS} -ne 0 ]] && [[ ${CURRENT_COMMIT_TS} -ne 0 ]]; then
                    # Successfully got commit timestamps from API
                    echo "  → Comparing commit timestamps from GitHub API..."
                    
                    if [[ ${RUN_COMMIT_TS} -gt ${CURRENT_COMMIT_TS} ]]; then
                        # RUN commit is newer - cancel current run (self-cancellation)
                        echo "  → Other run has newer commit (timestamp: ${RUN_COMMIT_TS} > ${CURRENT_COMMIT_TS})"
                        echo "  → Current run (${GIT_COMMIT:0:8}) is older"
                        echo "=========================================="
                        echo "Current run has older commit. Cancelling self to allow newer commit to proceed."
                        echo "=========================================="
                        cancel_pipeline_run "${PIPELINE_RUN_ID}"
                        exit 0
                    elif [[ ${RUN_COMMIT_TS} -lt ${CURRENT_COMMIT_TS} ]]; then
                        # CURRENT commit is newer - cancel the run
                        SHOULD_CANCEL=true
                        CANCEL_REASON="Older commit by timestamp (Run: ${RUN_COMMIT:0:8}, Current: ${GIT_COMMIT:0:8})"
                        echo "  → Will cancel: Run has older commit (timestamp: ${RUN_COMMIT_TS} < ${CURRENT_COMMIT_TS})"
                    else
                        # Same timestamp - skip cancellation for safety
                        echo "  → Commits have same timestamp, skipping cancellation for safety"
                    fi
                else
                    # GitHub API failed - skip cancellation for safety
                    echo "  → Warning: Could not get commit timestamps from GitHub API"
                    echo "  → Skipping cancellation for safety (cannot determine which commit is newer)"
                fi
            fi
        
        # Case 2: Same commit but older run - cancel the older one
        elif [[ -n "${RUN_COMMIT}" ]] && [[ -n "${GIT_COMMIT}" ]] && [[ "${RUN_COMMIT}" == "${GIT_COMMIT}" ]]; then
            echo "  → Same commit detected, comparing timestamps..."
            # Compare creation times (current run should be newer)
            CURRENT_RUN_DETAILS=$(curl -s -X GET \
                --location \
                --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" \
                --header "Accept: application/json" \
                "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${PIPELINE_RUN_ID}")
            
            CURRENT_CREATED_AT=$(echo "${CURRENT_RUN_DETAILS}" | jq -r '.created_at')
            CURRENT_BUILD_NUMBER=$(echo "${CURRENT_RUN_DETAILS}" | jq -r '.build_number')
            
            # Get build number for the run being evaluated
            RUN_BUILD_NUMBER=$(echo "${run}" | jq -r '.build_number')
            
            # Convert timestamps to seconds for comparison
            RUN_TIMESTAMP=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$(echo ${RUN_CREATED_AT} | cut -d'.' -f1)" "+%s" 2>/dev/null || echo "0")
            CURRENT_TIMESTAMP=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$(echo ${CURRENT_CREATED_AT} | cut -d'.' -f1)" "+%s" 2>/dev/null || echo "0")
            
            # If the old run is older than current run, cancel it
            if [[ ${RUN_TIMESTAMP} -lt ${CURRENT_TIMESTAMP} ]]; then
                SHOULD_CANCEL=true
                CANCEL_REASON="Same commit but older run (duplicate)"
                echo "  → Will cancel: Older duplicate run"
            # If timestamps are equal, use build number as tiebreaker
            elif [[ ${RUN_TIMESTAMP} -eq ${CURRENT_TIMESTAMP} ]]; then
                if [[ ${RUN_BUILD_NUMBER} -lt ${CURRENT_BUILD_NUMBER} ]]; then
                    SHOULD_CANCEL=true
                    CANCEL_REASON="Same commit and timestamp, lower build number (Build #${RUN_BUILD_NUMBER} < #${CURRENT_BUILD_NUMBER})"
                    echo "  → Will cancel: Lower build number (duplicate)"
                else
                    echo "  → Skipping: Higher or equal build number"
                fi
            else
                echo "  → Skipping: This run is newer"
            fi
        else
            if [[ "${RUN_EVENT_LISTENER}" == "async-stage-listener" ]]; then
                echo "  → Skipping: Subpipeline (cannot compare commits - inherits parent context)"
            else
                echo "  → Skipping: Cannot determine commit comparison (RUN_COMMIT='${RUN_COMMIT}', GIT_COMMIT='${GIT_COMMIT}')"
            fi
        fi
        
        # Cancel the run if needed
        if [[ "${SHOULD_CANCEL}" == "true" ]]; then
            echo "----------------------------------------"
            echo "Preparing to cancel pipeline run: ${RUN_ID}"
            echo "Reason: ${CANCEL_REASON}"
            echo "Status: ${RUN_STATUS}"
            echo "Created: ${RUN_CREATED_AT}"
            
            # First, cancel any subpipelines triggered by this parent run
            echo "Checking for subpipelines triggered by run ${RUN_ID}..."
            
            # Get all pipeline runs and filter for subpipelines with this parent
            SUBPIPELINE_RUNS=$(curl -s -X GET \
                --location \
                --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" \
                --header "Accept: application/json" \
                "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs?limit=100")
            
            # Verify API response
            if ! echo "${SUBPIPELINE_RUNS}" | jq -e '.pipeline_runs' > /dev/null 2>&1; then
                echo "  → Warning: Failed to fetch pipeline runs or invalid response"
                echo "  → Skipping subpipeline cancellation"
            else
                # Debug: Show total pipeline runs fetched
                TOTAL_RUNS=$(echo "${SUBPIPELINE_RUNS}" | jq '.pipeline_runs | length' 2>/dev/null || echo "0")
                echo "  → Total pipeline runs fetched: ${TOTAL_RUNS}"
                
                # Find subpipelines belonging to this specific parent run
                # Subpipelines store parent run ID in event_params_blob as base64-encoded value
                echo "  → Searching for subpipelines with parent run ID: ${RUN_ID}"
                
                # Count total subpipelines (for informational purposes)
                TOTAL_SUBPIPELINES=$(echo "${SUBPIPELINE_RUNS}" | jq '[.pipeline_runs[]? | select(.trigger.event_listener=="async-stage-listener") | select(.status != "succeeded" and .status != "failed" and .status != "cancelled" and .status != "error")] | length' 2>/dev/null || echo "0")
                echo "  → Total active subpipelines in pipeline: ${TOTAL_SUBPIPELINES}"
                
                # Extract subpipeline IDs that belong to this parent
                SUBPIPELINE_IDS=$(echo "${SUBPIPELINE_RUNS}" | jq -r --arg parent_id "${RUN_ID}" '
                    [.pipeline_runs[]? |
                     select(.trigger.event_listener=="async-stage-listener") |
                     select(.status != "succeeded" and .status != "failed" and .status != "cancelled" and .status != "error") |
                     select(.event_params_blob |
                            try (fromjson | .pipelinectl[]? |
                                 select(.name=="cocoa.string.ci_parent_pipeline_run_id") |
                                 .props[0].value | @base64d) catch "" |
                            . == $parent_id) |
                     .id] | .[]' 2>/dev/null)
                
                if [[ -z "${SUBPIPELINE_IDS}" ]]; then
                    echo "  → No active subpipelines found for pipeline run ${RUN_ID}"
                    if [[ "${TOTAL_SUBPIPELINES}" -gt 0 ]]; then
                        echo "  → Note: ${TOTAL_SUBPIPELINES} other active subpipeline(s) exist in this pipeline (belong to different parent runs)"
                    fi
                else
                    SUBPIPELINE_COUNT=$(echo "${SUBPIPELINE_IDS}" | wc -l | tr -d ' ')
                    echo "  → Found ${SUBPIPELINE_COUNT} active subpipeline(s) for pipeline run ${RUN_ID} to cancel"
                    if [[ "${TOTAL_SUBPIPELINES}" -gt "${SUBPIPELINE_COUNT}" ]]; then
                        OTHER_COUNT=$((TOTAL_SUBPIPELINES - SUBPIPELINE_COUNT))
                        echo "  → Note: ${OTHER_COUNT} other active subpipeline(s) exist (belong to different parent runs)"
                    fi
                    
                    # Cancel each subpipeline
                    while IFS= read -r SUBPIPELINE_ID; do
                        if [[ -n "${SUBPIPELINE_ID}" ]]; then
                            echo "  → Cancelling subpipeline: ${SUBPIPELINE_ID}"
                            cancel_pipeline_run "${SUBPIPELINE_ID}" "${COUNTER_FILE}"
                        fi
                    done <<< "${SUBPIPELINE_IDS}"
                fi
            fi
            
            # Now cancel the parent pipeline run
            echo "Cancelling parent pipeline run: ${RUN_ID}"
            CANCEL_RESPONSE=$(curl -s -X POST \
                --location \
                --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" \
                --header "Accept: application/json" \
                "https://${BASE_URL}/pipeline/v2/tekton_pipelines/${PIPELINE_ID}/pipeline_runs/${RUN_ID}/cancel")
            
            # Check if cancellation was successful
            if echo "${CANCEL_RESPONSE}" | jq -e '.status' > /dev/null 2>&1; then
                CANCEL_STATUS=$(echo "${CANCEL_RESPONSE}" | jq -r '.status')
                echo "Parent pipeline cancellation initiated. New status: ${CANCEL_STATUS}"
                CURRENT_COUNT=$(cat "${COUNTER_FILE}")
                echo "$((CURRENT_COUNT + 1))" > "${COUNTER_FILE}"
            else
                echo "Warning: Failed to cancel parent run ${RUN_ID}"
                echo "Response: ${CANCEL_RESPONSE}"
            fi
            echo "----------------------------------------"
        fi
    else
        echo "  → Skipping: Different PR (Run PR: ${RUN_PR_NUMBER}, Current PR: ${PR_NUMBER})"
    fi
done < <(echo "${PIPELINE_RUNS}" | jq -c '.pipeline_runs[]?' 2>/dev/null)

# Read final count from temp file
CANCELLED_COUNT=$(cat "${COUNTER_FILE}")
rm -f "${COUNTER_FILE}"

echo "=========================================="
echo "Cancellation check complete"
echo "Total runs cancelled: ${CANCELLED_COUNT}"
echo "=========================================="

exit 0

# Made with Bob