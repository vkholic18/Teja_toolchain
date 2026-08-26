#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# run_bob_pr_review.sh - Job wrapper for the Bob AI PR review step.
#
# Only runs when the PR carries the label defined by BOB_PR_REVIEW_LABEL_NAME
# (default: "bob-review").  This keeps the review opt-in per PR.
#
# Called via: run_job "BOB_PR_REVIEW" "false" \
#                 ${PATH_TO_GENCTL_CI}/onepipeline/jobs/run_bob_pr_review.sh

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Only meaningful on a PR pipeline
if [[ -z "${PR_ID}" ]]; then
    echo "Not a PR build (PR_ID is unset). Skipping Bob review..."
    exit 0
fi

BOB_PR_REVIEW_LABEL_NAME="${BOB_PR_REVIEW_LABEL_NAME:-bob-review}"

${PATH_TO_GENCTL_CI}/scripts/check_pr_has_label/check_pr_has_label.sh "${BOB_PR_REVIEW_LABEL_NAME}"
label_result=$?

echo "check_pr_has_label result: ${label_result}"

if [[ ${label_result} -eq 0 ]]; then
    echo "Label '${BOB_PR_REVIEW_LABEL_NAME}' found — running Bob AI PR review for PR #${PR_ID}"
    source ${PATH_TO_GENCTL_CI}/onepipeline/utils/bob_setup.sh
    source ${PATH_TO_PIPELINE}/steps/bob-pr-review.sh
elif [[ ${label_result} -eq 100 ]]; then
    echo "WARNING: Failed to check for label '${BOB_PR_REVIEW_LABEL_NAME}' — skipping Bob review"
    exit 0
else
    echo "Label '${BOB_PR_REVIEW_LABEL_NAME}' not present — skipping Bob review"
    exit 0
fi