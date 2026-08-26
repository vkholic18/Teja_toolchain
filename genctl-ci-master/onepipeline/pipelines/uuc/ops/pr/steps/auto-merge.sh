#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
set -euo pipefail

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Source onboarding validation utils (for get_changed_files_from_git)
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/onboarding_validation_utils.sh

# Set the pipeline template type
export PIPELINE_TYPE="pr"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="false"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# ---------------------------------------------------------------------------
# Guard: block auto-merge if any changed onboarding YAML uses cd_only profile
# ---------------------------------------------------------------------------
_cd_only_files=()
while IFS= read -r _f; do
    [[ -z "$_f" ]] && continue
    if grep -qE '^[[:space:]]*cicd_profile:[[:space:]]*cd_only[[:space:]]*$' "$_f" 2>/dev/null; then
        _cd_only_files+=("$_f")
    fi
done < <(get_changed_files_from_git 2>/dev/null || true)

if [[ ${#_cd_only_files[@]} -gt 0 ]]; then
    echo "[AUTO-MERGE] cd_only profile detected in the following onboarding file(s):"
    for _f in "${_cd_only_files[@]}"; do
        echo "  - $_f"
    done
    echo "[AUTO-MERGE] Skipping auto-merge and sending Slack notification."

    # Build a human-readable list of affected files for the Slack message
    _cd_only_list=""
    for _f in "${_cd_only_files[@]}"; do
        _cd_only_list="${_cd_only_list}\n• $(basename "$_f")"
    done

    bash "${PATH_TO_GENCTL_CI}/onepipeline/utils/notify_slack.sh" \
        --webhook-url   "${SLACK_WEBHOOK_URL:-}" \
        --channel       "${SLACK_CHANNEL:-}" \
        --verdict       "NEEDS_REVIEW" \
        --pr-url        "${PR_URL:-}" \
        --pipeline-url  "${PIPELINE_RUN_URL:-}" \
        --tag-group     "${SLACK_TAG_GROUP:-}" \
        --repo          "${PR_BASEBRANCH:-}" \
        --mode          "onboarding" \
        --pipeline-type "PR" \
        --review-body   "REASON: Onboarding PR contains a cd_only profile and cannot be auto-merged.$(printf '%b' "${_cd_only_list}")" \
        || true

    echo "[AUTO-MERGE] Notification sent. Exiting without merging."
    exit 0
fi

# detect the phase of the PR
detect_pr_phase "$PR_URL"

if [[ "$PR_PHASE" == "pre-merge" ]]; then
    ### Auto-merge ### (Since is only one task no need for job)
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "AUTO_MERGE" ${EXIT_ON_TASK_FAILURE} \
    ${PATH_TO_GENCTL_CI}/scripts/merge_pr/merge_pr.sh
elif [[ "$PR_PHASE" == "post-merge" ]]; then
    echo "[AUTO-MERGE] PR has already been merged, so skipping the auto-merge functionality."
else
    echo "[AUTO-MERGE] PR is either closed or UNKNOWN state; auto-merge will not be executed."
    echo "Exiting..."
    exit 1
fi
