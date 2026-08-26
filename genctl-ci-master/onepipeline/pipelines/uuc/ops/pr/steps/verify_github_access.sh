#!/bin/bash

# GitHub Repository Access Verification Script Wrapper
# This script verifies GitHub repository access for functional IDs
# Supports multi-team structure: <team-folder>/<repo-name>-onboarding.yaml
# Excludes sample/reference onboarding.yaml in root directory
# Usage: ./verify_github_access.sh [--debug] [<path_to_onboarding.yaml> ...]

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

# Check Python dependencies
check_python_dependencies

# Check for GitHub token
check_github_token

# Main execution
main() {
    local files_to_validate=()
    local overall_exit_code=0

    # Resolve the workspace root: prefer PATH_TO_WORKSPACE_REPO, fall back to PWD
    local workspace_root="${PATH_TO_WORKSPACE_REPO:-$PWD}"

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
                # don't exist on disk — running the full scan would check
                # unchanged services and could block the offboard PR.
                local deleted_files=()
                mapfile -t deleted_files < <(get_deleted_onboarding_files 2>/dev/null) || true

                if [ ${#deleted_files[@]} -gt 0 ]; then
                    echo -e "${BLUE}[INFO]${NC} PR contains only deletion(s) of onboarding file(s) — offboard scenario, skipping check"
                    for df in "${deleted_files[@]}"; do
                        echo -e "  ${YELLOW}🗑  $(basename "$df")${NC} — deleted / offboarded"
                    done
                    exit $overall_exit_code
                fi

                echo -e "${YELLOW}[WARNING]${NC} No changed or deleted files detected from git."
                echo -e "${BLUE}[INFO]${NC} Searching for all onboarding files in workspace..."
                mapfile -t files_to_validate < <(find_onboarding_files "$workspace_root")
            fi
        fi
    fi
    
    # Check if we have any files to validate
    if [ ${#files_to_validate[@]} -eq 0 ]; then
        echo -e "${YELLOW}[WARNING]${NC} No onboarding YAML files found to validate."
        echo -e "${BLUE}[INFO]${NC} Expected file pattern: <team-folder>/<repo-name>-onboarding.yaml"
        exit 0
    fi
    
    echo -e "${GREEN}[INFO]${NC} Found ${#files_to_validate[@]} file(s) to validate"
    echo ""
    
    # Validate each file
    for yaml_file in "${files_to_validate[@]}"; do
        if [ ! -f "$yaml_file" ]; then
            echo -e "${RED}[ERROR]${NC} File not found: $yaml_file"
            overall_exit_code=1
            continue
        fi
        
        run_validation_on_file "Verifying GitHub Access" "$yaml_file" "$SCRIPT_DIR/verify_github_access.py" "$DEBUG_FLAG"
        
        if [ $? -ne 0 ]; then
            overall_exit_code=1
        fi
    done
    
    # Print final summary
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [ $overall_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ All GitHub access verification checks passed${NC}"
    else
        echo -e "${RED}✗ Some GitHub access verification checks failed${NC}"
        show_documentation_link
    fi
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    exit $overall_exit_code
}

# Run main function
main "$@"
