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

# Fetch BOB verdict from the latest BOB AI review comment on the PR
_GH_API_BASE="$(echo "${GHE_API_URL}" | sed 's|/$||')"
_BOB_COMMENT_FILE="$(mktemp /tmp/bob_comment_XXXXXX.md)"

echo "[AUTO-MERGE] Fetching latest BOB review comment from PR #${PR_NUMBER}..."
_BOB_COMMENT_BODY=$(curl -s \
    "${_GH_API_BASE}/repos/${WORKSPACE_ORG}/${WORKSPACE_REPO}/issues/${PR_NUMBER}/comments" \
    -H "Authorization: Bearer ${GHE_API_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    | jq -r '[.[] | select(.body | test("🤖 BOB AI Terraform Review"; "i"))] | last | .body // empty')

if [[ -z "${_BOB_COMMENT_BODY}" ]]; then
    echo "[AUTO-MERGE] No BOB review comment found on PR #${PR_NUMBER} — falling back to pipeline env."
    BOB_VERDICT=$(get_env "bob-verdict" "")
else
    echo "${_BOB_COMMENT_BODY}" > "${_BOB_COMMENT_FILE}"
    BOB_VERDICT=$(bash "${PATH_TO_GENCTL_CI}/onepipeline/utils/extract_bob_verdict.sh" "${_BOB_COMMENT_FILE}") || true
    echo "[AUTO-MERGE] BOB verdict extracted from latest PR comment."
fi

rm -f "${_BOB_COMMENT_FILE}"
export BOB_VERDICT
echo "[AUTO-MERGE] BOB_VERDICT=${BOB_VERDICT}"

if [[ "${BOB_VERDICT}" != "APPROVE" ]]; then
    echo "[AUTO-MERGE] Verdict is '${BOB_VERDICT}' — auto-merge requires APPROVE. Skipping."
    exit 0
fi

echo "[AUTO-MERGE] Verdict is APPROVE — proceeding with auto-merge."

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
