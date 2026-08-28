#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -o pipefail

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Set the pipeline template type
export PIPELINE_TYPE="merge"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Set pipeline environment and prepare it (sources secrets.sh / vars.sh / aliases.sh)
# This gives us GITHUB_API_KEY, WORKSPACE_ORG, WORKSPACE_REPO, GITHUB_API_URL
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# =============================================================================
# Post merge pipeline run URL as a comment on the PR that triggered this merge
#
# NOTE: This is a MERGE pipeline, triggered by a push-to-main event — NOT a PR
# event. PR_URL is not injected by OnePipeline in this context. Instead, we
# resolve the originating PR number by querying the GitHub API with the merge
# commit SHA (the commit OnePipeline checked out as the app-repo HEAD).
# =============================================================================

if [[ -z "${PIPELINE_RUN_URL:-}" ]]; then
  echo "WARNING: PIPELINE_RUN_URL is not set — skipping pipeline URL comment."
  exit 0
fi

# The merge commit SHA — this is the commit on main that OnePipeline checked out
MERGE_COMMIT_SHA="$(load_repo app-repo commit)"

if [[ -z "${MERGE_COMMIT_SHA}" ]]; then
  echo "WARNING: Could not read merge commit SHA from app-repo — skipping pipeline URL comment."
  exit 0
fi

GH_API_BASE="$(get_env GITHUB_API_URL | sed 's|/$||')"

echo "Resolving PR number from merge commit ${MERGE_COMMIT_SHA}..."

# GitHub API: GET /repos/:org/:repo/commits/:sha/pulls
# Returns the list of PRs associated with the merge commit.
PR_NUMBER=$(curl -s \
  "${GH_API_BASE}/repos/${WORKSPACE_ORG}/${WORKSPACE_REPO}/commits/${MERGE_COMMIT_SHA}/pulls" \
  -H "Authorization: Bearer ${GITHUB_API_KEY}" \
  -H "Accept: application/vnd.github.v3+json" \
  | jq -r '.[0].number // empty')

if [[ -z "${PR_NUMBER}" ]]; then
  echo "WARNING: Could not resolve a PR number for commit ${MERGE_COMMIT_SHA} — skipping pipeline URL comment."
  exit 0
fi

echo "Resolved PR #${PR_NUMBER}. Posting merge pipeline URL..."

# -----------------------------------------------------------------------------
# Comment format — mirrors the #### KEY: value convention used by add_comment.py
# so callers can parse it with the same grep/split pattern used by get_pr_md5.py.
#
# Sentinel: "#### Merge Pipeline Summary ####"
# Fields:
#   #### pipeline_url: full Tekton run URL — pipeline_id and pipeline_run_id
#                      are embedded in the URL and can be parsed by the reader:
#                        pipeline_id:     grep -oP '(?<=/pipelines/tekton/)[^/?]+'
#                        pipeline_run_id: grep -oP '(?<=/runs/)[^/?]+'
#   #### workspace:    TF workspace name
# -----------------------------------------------------------------------------
COMMENT_BODY="$(cat <<EOF
#### Merge Pipeline Summary ####
#### pipeline_url: ${PIPELINE_RUN_URL}
#### workspace: ${workspace_name}
EOF
)"

curl -s -X POST \
  "${GH_API_BASE}/repos/${WORKSPACE_ORG}/${WORKSPACE_REPO}/issues/${PR_NUMBER}/comments" \
  -H "Authorization: Bearer ${GITHUB_API_KEY}" \
  -H "Content-Type: application/json" \
  --data "$(jq -n --arg body "${COMMENT_BODY}" '{"body": $body}')" \
  -o /dev/null \
  && echo "Pipeline URL comment posted to PR #${PR_NUMBER}." \
  || echo "WARNING: Failed to post pipeline URL comment to PR #${PR_NUMBER} (non-fatal)."
