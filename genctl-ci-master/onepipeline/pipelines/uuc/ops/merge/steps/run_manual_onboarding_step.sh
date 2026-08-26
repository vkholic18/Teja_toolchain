#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# run_manual_onboarding_step.sh
#
# One-pipeline wrapper for the manual / cron onboarding pipeline task.
# Follows the same structure as the other *_step.sh files in this directory:
#   - sources the framework (tools, one_pipeline_utils, colors, ci_logic_runners)
#   - clones both UUC_TOOLCHAINS and UUC_INFRASTRUCTURE_TOOLCHAINS repos
#   - sets PATH_TO_UUC_TOOLCHAINS_REPO and PATH_TO_UUC_INFRASTRUCTURE_REPO
#   - prepares the pipeline environment (secrets + vars + aliases)
#   - delegates to run_manual_onboarding.sh via run_task
#
# Required toolchain env properties:
#   PIPELINE_MODE              ci | cd | infra | compliance
#   PROCESS_ALL_FILES          true | false  (default: false)
#   ONBOARDING_FILES           space-separated list of *-onboarding.yaml paths;
#                              required when PROCESS_ALL_FILES=false and
#                              ONBOARDING_DIR is not set
#   ONBOARDING_DIR             directory path to scan for *-onboarding.yaml files;
#                              alternative / complement to ONBOARDING_FILES
#   ONBOARDING_BRANCH          branch to scan when PROCESS_ALL_FILES=true
#   ACCOUNT_TYPE               dev | prod  (default: dev)
#
# Optional toolchain env properties:
#   ENABLE_TRIGGER_CREATION    true | false  (default: false, cd mode only)
#                              regenerates CD trigger locals via generate_cd_triggers.py
#   AUTO_PR_GITHUB_TOKEN       separate GHE token for PR creation API calls;
#                              falls back to GITHUB_TOKEN when not set

# ─── Source one-pipeline framework ───────────────────────────────────────────
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

export PIPELINE_TYPE="merge"

# ─── Clone required repos ────────────────────────────────────────────────────
# Both toolchains and infrastructure repos are cloned regardless of PIPELINE_MODE
# so that run_manual_onboarding.sh can dispatch to any of the four modes
# without needing a second clone step.
REPOS_TO_CLONE="
UUC_TOOLCHAINS
UUC_INFRASTRUCTURE_TOOLCHAINS"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and overrides
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
    "${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Clone required repos
clone_repos_from_env_vars "${IBM_HTTPS_BASE_URL}" "${WORKSPACE}" "${REPOS_TO_CLONE}"

# Expose cloned repo paths to run_manual_onboarding.sh
export PATH_TO_UUC_TOOLCHAINS_REPO="${WORKSPACE}/${UUC_TOOLCHAINS_REPO_NAME}"
export PATH_TO_UUC_INFRASTRUCTURE_REPO="${WORKSPACE}/${UUC_INFRASTRUCTURE_TOOLCHAINS_REPO_NAME}"

# ─── Prepare pipeline environment (secrets + vars + aliases) ─────────────────
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# ─── Task flags ───────────────────────────────────────────────────────────────
export EXIT_ON_TASK_FAILURE="true"
export SET_GHE_STATUSES="true"

# ─── Dispatch to run_manual_onboarding.sh ───────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${SCRIPT_DIR}/run_manual_onboarding.sh" ]; then
    echo "Running manual onboarding pipeline step (PIPELINE_MODE=${PIPELINE_MODE:-unset})"
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "run_manual_onboarding" ${EXIT_ON_TASK_FAILURE} \
        ${SCRIPT_DIR}/run_manual_onboarding.sh
else
    echo "run_manual_onboarding.sh not found in: ${SCRIPT_DIR}"
    exit 1
fi

# Made with Bob
