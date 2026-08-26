#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# bob-pr-review.sh - Runs the Bob AI PR review for pr_dev_integration pipelines.
#
# This script is sourced by onepipeline/jobs/run_bob_pr_review.sh after the
# common Bob setup (bob_setup.sh) has already been applied in test.sh.

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

echo "=========================================="
echo "Bob AI PR Review"
echo "=========================================="

export WORKSPACE_REPO_ORG="${PIPELINE_REPO_ORG}"
export WORKSPACE_REPO_NAME="${PIPELINE_REPO_NAME}"

export GITHUB_HOST="${GITHUB_HOST:-github.ibm.com}"
PR_URL="https://${GITHUB_HOST}/${WORKSPACE_REPO_ORG}/${WORKSPACE_REPO_NAME}/pull/${PR_ID}"
echo "PR URL: ${PR_URL}"

# ---------------------------------------------------------------------------
# Clone VPC DevOps Governance repository for repo-specific review standards
# ---------------------------------------------------------------------------
GOVERNANCE_REPO_ORG="genctl-cicd"
GOVERNANCE_REPO_NAME="vpc-devops-governance"
GOVERNANCE_REPO_BRANCH="cd-repo-def"
GOVERNANCE_REPO_URL="git@${GITHUB_HOST}:${GOVERNANCE_REPO_ORG}/${GOVERNANCE_REPO_NAME}.git"
GOVERNANCE_REPO_PATH="${CI_TEMP_DIR}/vpc-devops-governance"

if [ -d "${GOVERNANCE_REPO_PATH}" ]; then
    echo "Governance repo already cloned, pulling latest..."
    git -C "${GOVERNANCE_REPO_PATH}" pull origin "${GOVERNANCE_REPO_BRANCH}" || \
        echo "WARNING: Failed to pull governance repo"
else
    echo "Cloning governance repo (branch: ${GOVERNANCE_REPO_BRANCH})..."
    git clone -b "${GOVERNANCE_REPO_BRANCH}" "${GOVERNANCE_REPO_URL}" "${GOVERNANCE_REPO_PATH}" || {
        echo "WARNING: Failed to clone governance repo — continuing without governance context"
        GOVERNANCE_REPO_PATH=""
    }
fi

export GOVERNANCE_CONTEXT="
**Repository Governance Context**:
This repository follows IBM VPC DevOps governance standards defined at:
- Governance Repository: https://${GITHUB_HOST}/${GOVERNANCE_REPO_ORG}/${GOVERNANCE_REPO_NAME} (branch: ${GOVERNANCE_REPO_BRANCH})
- Local Clone: ${GOVERNANCE_REPO_PATH:-not available}

**CRITICAL**: Read the repo-specific governance YAML if available:
  ${GOVERNANCE_REPO_PATH}/context/cd-automation-repos/${WORKSPACE_REPO_NAME}.yaml

Use it as the authoritative source for code review standards in this repository.
Key governance areas: code standards, CI/CD patterns, testing requirements, IaC practices.
"

# ---------------------------------------------------------------------------
# Load review instructions from governance repo
# ---------------------------------------------------------------------------
INSTRUCTIONS_FILE="${GOVERNANCE_REPO_PATH}/context/bob-pr-review-instructions.md"

# The header is always prepended so Bob always has PR URL, repo, and governance context,
# regardless of whether the instructions file is present or not.
BOB_PROMPT_HEADER="You are performing an automated PR review in a CI/CD pipeline for IBM VPC infrastructure code.

**PR URL**: ${PR_URL}
**Repository**: ${WORKSPACE_REPO_ORG}/${WORKSPACE_REPO_NAME}

${GOVERNANCE_CONTEXT}"

if [ -f "${INSTRUCTIONS_FILE}" ]; then
    echo "Loading review instructions from governance repo: ${INSTRUCTIONS_FILE}"
    # envsubst expands only the listed placeholders — keeps any other ${} intact.
    INSTRUCTIONS_BODY=$(envsubst '${PR_URL} ${WORKSPACE_REPO_ORG} ${WORKSPACE_REPO_NAME} ${GOVERNANCE_CONTEXT}' \
        < "${INSTRUCTIONS_FILE}")
    BOB_PROMPT="${BOB_PROMPT_HEADER}

${INSTRUCTIONS_BODY}"
else
    echo "WARNING: Instructions file not found at ${INSTRUCTIONS_FILE} — using built-in prompt"
    BOB_PROMPT="${BOB_PROMPT_HEADER}

Use GitHub MCP tools to fetch the PR, review only the diff, post inline comments with severity prefixes (🔴 CRITICAL 🟡 HIGH 🟠 MEDIUM 🔵 LOW), and post a final summary comment with a quality score and APPROVE/REQUEST_CHANGES/COMMENT recommendation.

Begin the review now."
fi

# ---------------------------------------------------------------------------
# Execute Bob PR review
# ---------------------------------------------------------------------------
BOB_REVIEW_START=$(date +%s)
BOB_STREAM="${CI_TEMP_DIR}/bob-pr-review-stream.jsonl"
BOB_OUTPUT="${CI_TEMP_DIR}/bob-pr-review-output.log"
rm -f "${BOB_STREAM}" "${BOB_OUTPUT}"

echo "Running Bob PR review (mode: advanced)..."
echo "Instructions source: ${INSTRUCTIONS_FILE:-built-in}"

bob --chat-mode advanced --auth-method api-key --yolo \
    --output-format stream-json \
    --hide-intermediary-output \
    "${BOB_PROMPT}" \
    > "${BOB_STREAM}" 2>&1

BOB_EXIT_CODE=$?
BOB_REVIEW_DURATION=$(( $(date +%s) - BOB_REVIEW_START ))

# Extract plain-text output from stream
grep '^{' "${BOB_STREAM}" \
    | jq -r 'select(.type=="tool_use" and .tool_name=="attempt_completion") | .parameters.result' \
    2>/dev/null > "${BOB_OUTPUT}" || true

echo ""
echo "--- Bob review output ---"
cat "${BOB_OUTPUT}" || true
echo ""
echo "=========================================="
if [ ${BOB_EXIT_CODE} -eq 0 ]; then
    echo "✅ Bob AI PR review completed (${BOB_REVIEW_DURATION}s)"
else
    echo "❌ Bob AI PR review failed with exit code ${BOB_EXIT_CODE} (optional check — pipeline continues)"
fi
echo "=========================================="

# This is an optional check — never fail the pipeline
exit 0