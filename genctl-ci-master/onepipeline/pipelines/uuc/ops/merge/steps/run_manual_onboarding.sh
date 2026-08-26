#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# run_manual_onboarding.sh
#
# Manual pipeline step for UUC onboarding provisioning.
# Runs as a manual-trigger pipeline task using the same provisioning scripts
# as the merge pipeline — no code duplication.
#
# Every input is read from env properties set in the toolchain UI.
# Optionally, PIPELINE_MODE and ONBOARDING_FILES can also be passed as
# CLI arguments (useful for local debugging).
#
# ── Required env properties ───────────────────────────────────────────────
#
#   GITHUB_TOKEN               GHE personal access token
#   PIPELINE_MODE              ci | cd | infra | compliance
#
# ── Optional env properties ───────────────────────────────────────────────
#
#   PROCESS_ALL_FILES          true | false  (default: false)
#                              true  → full branch scan; checks out
#                                      ONBOARDING_BRANCH and processes every
#                                      *-onboarding.yaml on it
#                              false → explicit-file mode; ONBOARDING_FILES required
#   ONBOARDING_FILES           Space-separated list of one or more *-onboarding.yaml
#                              paths to process. Relative paths are resolved under
#                              PATH_TO_WORKSPACE_REPO.
#                              Required when PROCESS_ALL_FILES=false.
#                              Examples:
#                                Single : ONBOARDING_FILES=procurement_service-onboarding.yaml
#                                Multiple: ONBOARDING_FILES="auth-service-onboarding.yaml procurement_service-onboarding.yaml"
#   ONBOARDING_DIR             Directory path to scan for *-onboarding.yaml files.
#                              Resolved relative to PATH_TO_WORKSPACE_REPO when not absolute.
#                              May be combined with ONBOARDING_FILES; results are merged.
#                              CLI equivalent: --dir <path>
#   ONBOARDING_BRANCH          Branch to check out when PROCESS_ALL_FILES=true
#                              Default: current HEAD of PATH_TO_WORKSPACE_REPO
#   ACCOUNT_TYPE               dev | prod  (default: dev)
#   ENABLE_TRIGGER_CREATION    true | false  (default: false, cd mode only)
#                              When true, generate_cd_triggers.py regenerates
#                              tier-default and service-specific trigger locals
#                              in <team-slug>-cd-pipeline_vars.tf.
#   INCLUDE_DEVELOPMENT        true | false  (default: false, infra mode only)
#                              When true, zonal/regional secrets are also expanded
#                              for the development tier (e.g. OTC1, OTC2).
#                              Intended for temporary use only.
#   ENABLE_SECRETS_CREATION    true | false  (default: false, infra mode only)
#                              When true, integration env secrets are provisioned.
#                              By default integration is skipped — set to true to
#                              include integration zone/regional secret expansion.
#   AUTO_PR_GITHUB_TOKEN       GHE token used exclusively for PR creation API calls.
#                              Falls back to GITHUB_TOKEN when not set.
#                              Set this when GITHUB_TOKEN has limited scopes and a
#                              separate token with repo write access is needed for PRs.
#
# ── Pipeline-injected env vars (set by one-pipeline framework) ────────────
#
#   PATH_TO_WORKSPACE_REPO             uuc-service-cicd-onboarding clone
#   PATH_TO_GENCTL_CI                  genctl-ci repo root
#   PATH_TO_UUC_TOOLCHAINS_REPO        uuc-toolchains-tf-module clone (ci / cd modes)
#   PATH_TO_UUC_INFRASTRUCTURE_REPO    uuc-infrastructure-tf-module clone (infra mode)
#   WORKSPACE                          pipeline workspace root
#
# ── CLI usage (for local debugging) ──────────────────────────────────────
#
#   Single file:
#     ./run_manual_onboarding.sh ci procurement_service-onboarding.yaml
#
#   Multiple files:
#     ./run_manual_onboarding.sh ci auth-service-onboarding.yaml procurement_service-onboarding.yaml
#
#   Directory scan:
#     ./run_manual_onboarding.sh ci --dir teams/cos
#
#   Full branch scan:
#     ./run_manual_onboarding.sh ci --all
#     ./run_manual_onboarding.sh ci --all --branch dcms-onboarding
#
#   No args — all from env properties (pipeline trigger):
#     PIPELINE_MODE=ci PROCESS_ALL_FILES=true ./run_manual_onboarding.sh
#     PIPELINE_MODE=ci ONBOARDING_FILES="auth-service-onboarding.yaml procurement_service-onboarding.yaml" ./run_manual_onboarding.sh
#     PIPELINE_MODE=cd ENABLE_TRIGGER_CREATION=true ONBOARDING_FILES="auth-service-onboarding.yaml" ./run_manual_onboarding.sh
# =============================================================================================
set -euo pipefail

# ─── Resolve PIPELINE_MODE: CLI arg $1 overrides env property ─────────────────
if [ $# -ge 1 ] && [[ "$1" != --* ]]; then
  PIPELINE_MODE="$1"
  shift
fi

if [ -z "${PIPELINE_MODE:-}" ]; then
  echo "[ERROR] PIPELINE_MODE is required."
  echo ""
  echo "Set it as an env property or pass as the first argument:"
  echo "  PIPELINE_MODE=ci PROCESS_ALL_FILES=true ./run_manual_onboarding.sh"
  echo "  ./run_manual_onboarding.sh <ci|cd|infra|compliance> [--all] [--branch <branch>]"
  exit 1
fi

# ─── Defaults from env properties ────────────────────────────────────────────
PROCESS_ALL_FILES="${PROCESS_ALL_FILES:-false}"
ONBOARDING_FILES="${ONBOARDING_FILES:-}"   # space-separated list; may also be set as positional args
ONBOARDING_DIR="${ONBOARDING_DIR:-}"       # directory to scan; maps to --dir on provisioning scripts
ONBOARDING_BRANCH="${ONBOARDING_BRANCH:-}"
ACCOUNT_TYPE="${ACCOUNT_TYPE:-dev}"
ENABLE_TRIGGER_CREATION="${ENABLE_TRIGGER_CREATION:-false}"
INCLUDE_DEVELOPMENT="${INCLUDE_DEVELOPMENT:-false}"
ENABLE_SECRETS_CREATION="${ENABLE_SECRETS_CREATION:-false}"
AUTO_PR_GITHUB_TOKEN="${AUTO_PR_GITHUB_TOKEN:-}"

# ─── CLI flags / positional args override env properties ──────────────────────
# Bare positional args are treated as onboarding file paths (single or multiple).
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      PROCESS_ALL_FILES="true"
      shift
      ;;
    --branch)
      ONBOARDING_BRANCH="$2"
      shift 2
      ;;
    --dir)
      ONBOARDING_DIR="$2"
      shift 2
      ;;
    --account-type)
      ACCOUNT_TYPE="$2"
      shift 2
      ;;
    --enable-triggers)
      ENABLE_TRIGGER_CREATION="true"
      shift
      ;;
    --include-development)
      INCLUDE_DEVELOPMENT="true"
      shift
      ;;
    --enable-secrets-creation)
      ENABLE_SECRETS_CREATION="true"
      shift
      ;;
    -*)
      echo "[ERROR] Unknown flag: $1"
      exit 1
      ;;
    *)
      # Accumulate bare positional args as space-separated file list
      if [ "$PROCESS_ALL_FILES" = "false" ]; then
        ONBOARDING_FILES="${ONBOARDING_FILES:+$ONBOARDING_FILES }$1"
      fi
      shift
      ;;
  esac
done

# ─── Validate pipeline-injected paths are present ────────────────────────────
for var in PATH_TO_WORKSPACE_REPO PATH_TO_GENCTL_CI; do
  if [ -z "${!var:-}" ]; then
    echo "[ERROR] $var is not set. Ensure it is configured as a pipeline env property."
    exit 1
  fi
done

# ci and cd modes need the toolchains repo; infra mode needs the infrastructure repo
case "$PIPELINE_MODE" in
  ci|cd)
    if [ -z "${PATH_TO_UUC_TOOLCHAINS_REPO:-}" ]; then
      echo "[ERROR] PATH_TO_UUC_TOOLCHAINS_REPO is required for PIPELINE_MODE=${PIPELINE_MODE}"
      exit 1
    fi
    ;;
  infra)
    if [ -z "${PATH_TO_UUC_INFRASTRUCTURE_REPO:-}" ]; then
      echo "[ERROR] PATH_TO_UUC_INFRASTRUCTURE_REPO is required for PIPELINE_MODE=infra"
      exit 1
    fi
    ;;
esac

# ─── Resolve script path from PIPELINE_MODE ───────────────────────────────────
MERGE_STEPS="${PATH_TO_GENCTL_CI}/onepipeline/pipelines/uuc/ops/merge/steps"

case "$PIPELINE_MODE" in
  ci)          SCRIPT_PATH="$MERGE_STEPS/provision_team_ci_toolchains.sh" ;;
  cd)          SCRIPT_PATH="$MERGE_STEPS/provision_team_cd_toolchains.sh" ;;
  infra)       SCRIPT_PATH="$MERGE_STEPS/provision_team_infrastructure.sh" ;;
  compliance)  SCRIPT_PATH="$MERGE_STEPS/create_compliance_repos.sh" ;;
  *)
    echo "[ERROR] Invalid PIPELINE_MODE: $PIPELINE_MODE"
    echo "Expected: ci | cd | infra | compliance"
    exit 1
    ;;
esac

# ─── Validate required values ─────────────────────────────────────────────────
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "[ERROR] GITHUB_TOKEN is required"
  exit 1
fi

if [ "$PROCESS_ALL_FILES" = "false" ] && [ -z "$ONBOARDING_FILES" ] && [ -z "$ONBOARDING_DIR" ]; then
  echo "[ERROR] At least one of ONBOARDING_FILES, ONBOARDING_DIR, or PROCESS_ALL_FILES=true is required"
  echo ""
  echo "Options:"
  echo "  Single file : ONBOARDING_FILES=procurement_service-onboarding.yaml"
  echo "  Multiple    : ONBOARDING_FILES=\"auth-service-onboarding.yaml procurement_service-onboarding.yaml\""
  echo "  Directory   : ONBOARDING_DIR=teams/cos"
  echo "  Full branch : PROCESS_ALL_FILES=true"
  exit 1
fi

# ─── Resolve each file to absolute path ───────────────────────────────────────
# Split ONBOARDING_FILES on spaces into an array, resolve relative paths.
declare -a RESOLVED_FILES=()
if [ "$PROCESS_ALL_FILES" = "false" ]; then
  if [ -n "$ONBOARDING_FILES" ]; then
    IFS=' ' read -ra _raw_files <<< "$ONBOARDING_FILES"
    for _f in "${_raw_files[@]}"; do
      [ -z "$_f" ] && continue
      if [[ "$_f" != /* ]]; then
        _f="${PATH_TO_WORKSPACE_REPO}/${_f}"
      fi
      RESOLVED_FILES+=("$_f")
    done
  fi

  # Resolve ONBOARDING_DIR to absolute path (passed as --dir to provisioning scripts)
  if [ -n "$ONBOARDING_DIR" ] && [[ "$ONBOARDING_DIR" != /* ]]; then
    ONBOARDING_DIR="${PATH_TO_WORKSPACE_REPO}/${ONBOARDING_DIR}"
  fi
fi

# ─── Export env vars consumed by provisioning scripts ─────────────────────────
export PATH_TO_GENCTL_CI
export PATH_TO_WORKSPACE_REPO
# ONBOARDING_REPO_PATH: stable pointer read by get_all_files_from_branch()
# before one_pipeline_utils.sh can overwrite PATH_TO_WORKSPACE_REPO.
export ONBOARDING_REPO_PATH="${PATH_TO_WORKSPACE_REPO}"
export PATH_TO_UUC_TOOLCHAINS_REPO="${PATH_TO_UUC_TOOLCHAINS_REPO:-}"
export PATH_TO_UUC_INFRASTRUCTURE_REPO="${PATH_TO_UUC_INFRASTRUCTURE_REPO:-}"
export GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"
export GITHUB_TOKEN
export ACCOUNT_TYPE
export PROCESS_ALL_FILES
export ENABLE_TRIGGER_CREATION
export INCLUDE_DEVELOPMENT
export ENABLE_SECRETS_CREATION
[ -n "$AUTO_PR_GITHUB_TOKEN" ] && export AUTO_PR_GITHUB_TOKEN
[ -n "$ONBOARDING_BRANCH" ]    && export ONBOARDING_BRANCH

# ─── Set up symlink workspace ─────────────────────────────────────────────────
WORKSPACE_APP_PATH="${WORKSPACE:-/tmp}/uuc-onboarding-cron-workspace"
mkdir -p "$WORKSPACE_APP_PATH"
ln -sfn "$PATH_TO_WORKSPACE_REPO" "$WORKSPACE_APP_PATH/uuc-service-cicd-onboarding"
[ -n "${PATH_TO_UUC_TOOLCHAINS_REPO:-}" ] && \
  ln -sfn "$PATH_TO_UUC_TOOLCHAINS_REPO" "$WORKSPACE_APP_PATH/uuc-toolchains-tf-module"
[ -n "${PATH_TO_UUC_INFRASTRUCTURE_REPO:-}" ] && \
  ln -sfn "$PATH_TO_UUC_INFRASTRUCTURE_REPO" "$WORKSPACE_APP_PATH/uuc-infrastructure-tf-module"

# ─── Print resolved config ────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  UUC Onboarding — Manual Pipeline Run"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PIPELINE_MODE              : $PIPELINE_MODE"
echo "  PROCESS_ALL_FILES          : $PROCESS_ALL_FILES"
echo "  ACCOUNT_TYPE               : $ACCOUNT_TYPE"
echo "  ENABLE_TRIGGER_CREATION    : $ENABLE_TRIGGER_CREATION"
echo "  INCLUDE_DEVELOPMENT        : $INCLUDE_DEVELOPMENT"
echo "  ENABLE_SECRETS_CREATION    : $ENABLE_SECRETS_CREATION"
echo "  AUTO_PR_GITHUB_TOKEN       : ${AUTO_PR_GITHUB_TOKEN:+(set)}"
echo "  PATH_TO_WORKSPACE_REPO     : $PATH_TO_WORKSPACE_REPO"
[ -n "${PATH_TO_UUC_TOOLCHAINS_REPO:-}" ]     && echo "  PATH_TO_UUC_TOOLCHAINS_REPO: $PATH_TO_UUC_TOOLCHAINS_REPO"
[ -n "${PATH_TO_UUC_INFRASTRUCTURE_REPO:-}" ] && echo "  PATH_TO_UUC_INFRA_REPO     : $PATH_TO_UUC_INFRASTRUCTURE_REPO"
echo "  PATH_TO_GENCTL_CI          : $PATH_TO_GENCTL_CI"
echo "  WORKSPACE_APP_PATH         : $WORKSPACE_APP_PATH"
echo "  Script                     : $SCRIPT_PATH"

if [ "$PROCESS_ALL_FILES" = "true" ]; then
  if [ -n "${ONBOARDING_BRANCH:-}" ]; then
    echo "  ONBOARDING_BRANCH          : $ONBOARDING_BRANCH (explicit)"
  else
    _cur=$(git -C "$PATH_TO_WORKSPACE_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    echo "  ONBOARDING_BRANCH          : ${_cur} (current HEAD of PATH_TO_WORKSPACE_REPO)"
  fi
else
  if [ ${#RESOLVED_FILES[@]} -gt 0 ]; then
    echo "  ONBOARDING_FILES (${#RESOLVED_FILES[@]}):"
    for _f in "${RESOLVED_FILES[@]}"; do
      echo "    - $_f"
    done
  fi
  if [ -n "$ONBOARDING_DIR" ]; then
    echo "  ONBOARDING_DIR             : $ONBOARDING_DIR"
  fi
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── Build args and run ───────────────────────────────────────────────────────
declare -a _run_args=()

if [ "$PROCESS_ALL_FILES" = "true" ]; then
  # Full-branch mode — provisioning scripts detect PROCESS_ALL_FILES=true
  # and call get_all_files_from_branch() internally; no --files needed.
  : # no extra args
else
  [ ${#RESOLVED_FILES[@]} -gt 0 ] && _run_args+=(--files "${RESOLVED_FILES[@]}")
  [ -n "$ONBOARDING_DIR" ]        && _run_args+=(--dir "$ONBOARDING_DIR")
fi

bash "$SCRIPT_PATH" "${_run_args[@]}"

# Made with Bob
