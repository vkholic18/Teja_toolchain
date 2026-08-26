#!/bin/bash

# CI/CD Onboarding YAML Validation Script Wrapper
# This script validates onboarding.yaml files changed in a PR.
# Supports multi-team structure: <team-folder>/<repo-name>-onboarding.yaml
# Excludes sample/reference onboarding.yaml in root directory.
#
# PR-level commons.yaml invariant checks are run ONCE before per-file
# validation to catch:
#   1. commons.yaml missing when a new service onboarding file is added
#   2. commons.yaml being deleted in the PR
#   3. 'secrets' section present in a service onboarding file
#
# Usage: ./validate_yaml.sh [--debug] [<path_to_onboarding.yaml> ...]

# Note: Not using 'set -e' to allow validation of all files even if some fail

# Source common utilities
source "${PATH_TO_GENCTL_CI}/onepipeline/utils/onboarding_validation_utils.sh"

# Get the directory where this script is located (for Python script path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize debug flag and check if --debug was passed
init_debug_flag "$@"
if [ $? -eq 1 ]; then
    shift  # Remove --debug from arguments
fi

# Check Python availability
check_python_available

# ---------------------------------------------------------------------------
# run_commons_invariant_check
#
# Calls validate_yaml.py --check-commons <search_dir> to enforce the three
# PR-level commons.yaml invariants (exists before new files, not deleted,
# no secrets in service files).  Runs ONCE per PR, not once per file.
#
# Args:
#   $1  search_dir — the branch workspace root directory
# Returns:
#   0  — all invariants passed
#   1  — one or more invariants violated (errors printed to stdout)
# ---------------------------------------------------------------------------
run_commons_invariant_check() {
    local search_dir="${1:-.}"

    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}▶ commons.yaml PR-Level Invariant Checks${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    python3 "$SCRIPT_DIR/validate_yaml.py" $DEBUG_FLAG --check-commons "$search_dir"
    local rc=$?

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    return $rc
}

# Main execution
main() {
    local files_to_validate=()
    local overall_exit_code=0

    # Resolve the workspace root: prefer PATH_TO_WORKSPACE_REPO, fall back to PWD
    local workspace_root="${PATH_TO_WORKSPACE_REPO:-$PWD}"

    # ── Step 1: PR-level commons.yaml invariant checks ────────────────────────
    # Run once before per-file loops.  Failures here are immediately surfaced
    # but we still proceed to validate individual files so teams see all errors
    # in one pipeline run rather than fixing them one-by-one.
    run_commons_invariant_check "$workspace_root"
    if [ $? -ne 0 ]; then
        overall_exit_code=1
    fi

    # ── Step 2: Collect files to validate ─────────────────────────────────────
    # If specific files are provided as arguments, use them
    if [ $# -gt 0 ]; then
        files_to_validate=("$@")
        echo -e "${BLUE}[INFO]${NC} Validating specified files: ${files_to_validate[*]}"
    else
        # Try to get changed files from git
        echo -e "${BLUE}[INFO]${NC} No files specified, attempting to detect changed files from git..."

        mapfile -t files_to_validate < <(get_changed_files_from_git)

        if [ ${#files_to_validate[@]} -eq 0 ]; then
            # Check whether commons.yaml itself changed — if so, all onboarding
            # files on the branch are affected and must be re-validated.
            if commons_changed_in_pr; then
                echo -e "${BLUE}[INFO]${NC} commons.yaml changed — expanding scope to all onboarding files in workspace..."
                mapfile -t files_to_validate < <(find_onboarding_files "$workspace_root")
            else
                # No changed files detected.  Before falling back to a full
                # workspace scan, check whether the PR is a pure offboard
                # (file deleted or renamed with no additions).  Deleted files
                # don't exist on disk and don't need schema validation — running
                # the full scan on them would (a) produce false failures for
                # unchanged services and (b) block the offboard PR from merging.
                local deleted_files=()
                mapfile -t deleted_files < <(get_deleted_onboarding_files 2>/dev/null) || true

                if [ ${#deleted_files[@]} -gt 0 ]; then
                    echo -e "${BLUE}[INFO]${NC} PR contains only deletion(s) of onboarding file(s) — offboard scenario, skipping schema validation"
                    for df in "${deleted_files[@]}"; do
                        echo -e "  ${YELLOW}🗑  $(basename "$df")${NC} — deleted / offboarded"
                    done
                    # Nothing to validate — exit with the invariant check result only.
                    exit $overall_exit_code
                fi

                # Genuine fallback: no changes detected at all (e.g. shallow
                # clone, manual trigger, or git diff unavailable).  Scan
                # everything so the PR still gets some validation coverage.
                echo -e "${YELLOW}[WARNING]${NC} No changed or deleted files detected from git."
                echo -e "${BLUE}[INFO]${NC} Searching for all onboarding files in workspace..."
                mapfile -t files_to_validate < <(find_onboarding_files "$workspace_root")
            fi
        fi
    fi
    
    # Check if we have any files to validate
    if [ ${#files_to_validate[@]} -eq 0 ]; then
        echo -e "${YELLOW}[WARNING]${NC} No onboarding YAML files found to validate."
        echo -e "${BLUE}[INFO]${NC} Expected file pattern: <service_name>-onboarding.yaml"
        # Still exit with the invariant check result
        exit $overall_exit_code
    fi
    
    echo -e "${GREEN}[INFO]${NC} Found ${#files_to_validate[@]} file(s) to validate"
    echo ""
    
    # ── Step 3: Validate each service onboarding file ─────────────────────────
    for yaml_file in "${files_to_validate[@]}"; do
        if [ ! -f "$yaml_file" ]; then
            echo -e "${RED}[ERROR]${NC} File not found: $yaml_file"
            overall_exit_code=1
            continue
        fi
        
        run_validation_on_file "Validating YAML Schema" "$yaml_file" "$SCRIPT_DIR/validate_yaml.py" "$DEBUG_FLAG"
        
        if [ $? -ne 0 ]; then
            overall_exit_code=1
        fi
    done
    
    # ── Final summary ──────────────────────────────────────────────────────────
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [ $overall_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ All YAML schema validation checks passed${NC}"
    else
        echo -e "${RED}✗ Some YAML schema validation checks failed${NC}"
        show_documentation_link
    fi
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    exit $overall_exit_code
}

# Run main function
main "$@"
