#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Common utilities for onboarding YAML validation scripts
# This file contains shared functions used across all validation scripts

# Source one_pipeline_utils.sh so functions defined here (e.g. wait_for_pr_merge)
# can call detect_pr_phase() regardless of whether the caller sourced it.
# Guard against double-sourcing — bash re-executes source every time, but
# function redefinition is harmless; the real cost is the repeated file read.
if [[ -z "${_ONE_PIPELINE_UTILS_LOADED:-}" ]]; then
    source "${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh"
    export _ONE_PIPELINE_UTILS_LOADED=1
fi

# Color codes for terminal output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m'  # No Color

# Documentation URL
ONBOARDING_README_URL="https://github.ibm.com/genctl-cicd/uuc-service-cicd-onboarding/blob/main/README.md"

# Initialize debug flag
init_debug_flag() {
    # Check for debug mode from environment variable or command line flag
    DEBUG_FLAG=""
    
    # Check environment variable first (for IBM toolchain pipeline)
    if [[ "${enable_debug:-false}" == "true" ]] || [[ "${ENABLE_DEBUG:-false}" == "true" ]]; then
        DEBUG_FLAG="--debug"
        echo -e "${YELLOW}[DEBUG MODE ENABLED via environment variable]${NC}"
    fi
    
    # Command line flag overrides environment variable
    if [[ "$1" == "--debug" ]]; then
        DEBUG_FLAG="--debug"
        echo -e "${YELLOW}[DEBUG MODE ENABLED via command line flag]${NC}"
        return 1  # Signal that --debug was found and should be shifted
    fi
    
    return 0
}

# Check if Python is available
check_python_available() {
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} Python 3 is not installed. Please install Python 3 to run this validation script."
        exit 1
    fi
}

# Check if required Python packages are installed
check_python_dependencies() {
    python3 -c "import yaml" 2>/dev/null || {
        echo -e "${YELLOW}[WARNING]${NC} PyYAML not installed. Installing..."
        pip3 install --user PyYAML || {
            echo -e "${RED}[ERROR]${NC} Failed to install PyYAML. Please install it manually:"
            echo "  pip3 install PyYAML"
            exit 1
        }
    }
    
    python3 -c "import requests" 2>/dev/null || {
        echo -e "${YELLOW}[WARNING]${NC} requests not installed. Installing..."
        pip3 install --user requests || {
            echo -e "${RED}[ERROR]${NC} Failed to install requests. Please install it manually:"
            echo "  pip3 install requests"
            exit 1
        }
    }
}

# Check for GitHub token
check_github_token() {
    if [ -z "$GITHUB_TOKEN" ] && [ -z "$GHE_TOKEN" ] && [ -z "$GH_TOKEN" ]; then
        echo -e "${RED}[ERROR]${NC} GitHub token not found!"
        echo -e "${YELLOW}[INFO]${NC} Please set one of the following environment variables:"
        echo "  - GH_TOKEN     (preferred — used by gh CLI and detect_pr_phase)"
        echo "  - GITHUB_TOKEN"
        echo "  - GHE_TOKEN"
        echo ""
        echo "Example:"
        echo "  export GH_TOKEN='your_token_here'"
        echo "  $0 <path_to_onboarding.yaml>"
        exit 1
    fi
}

# Check for IBM Cloud API key (for COS bucket access)
check_ibm_cloud_api_key() {
    if [ -z "$IBM_CLOUD_COS_API_KEY" ]; then
        echo -e "${RED}[ERROR]${NC} IBM Cloud COS API key not found!"
        echo -e "${YELLOW}[INFO]${NC} Please set the following environment variable:"
        echo "  - IBM_CLOUD_COS_API_KEY"
        echo ""
        echo "Example:"
        echo "  export IBM_CLOUD_COS_API_KEY='your_api_key_here'"
        echo "  $0 <path_to_onboarding.yaml>"
        exit 1
    fi
}
# Function to display documentation reference
show_documentation_link() {
    echo "" >&2
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "${BLUE}📖 For detailed onboarding instructions, please refer to:${NC}" >&2
    echo -e "${CYAN}   ${ONBOARDING_README_URL}${NC}" >&2
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
}

# ---------------------------------------------------------------------------
# is_commons_file
#
# Returns 0 (true) when the given filename is the team commons file.
# The canonical name is "commons.yaml" — "commons.yml" is also accepted for
# robustness.  commons.yaml is NOT a service onboarding file and must be
# excluded from the regular onboarding-file lists while still being
# discoverable on its own when needed.
# ---------------------------------------------------------------------------
is_commons_file() {
    local file="$1"
    local filename
    filename=$(basename "$file")
    [[ "$filename" == "commons.yaml" ]] || [[ "$filename" == "commons.yml" ]]
}

# ---------------------------------------------------------------------------
# find_commons_file
#
# Locates the commons.yaml for the branch that owns $1 (a service onboarding
# file or any file in the branch root).  Searches the directory containing
# $1.  Prints the absolute path when found; prints nothing and returns 1 when
# not found.
# ---------------------------------------------------------------------------
find_commons_file() {
    local ref_file="$1"
    local search_dir
    search_dir="$(cd "$(dirname "$ref_file")" && pwd)"

    for name in commons.yaml commons.yml; do
        if [[ -f "${search_dir}/${name}" ]]; then
            echo "${search_dir}/${name}"
            return 0
        fi
    done
    return 1
}

# Function to check if file is a sample/reference file.
#
# In the per-team branch model onboarding files live at the branch root:
#   <team_slug>-onboarding.yaml   ← real file, must NOT be filtered
#   commons.yaml                  ← team commons file, must NOT be filtered as sample
#                                    but IS excluded from onboarding file lists
#   onboarding-minimal.yaml       ← profile-specific reference template, must be filtered
#   onboarding-ci_only.yaml       ← profile-specific reference template, must be filtered
#   onboarding-ci_cd.yaml         ← profile-specific reference template, must be filtered
#   onboarding-cd_only.yaml       ← profile-specific reference template, must be filtered
#
# A file is considered a sample when ANY of the following is true:
#   1. Its basename matches the profile-specific reference templates:
#        onboarding-minimal.yaml / .yml
#        onboarding-ci_only.yaml / .yml
#        onboarding-ci_cd.yaml   / .yml
#        onboarding-cd_only.yaml / .yml
#      These are platform-managed and must never be treated as real service files.
#   2. Its basename is exactly "onboarding.yaml" or "onboarding.yml"
#      (legacy bare template — kept for safety in case old branches still carry it).
#   3. Its path contains "sample", "example", "template", or "reference".
#   Note: commons.yaml is NOT classified as a sample — it is excluded from
#   onboarding file lists by the callers via is_commons_file().
is_sample_file() {
    local file="$1"
    local filename
    filename=$(basename "$file")

    # Rule 1: profile-specific reference templates (including cd_only)
    if [[ "$filename" == "onboarding-minimal.yaml" ]]  || \
       [[ "$filename" == "onboarding-minimal.yml" ]]   || \
       [[ "$filename" == "onboarding-ci_only.yaml" ]]  || \
       [[ "$filename" == "onboarding-ci_only.yml" ]]   || \
       [[ "$filename" == "onboarding-ci_cd.yaml" ]]    || \
       [[ "$filename" == "onboarding-ci_cd.yml" ]]     || \
       [[ "$filename" == "onboarding-cd_only.yaml" ]]  || \
       [[ "$filename" == "onboarding-cd_only.yml" ]]; then
        return 0  # It's a sample file
    fi

    # Rule 2: legacy bare onboarding.yaml / onboarding.yml with no prefix
    if [[ "$filename" == "onboarding.yaml" ]] || [[ "$filename" == "onboarding.yml" ]]; then
        return 0  # It's a sample file
    fi

    # Rule 3: path segment explicitly marks it as sample/example/template/reference
    if [[ "$file" =~ (sample|example|template|reference) ]]; then
        return 0  # It's a sample file
    fi

    return 1  # Not a sample file
}


# ---------------------------------------------------------------------------
# commons_changed_in_pr
#
# Returns 0 (true) when the current PR / merge diff contains a change to
# commons.yaml (or commons.yml).  Used by the PR step wrappers to decide
# whether to expand the validation scope to ALL onboarding files on the
# branch rather than only the directly-changed ones.
#
# Uses the same PR_BASEBRANCH / PR_HEADSHA / PIPELINE_TYPE / HEAD~1 logic
# as get_changed_files_from_git so the two functions stay in sync.
# ---------------------------------------------------------------------------
commons_changed_in_pr() {
    local original_dir="$PWD"

    if [ -n "$PATH_TO_WORKSPACE_REPO" ] && [ -d "$PATH_TO_WORKSPACE_REPO" ]; then
        cd "$PATH_TO_WORKSPACE_REPO" || return 1
    fi

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        cd "$original_dir"
        return 1
    fi

    local base_branch="" head_ref="HEAD" use_merge_diff=false

    if [ "${PIPELINE_TYPE}" = "merge" ]; then
        local scm_commit=""
        if [ -f "/trigger-payload/payload.json" ]; then
            scm_commit=$(jq -r '.after // empty' /trigger-payload/payload.json 2>/dev/null)
        fi
        if [ -z "$scm_commit" ]; then
            cd "$original_dir"; return 1
        fi
        git rev-parse HEAD~1 >/dev/null 2>&1 && use_merge_diff=true || { cd "$original_dir"; return 1; }
    elif [ -n "$PR_BASEBRANCH" ]; then
        base_branch="origin/$PR_BASEBRANCH"
        git fetch origin "$PR_BASEBRANCH" >/dev/null 2>&1 || true
        [ -n "$PR_HEADSHA" ] && head_ref="$PR_HEADSHA"
    else
        if git rev-parse HEAD~1 >/dev/null 2>&1; then
            use_merge_diff=true
        else
            cd "$original_dir"; return 1
        fi
    fi

    local found=false
    if [ "$use_merge_diff" = true ]; then
        git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -qE '^commons\.(yaml|yml)$' && found=true
    else
        git diff --name-only "${base_branch}...${head_ref}" 2>/dev/null | grep -qE '^commons\.(yaml|yml)$' && found=true
    fi

    cd "$original_dir"
    $found
}


# Function to get changed files from git
get_changed_files_from_git() {
    local changed_files=()
    local original_dir="$PWD"
    
    # Change to workspace repo directory if PATH_TO_WORKSPACE_REPO is set
    if [ -n "$PATH_TO_WORKSPACE_REPO" ] && [ -d "$PATH_TO_WORKSPACE_REPO" ]; then
        cd "$PATH_TO_WORKSPACE_REPO" || {
            echo -e "${RED}[ERROR]${NC} Failed to change to workspace directory: $PATH_TO_WORKSPACE_REPO" >&2
            return 1
        }
        echo -e "${BLUE}[INFO]${NC} Checking for changed files in: $PATH_TO_WORKSPACE_REPO" >&2
    fi
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        cd "$original_dir"
        return 1
    fi
    
    # Determine the base branch to compare against
    local base_branch=""
    local head_ref="HEAD"
    local use_merge_diff=false

    # In a merge pipeline HEAD is already on the target branch, so diffing
    # origin/<target-branch>...HEAD is always empty.  The correct comparison is
    # HEAD~1..HEAD — "what was just merged in".  Detect this case first.
    if [ "${PIPELINE_TYPE}" = "merge" ]; then
        # On a manual run /trigger-payload/payload.json is absent or has no .after field.
        # On a real SCM-triggered merge .after holds the merge commit SHA.
        # This mirrors the pattern used in dmm_deployment_with_smoke_only.sh.
        local scm_commit=""
        if [ -f "/trigger-payload/payload.json" ]; then
            scm_commit=$(jq -r '.after // empty' /trigger-payload/payload.json 2>/dev/null)
        fi

        if [ -z "$scm_commit" ]; then
            echo -e "${YELLOW}[WARNING]${NC} Merge pipeline triggered manually (no SCM payload) — skipping changed-file detection" >&2
            cd "$original_dir"
            printf ''
            return 0
        fi

        if git rev-parse HEAD~1 >/dev/null 2>&1; then
            echo -e "${BLUE}[INFO]${NC} Merge pipeline detected - using HEAD~1..HEAD diff" >&2
            use_merge_diff=true
        else
            echo -e "${YELLOW}[WARNING]${NC} Merge pipeline but HEAD~1 unavailable (shallow clone?)" >&2
            cd "$original_dir"
            return 1
        fi
    # In PR context, use PR_BASEBRANCH and PR_HEADSHA if available
    elif [ -n "$PR_BASEBRANCH" ]; then
        base_branch="origin/$PR_BASEBRANCH"
        echo -e "${BLUE}[INFO]${NC} PR detected - Base branch: $PR_BASEBRANCH" >&2
        
        # Fetch the base branch to ensure we have latest
        if git fetch origin "$PR_BASEBRANCH" >/dev/null 2>&1; then
            echo -e "${BLUE}[INFO]${NC} Fetched latest base branch from origin" >&2
        fi
        
        # Use PR_HEADSHA if available for more accurate comparison
        if [ -n "$PR_HEADSHA" ]; then
            head_ref="$PR_HEADSHA"
            echo -e "${BLUE}[INFO]${NC} Using PR HEAD SHA: $PR_HEADSHA" >&2
        fi
    else
        # No pipeline type or PR context — inspect the commit graph directly
        if git rev-parse HEAD~1 >/dev/null 2>&1 && [ "$(git rev-list --parents -n 1 HEAD | wc -w)" -gt 2 ]; then
            echo -e "${BLUE}[INFO]${NC} Merge commit detected - comparing HEAD~1 HEAD" >&2
            use_merge_diff=true
        elif git rev-parse HEAD~1 >/dev/null 2>&1; then
            echo -e "${BLUE}[INFO]${NC} Using HEAD~1..HEAD diff" >&2
            use_merge_diff=true
        else
            # Last resort: try common branch names (shallow clone with no parent)
            for branch in "origin/main" "origin/master" "main" "master"; do
                if git rev-parse --verify "$branch" > /dev/null 2>&1; then
                    base_branch="$branch"
                    break
                fi
            done
            
            if [ -z "$base_branch" ]; then
                echo -e "${YELLOW}[WARNING]${NC} Could not determine base branch" >&2
                cd "$original_dir"
                return 1
            fi
            echo -e "${BLUE}[INFO]${NC} Using detected base branch: $base_branch" >&2
        fi
    fi
    
    if [ "$use_merge_diff" = false ]; then
        echo -e "${BLUE}[INFO]${NC} Comparing $head_ref against $base_branch" >&2
    fi
    
    # Get the base directory for absolute paths
    local base_dir="$PWD"
    
    # Get changed YAML files matching onboarding pattern
    # Pattern: *-onboarding.yaml or *-onboarding.yml, excluding *-timed-onboarding.yaml|yml
    if [ "$use_merge_diff" = true ]; then
        # For merge commits, compare HEAD~1 HEAD to see what was just merged
        while IFS= read -r file; do
            if [[ "$file" =~ -onboarding\.(yaml|yml)$ ]] || [[ "$file" =~ /onboarding\.(yaml|yml)$ ]]; then
                if [[ "$file" =~ -timed-onboarding\.(yaml|yml)$ ]]; then
                    continue
                fi
                if [ -f "$file" ]; then
                    # Skip sample files in root directory
                    if ! is_sample_file "$file"; then
                        # Convert to absolute path
                        if [[ "$file" = /* ]]; then
                            changed_files+=("$file")
                        else
                            changed_files+=("$base_dir/$file")
                        fi
                    fi
                fi
            fi
        done < <(git diff --name-only HEAD~1 HEAD 2>/dev/null)
    else
        # For PR context, use three-dot diff
        while IFS= read -r file; do
            if [[ "$file" =~ -onboarding\.(yaml|yml)$ ]] || [[ "$file" =~ /onboarding\.(yaml|yml)$ ]]; then
                if [[ "$file" =~ -timed-onboarding\.(yaml|yml)$ ]]; then
                    continue
                fi
                if [ -f "$file" ]; then
                    # Skip sample files in root directory
                    if ! is_sample_file "$file"; then
                        # Convert to absolute path
                        if [[ "$file" = /* ]]; then
                            changed_files+=("$file")
                        else
                            changed_files+=("$base_dir/$file")
                        fi
                    fi
                fi
            fi
        done < <(git diff --name-only "$base_branch"..."$head_ref" 2>/dev/null)
    fi
    
    # Also check staged files
    while IFS= read -r file; do
        if [[ "$file" =~ -onboarding\.(yaml|yml)$ ]] || [[ "$file" =~ /onboarding\.(yaml|yml)$ ]]; then
            if [[ "$file" =~ -timed-onboarding\.(yaml|yml)$ ]]; then
                continue
            fi
            if [ -f "$file" ]; then
                if ! is_sample_file "$file"; then
                    # Convert to absolute path
                    local abs_path
                    if [[ "$file" = /* ]]; then
                        abs_path="$file"
                    else
                        abs_path="$base_dir/$file"
                    fi
                    
                    # Add only if not already in array
                    if [[ ! " ${changed_files[@]} " =~ " ${abs_path} " ]]; then
                        changed_files+=("$abs_path")
                    fi
                fi
            fi
        fi
    done < <(git diff --cached --name-only "$head_ref" 2>/dev/null)
    
    # Restore original directory
    cd "$original_dir"
    
    # Check if we found any changed files
    if [ ${#changed_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}[WARNING]${NC} No changed onboarding YAML files detected from git diff." >&2
        echo -e "${BLUE}[INFO]${NC} Git diff command used: git diff --name-only $base_branch...$head_ref" >&2
        return 1
    fi
    
    echo -e "${GREEN}[SUCCESS]${NC} Found ${#changed_files[@]} changed onboarding file(s) from git" >&2
    
    # Return the array
    printf '%s\n' "${changed_files[@]}"
}

# ---------------------------------------------------------------------------
# Function to return onboarding YAML files that were DELETED in the current
# PR / merge commit. Mirrors get_changed_files_from_git but uses
# --diff-filter=D and intentionally skips the [ -f ] existence check
# (the file is gone — that's the whole point).
# Returns absolute paths via stdout, one per line.
# ---------------------------------------------------------------------------
get_deleted_onboarding_files() {
    local deleted_files=()
    local original_dir="$PWD"

    if [ -n "$PATH_TO_WORKSPACE_REPO" ] && [ -d "$PATH_TO_WORKSPACE_REPO" ]; then
        cd "$PATH_TO_WORKSPACE_REPO" || {
            echo -e "${RED}[ERROR]${NC} Failed to change to workspace directory: $PATH_TO_WORKSPACE_REPO" >&2
            return 1
        }
    fi

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        cd "$original_dir"
        return 1
    fi

    local base_dir="$PWD"
    local base_branch="" head_ref="HEAD" use_merge_diff=false

    if [ "${PIPELINE_TYPE}" = "merge" ]; then
        # On a manual run /trigger-payload/payload.json is absent or has no .after field.
        # On a real SCM-triggered merge .after holds the merge commit SHA.
        local scm_commit=""
        if [ -f "/trigger-payload/payload.json" ]; then
            scm_commit=$(jq -r '.after // empty' /trigger-payload/payload.json 2>/dev/null)
        fi

        if [ -z "$scm_commit" ]; then
            cd "$original_dir"
            return 0  # manual trigger — no deletions to process
        fi

        # Merge pipeline: HEAD is already on the target branch.
        # HEAD~1..HEAD is the only correct comparison.
        if git rev-parse HEAD~1 >/dev/null 2>&1; then
            use_merge_diff=true
        else
            cd "$original_dir"
            return 0  # shallow clone, cannot determine deletions
        fi
    elif [ -n "$PR_BASEBRANCH" ]; then
        base_branch="origin/$PR_BASEBRANCH"
        git fetch origin "$PR_BASEBRANCH" >/dev/null 2>&1 || true
        [ -n "$PR_HEADSHA" ] && head_ref="$PR_HEADSHA"
    else
        if git rev-parse HEAD~1 >/dev/null 2>&1 && \
           [ "$(git rev-list --parents -n 1 HEAD | wc -w)" -gt 2 ]; then
            use_merge_diff=true
        elif git rev-parse HEAD~1 >/dev/null 2>&1; then
            use_merge_diff=true
        else
            for branch in "origin/main" "origin/master" "main" "master"; do
                if git rev-parse --verify "$branch" > /dev/null 2>&1; then
                    base_branch="$branch"; break
                fi
            done
        fi
    fi

    # Build the base git range string used by both diff commands below.
    local git_range
    if [ "$use_merge_diff" = true ]; then
        git_range="HEAD~1 HEAD"
    elif [ -n "$base_branch" ]; then
        git_range="${base_branch}...${head_ref}"
    else
        cd "$original_dir"
        return 0   # no base branch resolved — cannot determine deletions
    fi

    # Helper: emit the old-side path for a name-status line when it matches
    # the onboarding filename pattern and is not a sample file.
    # Called for both D (deleted) and R (renamed — old path is the source) lines.
    _emit_if_onboarding() {
        local file="$1"
        if [[ "$file" =~ -onboarding\.(yaml|yml)$ ]] || \
           [[ "$file" =~ /onboarding\.(yaml|yml)$ ]]; then
            if [[ "$file" =~ -timed-onboarding\.(yaml|yml)$ ]]; then
                return
            fi
            if ! is_sample_file "$file"; then
                if [[ "$file" = /* ]]; then
                    deleted_files+=("$file")
                else
                    deleted_files+=("$base_dir/$file")
                fi
            fi
        fi
    }

    # --diff-filter=DR: D = pure deletions, R = renames (git mv).
    # --name-status emits tab-separated lines:
    #   D <TAB> old-path
    #   R<score> <TAB> old-path <TAB> new-path
    # We always want the OLD path (the "gone" file) as the offboard target.
    while IFS=$'\t' read -r status old_path new_path; do
        case "$status" in
            D)   _emit_if_onboarding "$old_path" ;;
            R*)  _emit_if_onboarding "$old_path" ;;   # renamed — old path is the source
        esac
    done < <(git diff --name-status -M --diff-filter=DR $git_range 2>/dev/null)

    cd "$original_dir"

    if [ ${#deleted_files[@]} -gt 0 ]; then
        echo -e "${BLUE}[INFO]${NC} Found ${#deleted_files[@]} deleted onboarding file(s)" >&2
        printf '%s\n' "${deleted_files[@]}"
    fi
}

# Function to find all onboarding YAML files in a directory.
#
# Argument:
#   $1  search_dir — directory to scan (default: PATH_TO_WORKSPACE_REPO, then PWD)
#
# Filtering rules (applied in order):
#   1. find pattern "*-onboarding.yaml|yml" structurally excludes the profile-specific
#      reference templates (onboarding-minimal.yaml, onboarding-ci_only.yaml,
#      onboarding-ci_cd.yaml) at the find level — they don't end in "-onboarding.yaml".
#   2. is_sample_file() is a belt-and-suspenders guard that explicitly catches all
#      three profile templates, the legacy bare "onboarding.yaml", and any file under
#      a path containing "sample", "example", "template", or "reference".
find_onboarding_files() {
    # Resolve search directory: explicit arg > PATH_TO_WORKSPACE_REPO > PWD
    local search_dir
    if [ -n "${1:-}" ] && [ -d "${1}" ]; then
        search_dir="${1}"
    elif [ -n "${PATH_TO_WORKSPACE_REPO:-}" ] && [ -d "${PATH_TO_WORKSPACE_REPO}" ]; then
        search_dir="${PATH_TO_WORKSPACE_REPO}"
    else
        search_dir="$PWD"
    fi

    echo -e "${BLUE}[INFO]${NC} Searching for onboarding files in: ${search_dir}" >&2

    local files=()

    # Pattern "*-onboarding.yaml|yml" matches profile templates like
    # "onboarding-minimal.yaml" (since they end in -onboarding prefix pattern... they
    # don't — they're onboarding-<profile>.yaml). The find pattern here only matches
    # files ending in "-onboarding.yaml|yml", so the profile templates are structurally
    # excluded at the find level already. is_sample_file() is a belt-and-suspenders
    # guard that also handles legacy bare "onboarding.yaml" and path-based rules.
    while IFS= read -r file; do
        if [[ "$file" =~ -timed-onboarding\.(yaml|yml)$ ]]; then
            continue
        fi
        # commons.yaml is not a service onboarding file — exclude it here;
        # callers that need it use find_commons_file() instead.
        if is_commons_file "$file"; then
            continue
        fi
        if ! is_sample_file "$file"; then
            # Normalise to absolute path
            if [[ "$file" = /* ]]; then
                files+=("$file")
            else
                files+=("${search_dir}/${file}")
            fi
        fi
    done < <(find "${search_dir}" -maxdepth 1 -type f \
                \( -name "*-onboarding.yaml" -o -name "*-onboarding.yml" \) \
                ! -name "*-timed-onboarding.yaml" ! -name "*-timed-onboarding.yml" \
                2>/dev/null | sort)

    printf '%s\n' "${files[@]}"
}

# ---------------------------------------------------------------------------
# Function: get_all_files_from_branch
#
# Collects every *-onboarding.yaml|yml on the target branch inside
# PATH_TO_WORKSPACE_REPO, excluding all reference templates
# (onboarding-minimal.yaml, onboarding-ci_only.yaml, onboarding-ci_cd.yaml).
#
# Branch resolution order (first match wins):
#   1. ONBOARDING_BRANCH env var — explicit override, any branch name
#   2. Current branch of PATH_TO_WORKSPACE_REPO — this is the team-specific
#      branch the pipeline app repo is already checked out on when a cron
#      trigger fires against a team branch (e.g. dcms-onboarding).
#      Branch name format: <team-slug>-onboarding
#
# There is intentionally no hardcoded fallback: if neither source resolves
# to a branch the function fails loudly so the misconfiguration is visible.
#
# This is the entry-point used when PROCESS_ALL_FILES=true is set, which
# signals a cron / manual full-branch run rather than a per-merge diff run.
#
# The function does NOT restore the original branch on exit — the caller
# (a pipeline step running in an ephemeral container) does not need it.
#
# Returns absolute file paths via stdout, one per line.
# Exits non-zero if the branch cannot be resolved, checked out, or is empty.
# ---------------------------------------------------------------------------
get_all_files_from_branch() {
    # Resolve the onboarding repo directory using the first valid git repo found
    # in the following priority order:
    #
    #   1. ONBOARDING_REPO_PATH  — explicit override, set by the local test
    #                              harness; never set by the pipeline framework.
    #   2. PATH_TO_WORKSPACE_REPO — valid inside a pipeline container where
    #                              one_pipeline_utils.sh sets it correctly to
    #                              ${WORKSPACE}/${PIPELINE_REPO_NAME}.
    #                              Skipped locally when the framework is not
    #                              running and the path is not a git repo.
    #   3. PWD                   — last resort; covers local runs where neither
    #                              of the above resolves to a valid repo.
    local repo_dir=""

    if [ -n "${ONBOARDING_REPO_PATH:-}" ] && [ -d "${ONBOARDING_REPO_PATH}/.git" ]; then
        repo_dir="${ONBOARDING_REPO_PATH}"
        echo -e "${BLUE}[INFO]${NC} Using ONBOARDING_REPO_PATH: ${repo_dir}" >&2
    elif [ -n "${PATH_TO_WORKSPACE_REPO:-}" ] && [ -d "${PATH_TO_WORKSPACE_REPO}/.git" ]; then
        repo_dir="${PATH_TO_WORKSPACE_REPO}"
        echo -e "${BLUE}[INFO]${NC} Using PATH_TO_WORKSPACE_REPO: ${repo_dir}" >&2
    elif [ -d "${PWD}/.git" ]; then
        repo_dir="${PWD}"
        echo -e "${BLUE}[INFO]${NC} Using PWD as onboarding repo: ${repo_dir}" >&2
    else
        echo -e "${RED}[ERROR]${NC} Cannot find onboarding git repository." >&2
        echo -e "${RED}[ERROR]${NC} Run from inside the uuc-service-cicd-onboarding clone," >&2
        echo -e "${RED}[ERROR]${NC} or set ONBOARDING_REPO_PATH to its path." >&2
        return 1
    fi


    # Resolve target branch
    local target_branch=""

    if [ -n "${ONBOARDING_BRANCH:-}" ]; then
        # 1. Explicit override via env var
        target_branch="${ONBOARDING_BRANCH}"
        echo -e "${BLUE}[INFO]${NC} Using ONBOARDING_BRANCH env var: '${target_branch}'" >&2
    else
        # 2. Derive from the current branch of the workspace repo
        #    (e.g. dcms-onboarding, fabric-onboarding, etc.)
        target_branch=$(git -C "${repo_dir}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        if [ -z "$target_branch" ] || [ "$target_branch" = "HEAD" ]; then
            echo -e "${RED}[ERROR]${NC} Cannot determine onboarding branch." >&2
            echo -e "${RED}[ERROR]${NC} Set ONBOARDING_BRANCH env var to the team branch (e.g. dcms-onboarding)." >&2
            return 1
        fi
        echo -e "${BLUE}[INFO]${NC} Derived onboarding branch from repo HEAD: '${target_branch}'" >&2
    fi

    echo -e "${BLUE}[INFO]${NC} PROCESS_ALL_FILES=true — fetching all files from branch '${target_branch}'" >&2

    # SKIP_GIT_RESET=true bypasses the fetch + checkout + reset --hard so that
    # uncommitted local changes are preserved.  Intended for local testing only —
    # never set this in a pipeline environment.
    if [ "${SKIP_GIT_RESET:-false}" = "true" ]; then
        echo -e "${YELLOW}[WARNING]${NC} SKIP_GIT_RESET=true — skipping git reset, using current working tree as-is" >&2
    else
        (
            cd "${repo_dir}"
            git fetch origin "${target_branch}" >/dev/null 2>&1
            git checkout "${target_branch}"     >/dev/null 2>&1
            git reset --hard "origin/${target_branch}" >/dev/null 2>&1
        ) || {
            echo -e "${RED}[ERROR]${NC} Failed to checkout branch '${target_branch}' in ${repo_dir}" >&2
            return 1
        }
    fi

    local files=()
    while IFS= read -r file; do
        files+=("$file")
    done < <(find_onboarding_files "${repo_dir}")

    if [ ${#files[@]} -eq 0 ]; then
        echo -e "${YELLOW}[WARNING]${NC} No *-onboarding.yaml files found on branch '${target_branch}'" >&2
        return 1
    fi

    echo -e "${GREEN}[INFO]${NC} Found ${#files[@]} onboarding file(s) on branch '${target_branch}'" >&2
    printf '%s\n' "${files[@]}"
}

# Function to run validation on a single file with visual separators
run_validation_on_file() {
    local validation_type="$1"  # e.g., "Validating Mandatory Files", "Validating YAML Schema"
    local yaml_file="$2"
    local python_script="$3"
    local debug_flag="$4"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}▶ ${validation_type}: ${yaml_file}${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    python3 "$python_script" $debug_flag "$yaml_file"
    local result=$?
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    return $result
}

# ---------------------------------------------------------------------------
# Function: wait_for_pr_merge
#
# Polls the given PR every PR_POLL_INTERVAL_SECS seconds (default: 360) until
# it transitions to the MERGED state or the total wait time exceeds
# PR_MONITOR_TIMEOUT_MINS minutes (default: 60, configurable via env var).
#
# Uses detect_pr_phase() from one_pipeline_utils.sh to query PR state via the
# GitHub CLI so that authentication and URL parsing are handled uniformly.
#
# Exit codes:
#   0 — PR was merged within the timeout window
#   1 — PR was closed without merging, or timed out, or an error occurred
#
# Args:
#   $1  pr_html_url   — The browser URL of the PR (e.g. https://github.ibm.com/org/repo/pull/42)
#   $2  label         — Used only for log messages (e.g. team slug, toolchain name)
# ---------------------------------------------------------------------------
wait_for_pr_merge() {
    local pr_html_url="$1"
    local label="$2"

    # Convert a browser PR URL (https://github.ibm.com/org/repo/pull/42)
    # into the API URL format expected by detect_pr_phase()
    # (https://github.ibm.com/api/v3/repos/org/repo/pulls/42)
    local pr_api_url
    pr_api_url=$(echo "$pr_html_url" | \
        sed -E 's|https://([^/]+)/([^/]+)/([^/]+)/pull/([0-9]+).*|https://\1/api/v3/repos/\2/\3/pulls/\4|')

    if [ -z "$pr_api_url" ] || [ "$pr_api_url" = "$pr_html_url" ]; then
        echo -e "${RED}[ERROR]${NC} Could not derive API URL from PR HTML URL: ${pr_html_url}"
        return 1
    fi

    # Configurable timeout (minutes) and poll interval (seconds)
    local timeout_mins="${PR_MONITOR_TIMEOUT_MINS:-120}"
    local poll_interval_secs="${PR_POLL_INTERVAL_SECS:-60}"

    local max_iterations=$(( (timeout_mins * 60) / poll_interval_secs ))
    local elapsed_mins=0
    local iteration=0

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}[INFO]${NC} Monitoring PR merge status for: ${GREEN}${label}${NC}"
    echo -e "${BLUE}[INFO]${NC} PR URL    : ${CYAN}${pr_html_url}${NC}"
    echo -e "${BLUE}[INFO]${NC} Timeout   : ${timeout_mins} minutes"
    echo -e "${BLUE}[INFO]${NC} Poll every: ${poll_interval_secs} seconds"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    while [ $iteration -lt $max_iterations ]; do
        iteration=$(( iteration + 1 ))
        elapsed_mins=$(( (iteration - 1) * poll_interval_secs / 60 ))

        echo -e "${BLUE}[INFO]${NC} [${label}] Poll #${iteration}/${max_iterations} — elapsed ~${elapsed_mins}m — checking PR state..."

        # detect_pr_phase sets PR_PHASE to: pre-merge | post-merge | closed
        # It also handles gh auth login internally.
        if ! detect_pr_phase "$pr_api_url"; then
            echo -e "${YELLOW}[WARNING]${NC} [${label}] detect_pr_phase returned an error on poll #${iteration} — will retry next cycle"
        else
            case "${PR_PHASE}" in
                post-merge)
                    echo -e "${GREEN}[SUCCESS]${NC} [${label}] PR has been MERGED! ✅"
                    echo -e "${BLUE}[INFO]${NC} Total wait time: ~${elapsed_mins} minutes"
                    return 0
                    ;;
                closed)
                    echo -e "${RED}[ERROR]${NC} [${label}] PR was CLOSED without merging."
                    return 1
                    ;;
                pre-merge)
                    echo -e "${BLUE}[INFO]${NC} [${label}] PR is still OPEN — waiting ${poll_interval_secs}s before next check..."
                    ;;
                *)
                    echo -e "${YELLOW}[WARNING]${NC} [${label}] Unexpected PR_PHASE='${PR_PHASE}' — will retry"
                    ;;
            esac
        fi

        # Only sleep when there are more iterations remaining
        if [ $iteration -lt $max_iterations ]; then
            sleep "$poll_interval_secs"
        fi
    done

    echo -e "${RED}[ERROR]${NC} [${label}] Timed out after ${timeout_mins} minutes waiting for PR to be merged."
    echo -e "${YELLOW}[INFO]${NC} PR URL: ${pr_html_url}"
    echo -e "${YELLOW}[INFO]${NC} Please merge or close the PR manually."
    return 1
}

# ---------------------------------------------------------------------------
# Function: wait_for_merge_pipeline
#
# After an infra PR is merged, reads the "#### Merge Pipeline Summary ####"
# comment posted by setup.sh from the merged PR and polls the Tekton CD API
# until the triggered merge pipeline run reaches a terminal state.
#
# How it works:
#   1. Scan PR comments for the sentinel "#### Merge Pipeline Summary ####"
#      using gh api (gh CLI) — no manual token header required
#   2. Extract "#### pipeline_url:" from that comment
#   3. Derive BASE_URL / PIPELINE_ID / PIPELINE_RUN_ID from the URL
#   4. Delegate polling to wait_until_pipeline_run_finished() from
#      tekton_api_utils.sh — called in a subshell to contain its exit 1 calls
#   5. Do one final status query to distinguish succeeded from failed/cancelled
#      (this step still uses curl — it targets the IBM Cloud Tekton API, not GitHub)
#
# Reusable for any toolchain provisioning flow (ops CI, ops CD, etc.) that
# merges a PR and needs to verify the resulting merge pipeline completed.
#
# Args:
#   $1  pr_html_url  — browser URL of the merged PR
#   $2  pr_number    — PR number (used to fetch comments via gh CLI)
#   $3  label        — used only for log messages (e.g. team slug, toolchain name)
#
# Env vars (all optional, have defaults):
#   GH_TOKEN                          — GitHub token used by gh CLI (set GH_HOST for GHE)
#   MERGE_PIPELINE_TIMEOUT_MINS       — max wait time in minutes       (default: 360)
#   MERGE_PIPELINE_POLL_INTERVAL_SECS — seconds between Tekton polls   (default: 60)
#
# Exit codes:
#   0 — merge pipeline succeeded
#   1 — merge pipeline failed/cancelled/errored, timed out, or comment not found
# ---------------------------------------------------------------------------
wait_for_merge_pipeline() {
    local pr_html_url="$1"
    local pr_number="$2"
    local label="$3"

    # Configurable timeouts — separate from the PR merge monitor
    local timeout_mins="${MERGE_PIPELINE_TIMEOUT_MINS:-360}"
    local poll_interval_secs="${MERGE_PIPELINE_POLL_INTERVAL_SECS:-60}"
    local max_attempts=$(( (timeout_mins * 60) / poll_interval_secs ))

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}[INFO]${NC} Waiting for merge pipeline to complete for: ${GREEN}${label}${NC}"
    echo -e "${BLUE}[INFO]${NC} PR URL    : ${CYAN}${pr_html_url}${NC}"
    echo -e "${BLUE}[INFO]${NC} Timeout   : ${timeout_mins} minutes"
    echo -e "${BLUE}[INFO]${NC} Poll every: ${poll_interval_secs} seconds"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # ── Step 1: find the pipeline_url in PR comments ─────────────────────────
    # Derive the repo path and GHE hostname from the PR browser URL:
    #   https://github.ibm.com/org/repo/pull/42 → org/repo, github.ibm.com
    local repo_path gh_hostname
    repo_path=$(echo "$pr_html_url"  | sed -E 's|https://[^/]+/([^/]+/[^/]+)/pull/.*|\1|')
    gh_hostname=$(echo "$pr_html_url" | sed -E 's|https://([^/]+)/.*|\1|')

    # gh api path: /repos/<org>/<repo>/issues/<pr>/comments
    local gh_api_path="/repos/${repo_path}/issues/${pr_number}/comments"

    echo -e "${BLUE}[INFO]${NC} [${label}] Fetching PR #${pr_number} comments via gh CLI to locate merge pipeline URL..."

    # Poll for the comment — setup.sh posts it at pipeline start, so it may
    # not be present yet if we arrive here very quickly after the merge.
    local comment_poll_max=60
    local comment_poll_count=0
    local pipeline_run_url=""

    while [ $comment_poll_count -lt $comment_poll_max ]; do
        comment_poll_count=$(( comment_poll_count + 1 ))

        local comments_json
        comments_json=$(GH_HOST="${gh_hostname}" gh api \
            -H "Accept: application/vnd.github.v3+json" \
            "${gh_api_path}?per_page=100")

        # Find the LATEST comment containing the sentinel and extract pipeline_url.
        # GitHub returns comments in ascending created_at order, so the last element
        # from jq is the most recent summary comment.  Using `tail -1` (not head -1)
        # prevents stale run URLs from a previous pipeline execution on the same PR
        # from being picked up when multiple "Merge Pipeline Summary" comments exist.
        pipeline_run_url=$(echo "$comments_json" \
            | jq -r '[.[] | select(.body | contains("#### Merge Pipeline Summary ####"))] | last | .body' \
            | grep "#### pipeline_url:" \
            | tail -1 \
            | sed 's/.*#### pipeline_url:[[:space:]]*//')

        if [ -n "$pipeline_run_url" ] && [ "$pipeline_run_url" != "null" ]; then
            echo -e "${GREEN}[SUCCESS]${NC} [${label}] Found merge pipeline URL: ${CYAN}${pipeline_run_url}${NC}"
            break
        fi

        echo -e "${BLUE}[INFO]${NC} [${label}] Merge pipeline comment not found yet — attempt ${comment_poll_count}/${comment_poll_max}, retrying in 30s..."
        sleep 30
    done

    if [ -z "$pipeline_run_url" ]; then
        echo -e "${RED}[ERROR]${NC} [${label}] Could not find '#### Merge Pipeline Summary ####' comment on PR #${pr_number} after ${comment_poll_max} attempts."
        return 1
    fi

    # ── Step 2: parse BASE_URL, PIPELINE_ID, PIPELINE_RUN_ID from URL ────────
    # URL shape: https://cloud.ibm.com/devops/pipelines/tekton/<PIPELINE_ID>/runs/<RUN_ID>
    # ENDPOINT pattern used across all trigger_subpipeline*.sh:
    #   ENDPOINT=$(echo "${url##*ibm:}" | cut -d':' -f2)  → e.g. "us-south"
    local endpoint pipeline_id pipeline_run_id base_url
    endpoint=$(echo "${pipeline_run_url##*ibm:}" | cut -d':' -f2)
    base_url="api.${endpoint}.devops.cloud.ibm.com"
    pipeline_id=$(echo "$pipeline_run_url"     | grep -oP '(?<=/pipelines/tekton/)[^/?]+')
    pipeline_run_id=$(echo "$pipeline_run_url" | grep -oP '(?<=/runs/)[^/?]+')

    if [ -z "$pipeline_id" ] || [ -z "$pipeline_run_id" ]; then
        echo -e "${RED}[ERROR]${NC} [${label}] Could not parse pipeline_id or pipeline_run_id from URL: ${pipeline_run_url}"
        return 1
    fi

    echo -e "${BLUE}[INFO]${NC} [${label}] Pipeline ID : ${pipeline_id}"
    echo -e "${BLUE}[INFO]${NC} [${label}] Run ID      : ${pipeline_run_id}"
    echo -e "${BLUE}[INFO]${NC} [${label}] API base    : ${base_url}"

    # ── Steps 3+4: wait until terminal state using existing utility ───────────
    # wait_until_pipeline_run_finished() handles IAM token generation/refresh
    # and the polling loop. It calls `exit 1` on timeout/error so we run it
    # in a subshell to prevent it from killing the parent process.
    source "${PATH_TO_GENCTL_CI}/onepipeline/utils/tekton_api_utils.sh"

    echo -e "${BLUE}[INFO]${NC} [${label}] Delegating polling to wait_until_pipeline_run_finished (max ${max_attempts} attempts, ${poll_interval_secs}s interval)..."
    (
        wait_until_pipeline_run_finished \
            "${base_url}" "${pipeline_id}" "${pipeline_run_id}" \
            "${max_attempts}" "${poll_interval_secs}"
    )
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} [${label}] Timed out or failed waiting for merge pipeline. See: ${CYAN}${pipeline_run_url}${NC}"
        return 1
    fi

    # ── Step 5: query final status to distinguish succeeded from failed ───────
    # wait_until_pipeline_run_finished breaks on ANY terminal state — we need
    # to know which one. Re-source iam_utils to ensure a fresh token.
    source "${PATH_TO_GENCTL_CI}/onepipeline/utils/iam_utils.sh"
    local final_status
    final_status=$(curl -s -X GET \
        --header "Authorization: Bearer ${IAM_ACCESS_TOKEN}" \
        --header "Accept: application/json" \
        "https://${base_url}/pipeline/v2/tekton_pipelines/${pipeline_id}/pipeline_runs/${pipeline_run_id}?includes=definitions" \
        | jq -r '.status // empty')

    echo -e "${BLUE}[INFO]${NC} [${label}] Final pipeline status: ${final_status}"

    case "${final_status}" in
        succeeded)
            echo -e "${GREEN}[SUCCESS]${NC} [${label}] Merge pipeline completed successfully! ✅"
            return 0
            ;;
        failed|error|cancelled)
            echo -e "${RED}[ERROR]${NC} [${label}] Merge pipeline ended with status: ${final_status}. See: ${CYAN}${pipeline_run_url}${NC}"
            return 1
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} [${label}] Unexpected final status '${final_status}'. See: ${CYAN}${pipeline_run_url}${NC}"
            return 1
            ;;
    esac
}

# ===========================================================================
# Environment-code YAML helpers
# ---------------------------------------------------------------------------
# These three variables are the single source of truth for the env-code YAML
# URLs used by:
#   - provision_team_cd_toolchains.sh   (CD trigger generation)
#   - provision_team_infrastructure.sh  (zonal/regional secret expansion)
#   - add_update_secrets.sh             (future use)
#
# Override any of them before sourcing this file or export them from the
# calling script/pipeline to point at a different revision or mirror.
#
# Local-file fallbacks (DCMS_ENV_CODE_YAML_LOCAL / UNDERCLOUD_ENV_CODE_YAML_LOCAL)
# take precedence when set and the file exists — used for air-gapped runners or
# local development without hitting GitHub.
# ===========================================================================
# Use the GHE Contents API URL instead of the browser blob URL.
# The blob/raw web URLs on GHE return HTML for authenticated requests that
# supply an Authorization header (GHE redirects to login); the Contents API
# with Accept: application/vnd.github.v3.raw returns the raw file bytes.
: "${DCMS_ENV_CODE_YAML_URL:=https://github.ibm.com/api/v3/repos/ibmcloud/iaas-architecture/contents/configuration/dcms_environment_code.yaml?ref=main}"
: "${UNDERCLOUD_ENV_CODE_YAML_URL:=https://github.ibm.com/api/v3/repos/ibmcloud/iaas-architecture/contents/configuration/undercloud_environment_code.yaml?ref=main}"
: "${DCMS_ENV_CODE_YAML_LOCAL:=}"
: "${UNDERCLOUD_ENV_CODE_YAML_LOCAL:=}"

# ---------------------------------------------------------------------------
# resolve_env_code_yaml
#
# Prints the source (local path or URL) for the correct environment-code YAML
# for the given team slug.
#
#   team_slug = "dcms"  → dcms_environment_code.yaml
#   everything else     → undercloud_environment_code.yaml
#
# Resolution order:
#   1. *_ENV_CODE_YAML_LOCAL  if set and the file exists  (local override)
#   2. *_ENV_CODE_YAML_URL    (GitHub raw URL — downloaded at runtime)
#
# Usage:
#   env_yaml=$(resolve_env_code_yaml "$team_slug")
# ---------------------------------------------------------------------------
resolve_env_code_yaml() {
    local team_slug="$1"

    if [ "$team_slug" = "dcms" ]; then
        if [ -n "$DCMS_ENV_CODE_YAML_LOCAL" ] && [ -f "$DCMS_ENV_CODE_YAML_LOCAL" ]; then
            echo "$DCMS_ENV_CODE_YAML_LOCAL"
        else
            echo "$DCMS_ENV_CODE_YAML_URL"
        fi
    else
        if [ -n "$UNDERCLOUD_ENV_CODE_YAML_LOCAL" ] && [ -f "$UNDERCLOUD_ENV_CODE_YAML_LOCAL" ]; then
            echo "$UNDERCLOUD_ENV_CODE_YAML_LOCAL"
        else
            echo "$UNDERCLOUD_ENV_CODE_YAML_URL"
        fi
    fi
}
