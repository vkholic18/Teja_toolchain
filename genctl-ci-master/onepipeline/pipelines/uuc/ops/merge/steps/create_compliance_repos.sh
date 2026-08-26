#!/bin/bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Compliance Repository Creation Script
# This script runs in the merge pipeline of uuc-service-cicd-onboarding repo
# It creates inventory and incident repositories when create: true in onboarding.yaml

set -e  # Exit on error

# Source common utilities
source "${PATH_TO_GENCTL_CI}/onepipeline/utils/onboarding_validation_utils.sh"

# Configuration
GH_HOSTNAME="github.ibm.com"

# Template repository to fork for inventory repos
INVENTORY_TEMPLATE_OWNER="one-pipeline"
INVENTORY_TEMPLATE_REPO="compliance-inventory"

# Initialize
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📦 UUC Compliance Repository Creation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check prerequisites
check_python_available
check_python_dependencies
check_github_token

# Authenticate gh CLI once up-front using GH_TOKEN (set by check_github_token caller)
# detect_pr_phase (in one_pipeline_utils.sh) does the same — guard against double-login.
if ! gh auth status --hostname "${GH_HOSTNAME}" >/dev/null 2>&1; then
    gh auth login --hostname "${GH_HOSTNAME}" --with-token <<< "${GH_TOKEN}"
fi

# Function to extract repository info from onboarding file.
# Both inventory_repo and incident_repo must have a repo URL even when
# create: true — the org and repo name are derived from that URL.
extract_repo_info() {
    local onboarding_file="$1"

    if [ ! -f "$onboarding_file" ]; then
        echo -e "${RED}[ERROR]${NC} Onboarding file not found: $onboarding_file"
        return 1
    fi

    python3 - <<EOF
import yaml, sys, os
from pathlib import Path
from urllib.parse import urlparse

try:
    with open('$onboarding_file', 'r') as f:
        config = yaml.safe_load(f)

    # Load commons.yaml — team-level fields (team_name, FID usernames) live there
    _loader_paths = [
        str(Path(os.environ.get('PATH_TO_GENCTL_CI', '')) / 'onepipeline' / 'utils'),
    ]
    for _p in _loader_paths:
        if _p not in sys.path and os.path.isfile(os.path.join(_p, 'commons_loader.py')):
            sys.path.insert(0, _p)
            break
    from commons_loader import load_commons, CommonsNotFoundError
    try:
        commons = load_commons('$onboarding_file')
    except CommonsNotFoundError as _e:
        print(f"ERROR: {_e}", file=sys.stderr)
        sys.exit(1)

    team_name    = commons.get('team_name', '')
    service_name = config.get('service_name', '')

    # Extract service FID GitHub usernames — now in commons.yaml
    service_fid_dev_github_username  = commons.get('service_fid_dev_github_username', '')
    service_fid_prod_github_username = commons.get('service_fid_prod_github_username', '')

    # Extract inventory repo info
    inventory_repo   = config.get('inventory_repo', {}) or {}
    inventory_url    = inventory_repo.get('repo', '')
    inventory_branch = inventory_repo.get('branch', 'main')
    inventory_create = inventory_repo.get('create', False)

    # Extract incident repo info
    incident_repo   = config.get('incident_repo', {}) or {}
    incident_url    = incident_repo.get('repo', '')
    incident_branch = incident_repo.get('branch', 'main')
    incident_create = incident_repo.get('create', False)

    def parse_org_and_name(url):
        """Return (org, repo_name) from a github.ibm.com URL, or ('', '') if blank."""
        if not url:
            return '', ''
        parts = urlparse(url).path.strip('/').split('/')
        if len(parts) < 2:
            return '', parts[-1] if parts else ''
        return parts[-2], parts[-1]

    inventory_org,  inventory_name  = parse_org_and_name(inventory_url)
    incident_org,   incident_name   = parse_org_and_name(incident_url)

    # Validate: if create is requested the URL (and therefore org+name) must be present
    if str(inventory_create).lower() == 'true' and not inventory_url:
        print("ERROR: inventory_repo.create is true but inventory_repo.repo URL is not set", file=sys.stderr)
        sys.exit(1)
    if str(incident_create).lower() == 'true' and not incident_url:
        print("ERROR: incident_repo.create is true but incident_repo.repo URL is not set", file=sys.stderr)
        sys.exit(1)

    # Output format (pipe-separated):
    # team_name|service_name
    # |inventory_org|inventory_name|inventory_branch|inventory_create
    # |incident_org|incident_name|incident_branch|incident_create
    # |service_fid_dev_github_username|service_fid_prod_github_username
    print(f"{team_name}|{service_name}"
          f"|{inventory_org}|{inventory_name}|{inventory_branch}|{inventory_create}"
          f"|{incident_org}|{incident_name}|{incident_branch}|{incident_create}"
          f"|{service_fid_dev_github_username}|{service_fid_prod_github_username}")

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# Function to check if repository exists in a given org.
# Uses: gh api GET /repos/{org}/{repo} — exits 0 on 200, non-zero otherwise.
repo_exists() {
    local org="$1"
    local repo_name="$2"

    GH_HOST="${GH_HOSTNAME}" gh api "repos/${org}/${repo_name}" \
        --silent >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Fork the compliance-inventory template into the team's org and rename it.
#
# The GHE fork API always names the fork after the source repo
# ("compliance-inventory"), so we immediately rename it to the desired name.
#
# Usage: fork_inventory_repo <target-org> <desired-repo-name> <description>
# Prints the html_url of the resulting repo on success.
# ---------------------------------------------------------------------------
fork_inventory_repo() {
    local target_org="$1"
    local repo_name="$2"
    local description="$3"

    echo -e "${BLUE}[INFO]${NC} Forking ${INVENTORY_TEMPLATE_OWNER}/${INVENTORY_TEMPLATE_REPO} → ${target_org}/${repo_name}"

    # The GHE fork API always names the fork after the source repo
    # ("compliance-inventory"). If that intermediate name already exists in the
    # target org from a previous run, skip the fork call and go straight to rename.
    local fork_name="${INVENTORY_TEMPLATE_REPO}"
    local fork_url

    if repo_exists "${target_org}" "${fork_name}"; then
        echo -e "${YELLOW}[WARNING]${NC} Intermediate fork ${target_org}/${fork_name} already exists — skipping fork, proceeding to rename"
        fork_url="https://${GH_HOSTNAME}/${target_org}/${fork_name}"
    else
        # Step 1: Fork into the team's org
        local fork_response error_message
        fork_response=$(GH_HOST="${GH_HOSTNAME}" gh api \
            --method POST \
            "repos/${INVENTORY_TEMPLATE_OWNER}/${INVENTORY_TEMPLATE_REPO}/forks" \
            --field organization="${target_org}")

        fork_name=$(echo "$fork_response"     | jq -r '.name      // empty')
        fork_url=$(echo "$fork_response"      | jq -r '.html_url  // empty')
        error_message=$(echo "$fork_response" | jq -r '.message   // empty')

        if [ -z "$fork_name" ] || [ "$fork_name" = "null" ]; then
            echo -e "${RED}[ERROR]${NC} Failed to fork ${INVENTORY_TEMPLATE_OWNER}/${INVENTORY_TEMPLATE_REPO}: ${error_message}"
            return 1
        fi
    fi

    echo -e "${BLUE}[INFO]${NC} Fork present as ${target_org}/${fork_name}"

    # Step 2: Rename to the desired name (if different from the template name)
    if [ "$fork_name" != "$repo_name" ]; then
        echo -e "${BLUE}[INFO]${NC} Renaming ${fork_name} → ${repo_name}"

        local rename_response renamed_url rename_error
        rename_response=$(GH_HOST="${GH_HOSTNAME}" gh api \
            --method PATCH \
            "repos/${target_org}/${fork_name}" \
            --field name="${repo_name}" \
            --field description="${description}")

        renamed_url=$(echo "$rename_response" | jq -r '.html_url // empty')
        rename_error=$(echo "$rename_response" | jq -r '.message  // empty')

        if [ -z "$renamed_url" ] || [ "$renamed_url" = "null" ]; then
            echo -e "${RED}[ERROR]${NC} Fork was created but rename failed: ${rename_error}"
            echo -e "${YELLOW}[WARNING]${NC} Repository exists as ${target_org}/${fork_name} — please rename manually"
            echo "$fork_url"
            return 1
        fi

        echo -e "${GREEN}[SUCCESS]${NC} Inventory repository forked and renamed: ${renamed_url}"
        echo "$renamed_url"
    else
        # No rename needed — just patch the description
        GH_HOST="${GH_HOSTNAME}" gh api \
            --method PATCH \
            "repos/${target_org}/${fork_name}" \
            --field description="${description}" \
            --silent >/dev/null

        echo -e "${GREEN}[SUCCESS]${NC} Inventory repository forked: ${fork_url}"
        echo "$fork_url"
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Verify that a user has the required permission on a repository.
#
# IMPORTANT: Access in this environment is governed by Access Hub. Do NOT use
# direct GitHub API calls to grant access — those changes will be reverted by
# the Access Hub reconciliation job. All access must be requested through the
# Access Hub approval process.
#
# This function only checks; it never grants.
# Usage: verify_repo_permission <org> <repo-name> <username> <required-permission>
# Returns 0 if verified, 1 if the permission is insufficient or cannot be determined.
# ---------------------------------------------------------------------------
verify_repo_permission() {
    local org="$1"
    local repo_name="$2"
    local username="$3"
    local required_permission="$4"

    if [ -z "$username" ]; then
        return 0  # Nothing to verify
    fi

    echo -e "${BLUE}[INFO]${NC} Verifying '${required_permission}' access on ${org}/${repo_name} for ${username}..."

    local actual_permission
    actual_permission=$(GH_HOST="${GH_HOSTNAME}" gh api \
        "repos/${org}/${repo_name}/collaborators/${username}/permission" \
        --jq '.permission' 2>/dev/null)

    # Map required permission to the set of acceptable values
    local acceptable=false
    case "$required_permission" in
        admin)  [ "$actual_permission" = "admin" ]                                            && acceptable=true ;;
        write)  [ "$actual_permission" = "admin" ] || [ "$actual_permission" = "write" ]      && acceptable=true ;;
        read)   [ "$actual_permission" = "admin" ] || [ "$actual_permission" = "write" ] \
             || [ "$actual_permission" = "read" ]                                             && acceptable=true ;;
    esac

    if [ "$acceptable" = "true" ]; then
        echo -e "${GREEN}[SUCCESS]${NC} Verified: ${username} has '${actual_permission}' access on ${org}/${repo_name}"
        return 0
    else
        echo -e "${RED}[ERROR]${NC} Access check FAILED: ${username} has '${actual_permission:-none}' access on ${org}/${repo_name} — '${required_permission}' is required"
        echo -e "${RED}[ERROR]${NC} Request '${required_permission}' access via Access Hub for ${username} on ${org}/${repo_name}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Create a plain GitHub repository in the team's org (used for incident repos).
# Usage: create_github_repo <target-org> <repo-name> <description> <private: true|false>
# ---------------------------------------------------------------------------
create_github_repo() {
    local target_org="$1"
    local repo_name="$2"
    local description="$3"
    local is_private="$4"

    echo -e "${BLUE}[INFO]${NC} Creating repository: ${target_org}/${repo_name}"

    local response
    response=$(GH_HOST="${GH_HOSTNAME}" gh api \
        --method POST \
        "orgs/${target_org}/repos" \
        --field name="${repo_name}" \
        --field description="${description}" \
        --field private="${is_private}" \
        --field auto_init=false)

    local repo_url error_message
    repo_url=$(echo "$response"      | jq -r '.html_url // empty')
    error_message=$(echo "$response" | jq -r '.message  // empty')

    if [ -n "$repo_url" ] && [ "$repo_url" != "null" ]; then
        echo -e "${GREEN}[SUCCESS]${NC} Repository created: ${repo_url}"
        echo "$repo_url"
        return 0
    else
        echo -e "${RED}[ERROR]${NC} Failed to create repository: ${error_message}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Create a README.md in an empty repository.
# Used to initialise incident repos with a single commit on the default branch.
# Usage: create_readme <target-org> <repo-name> <branch>
# ---------------------------------------------------------------------------
create_readme() {
    local target_org="$1"
    local repo_name="$2"
    local branch="$3"

    echo -e "${BLUE}[INFO]${NC} Creating README.md in ${target_org}/${repo_name}"

    # README contains just the repo name as an H1
    local encoded_content
    encoded_content=$(printf '# %s\n' "$repo_name" | base64)

    local response commit_sha
    response=$(GH_HOST="${GH_HOSTNAME}" gh api \
        --method PUT \
        "repos/${target_org}/${repo_name}/contents/README.md" \
        --field message="docs: Initialize repository with README" \
        --field content="${encoded_content}" \
        --field branch="${branch}")

    commit_sha=$(echo "$response" | jq -r '.commit.sha // empty')

    if [ -n "$commit_sha" ] && [ "$commit_sha" != "null" ]; then
        echo -e "${GREEN}[SUCCESS]${NC} README.md created (commit: ${commit_sha:0:8})"
        return 0
    else
        local err
        err=$(echo "$response" | jq -r '.message // empty')
        echo -e "${RED}[ERROR]${NC} Failed to create README.md: ${err}"
        return 1
    fi
}

# Main execution
main() {
    local exit_code=0
    local changed_files=()
    local created_repos=()

    # ── PROCESS_ALL_FILES mode (cron / manual full-branch run) ────────────────
    # When PROCESS_ALL_FILES=true the script checks out ONBOARDING_BRANCH and
    # processes every *-onboarding.yaml on it instead of using git-diff.
    # Set via toolchain env property; ONBOARDING_BRANCH defaults to team-onboarding.
    if [[ "${PROCESS_ALL_FILES:-false}" == "true" ]]; then
        mapfile -t changed_files < <(get_all_files_from_branch)
    else
        # Get changed onboarding files
        echo -e "${BLUE}[INFO]${NC} Detecting changed onboarding files..."
        mapfile -t changed_files < <(get_changed_files_from_git)
    fi

    if [ ${#changed_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}[WARNING]${NC} No onboarding files changed in this merge"
        echo -e "${BLUE}[INFO]${NC} Skipping repository creation"
        exit 0
    fi
    
    echo -e "${GREEN}[INFO]${NC} Found ${#changed_files[@]} changed onboarding file(s)"
    for file in "${changed_files[@]}"; do
        echo -e "  - ${file}"
    done
    echo ""
    
    # Process each changed file
    for onboarding_file in "${changed_files[@]}"; do
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        # Get absolute path
        if [[ "$onboarding_file" != /* ]]; then
            if [ -n "$PATH_TO_WORKSPACE_REPO" ]; then
                onboarding_file="${PATH_TO_WORKSPACE_REPO}/${onboarding_file}"
            else
                onboarding_file="$(pwd)/${onboarding_file}"
            fi
        fi
        
        # Extract repository info
        repo_info=$(extract_repo_info "$onboarding_file")
        if [ $? -ne 0 ]; then
            echo -e "${RED}[ERROR]${NC} Failed to extract repository info from: $onboarding_file"
            exit_code=1
            continue
        fi
        
        # Parse repo info (org now included for both repos)
        IFS='|' read -r team_name service_name \
            inventory_org inventory_name inventory_branch inventory_create \
            incident_org  incident_name  incident_branch  incident_create \
            service_fid_dev_github_username service_fid_prod_github_username \
            <<< "$repo_info"
        
        echo -e "${BLUE}[INFO]${NC} Processing service: ${GREEN}${service_name}${NC} (${team_name} team)"

        # Skip compliance repo creation for 'minimal' profile — no inventory or incident repos needed
        local _profile
        _profile=$(python3 -c "
import yaml, sys
try:
    c = yaml.safe_load(open('${onboarding_file}'))
    v = c.get('cicd_profile')
    if not v:
        print('MISSING', file=sys.stderr)
        sys.exit(1)
    print(v)
except Exception:
    sys.exit(1)
" 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$_profile" ]; then
            echo -e "${RED}[ERROR]${NC} cicd_profile is required but not set in $(basename "$onboarding_file"). Allowed values: minimal | ci_only | ci_cd"
            exit_code=1
            continue
        fi
        if [ "$_profile" = "minimal" ]; then
            echo -e "${BLUE}[INFO]${NC} cicd_profile is 'minimal' — no compliance repos required, skipping"
            continue
        fi

        # Generate team slug
        team_slug=$(echo "$team_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

        # Process inventory repository
        if [ "$inventory_create" = "True" ] || [ "$inventory_create" = "true" ]; then
            echo -e "${BLUE}[INFO]${NC} Inventory repository creation requested"
            echo -e "${BLUE}[INFO]${NC} Target:   ${inventory_org}/${inventory_name}"
            echo -e "${BLUE}[INFO]${NC} Template: https://${GH_HOSTNAME}/${INVENTORY_TEMPLATE_OWNER}/${INVENTORY_TEMPLATE_REPO}"

            if [ -z "$inventory_org" ] || [ -z "$inventory_name" ]; then
                echo -e "${RED}[ERROR]${NC} inventory_repo.repo URL is missing or could not be parsed"
                exit_code=1
            elif repo_exists "$inventory_org" "$inventory_name"; then
                echo -e "${YELLOW}[WARNING]${NC} Inventory repository already exists: ${inventory_org}/${inventory_name}"
            else
                local inventory_url
                inventory_url=$(fork_inventory_repo \
                    "$inventory_org" \
                    "$inventory_name" \
                    "Compliance inventory for ${service_name} (${team_name} team)")

                if [ $? -eq 0 ]; then
                    created_repos+=("${inventory_org}/${inventory_name} (inventory — forked from ${INVENTORY_TEMPLATE_OWNER}/${INVENTORY_TEMPLATE_REPO})")
                    echo -e "${GREEN}[SUCCESS]${NC} Inventory repository ready: ${inventory_url}"

                    # Verify both FIDs have admin access — access must be pre-approved via Access Hub.
                    # Do NOT grant programmatically: direct API grants are reverted by Access Hub reconciliation.
                    echo -e "${BLUE}[INFO]${NC} Verifying admin access on inventory repository..."
                    if [ -n "$service_fid_dev_github_username" ]; then
                        if ! verify_repo_permission "$inventory_org" "$inventory_name" \
                                "$service_fid_dev_github_username" "admin"; then
                            exit 1
                        fi
                    fi
                    if [ -n "$service_fid_prod_github_username" ]; then
                        if ! verify_repo_permission "$inventory_org" "$inventory_name" \
                                "$service_fid_prod_github_username" "admin"; then
                            exit 1
                        fi
                    fi
                else
                    echo -e "${RED}[ERROR]${NC} Failed to create inventory repository"
                    exit_code=1
                fi
            fi
        else
            echo -e "${BLUE}[INFO]${NC} Inventory repository creation not requested (create: false)"
        fi

        echo ""

        # Process incident repository (plain repo — no template)
        if [ "$incident_create" = "True" ] || [ "$incident_create" = "true" ]; then
            echo -e "${BLUE}[INFO]${NC} Incident repository creation requested"
            echo -e "${BLUE}[INFO]${NC} Target: ${incident_org}/${incident_name}"

            if [ -z "$incident_org" ] || [ -z "$incident_name" ]; then
                echo -e "${RED}[ERROR]${NC} incident_repo.repo URL is missing or could not be parsed"
                exit_code=1
            elif repo_exists "$incident_org" "$incident_name"; then
                echo -e "${YELLOW}[WARNING]${NC} Incident repository already exists: ${incident_org}/${incident_name}"
            else
                local incident_url
                incident_url=$(create_github_repo \
                    "$incident_org" \
                    "$incident_name" \
                    "Incident tracking for ${service_name} (${team_name} team)" \
                    "true")

                if [ $? -eq 0 ]; then
                    # Add a README so the repo has a default branch and a single seed commit
                    if ! create_readme "$incident_org" "$incident_name" "$incident_branch"; then
                        echo -e "${RED}[ERROR]${NC} Failed to create README.md in incident repository"
                        exit_code=1
                    fi
                    created_repos+=("${incident_org}/${incident_name} (incident)")
                    echo -e "${GREEN}[SUCCESS]${NC} Incident repository created: ${incident_url}"

                    # Verify both FIDs have admin access — access must be pre-approved via Access Hub.
                    # Do NOT grant programmatically: direct API grants are reverted by Access Hub reconciliation.
                    echo -e "${BLUE}[INFO]${NC} Verifying admin access on incident repository..."
                    if [ -n "$service_fid_dev_github_username" ]; then
                        if ! verify_repo_permission "$incident_org" "$incident_name" \
                                "$service_fid_dev_github_username" "admin"; then
                            exit 1
                        fi
                    fi
                    if [ -n "$service_fid_prod_github_username" ]; then
                        if ! verify_repo_permission "$incident_org" "$incident_name" \
                                "$service_fid_prod_github_username" "admin"; then
                            exit 1
                        fi
                    fi
                else
                    echo -e "${RED}[ERROR]${NC} Failed to create incident repository"
                    exit_code=1
                fi
            fi
        else
            echo -e "${BLUE}[INFO]${NC} Incident repository creation not requested (create: false)"
        fi
        
        echo ""
    done
    
    # Summary
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ ${#created_repos[@]} -gt 0 ]; then
        echo -e "${GREEN}[SUCCESS]${NC} Repository creation completed"
        echo -e "${BLUE}Repositories created:${NC}"
        for repo in "${created_repos[@]}"; do
            echo -e "  - ${repo}"
        done
    else
        echo -e "${YELLOW}[INFO]${NC} No repositories were created"
        echo -e "${BLUE}[INFO]${NC} This is normal if create: false or repositories already exist"
    fi
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    exit $exit_code
}

# Run main function
main "$@"

# Made with Bob
