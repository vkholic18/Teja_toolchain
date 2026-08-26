#!/bin/bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Automated Secrets Sync Script
# This script runs in the merge pipeline of uuc-service-cicd-onboarding repo.
# It detects changed onboarding.yaml files and automatically creates a PR in
# uuc-infrastructure-tf-module repo with updated secrets configuration.
#
# Branch strategy
# ---------------
# Each team's Terraform state lives on a dedicated branch named after the team
# slug (e.g. "observability").  This script checks out each team branch and
# opens a PR against it — never against main.
#
# tfvars file location
# --------------------
# Team secrets live in <team-slug>.auto.tfvars at the repo root (auto-loaded
# by Terraform).  The old teams/<team-slug>/team.tfvars path is gone.
#
# Secrets scripts
# ---------------
# scripts/secrets/ (extract_custom_secrets.py + mandatory_secrets_template.yaml)
# only exist on the main branch.  This script sparse-clones main into a
# separate SECRETS_TOOLS_DIR and runs the Python script from there.

set -e  # Exit on error

# macOS BSD sed requires -i '' ; GNU sed accepts -i alone
if sed --version 2>/dev/null | grep -q GNU; then
    SED_I=(-i)
else
    SED_I=(-i '')
fi

# Source common utilities
source "${PATH_TO_GENCTL_CI}/onepipeline/utils/onboarding_validation_utils.sh"

# Configuration
INFRASTRUCTURE_REPO="github.ibm.com/genctl-cicd/uuc-infrastructure-tf-module"
INFRASTRUCTURE_REPO_URL="https://${GITHUB_TOKEN}@${INFRASTRUCTURE_REPO}.git"
INFRASTRUCTURE_BRANCH="main"
# Path to secrets scripts relative to the repo root (only present on main branch)
SECRETS_SCRIPT_PATH="scripts/secrets/extract_custom_secrets.py"

# Temporary working directory
WORK_DIR="/tmp/uuc-secrets-sync-$$"
INFRA_CLONE_DIR="${WORK_DIR}/infrastructure"
# Separate sparse-clone of main that always has scripts/secrets/
SECRETS_TOOLS_DIR="${WORK_DIR}/secrets-tools"

# Initialize
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🔐 UUC Secrets Configuration Sync${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check prerequisites
check_python_available
check_python_dependencies
check_github_token

# ---------------------------------------------------------------------------
# Function to extract team slug from onboarding file path.
# Expected pattern: <team-folder>/<repo-name>-onboarding.yaml
# ---------------------------------------------------------------------------
extract_team_slug() {
    local file_path="$1"
    local team_folder
    team_folder=$(dirname "$file_path")
    local team_slug
    team_slug=$(basename "$team_folder")

    if [[ "$team_slug" != "." ]] && [[ "$team_slug" != ".." ]]; then
        echo "$team_slug"
        return 0
    fi

    # Fallback: derive from filename
    local filename
    filename=$(basename "$file_path")
    team_slug="${filename%-onboarding.yaml}"
    team_slug="${team_slug%-onboarding.yml}"
    echo "$team_slug"
}

# ---------------------------------------------------------------------------
# Ensure scripts/secrets tools are available from the main branch.
# Sparse-clones main into SECRETS_TOOLS_DIR once; reused across all teams.
# ---------------------------------------------------------------------------
ensure_secrets_tools() {
    if [ -d "${SECRETS_TOOLS_DIR}" ]; then
        echo -e "${BLUE}[INFO]${NC} Secrets tools already fetched from main"
        return 0
    fi

    echo -e "${BLUE}[INFO]${NC} Fetching scripts/secrets from main branch..."
    mkdir -p "${SECRETS_TOOLS_DIR}"

    git clone \
        --depth 1 \
        --branch "$INFRASTRUCTURE_BRANCH" \
        --no-checkout \
        "$INFRASTRUCTURE_REPO_URL" \
        "${SECRETS_TOOLS_DIR}" 2>&1 | grep -v "warning: " || {
        echo -e "${RED}[ERROR]${NC} Failed to clone main for secrets tools"
        return 1
    }

    git -C "${SECRETS_TOOLS_DIR}" sparse-checkout set scripts/
    git -C "${SECRETS_TOOLS_DIR}" checkout

    if [ ! -f "${SECRETS_TOOLS_DIR}/${SECRETS_SCRIPT_PATH}" ]; then
        echo -e "${RED}[ERROR]${NC} extract_custom_secrets.py not found on main branch"
        return 1
    fi

    echo -e "${GREEN}[SUCCESS]${NC} Secrets tools ready at ${SECRETS_TOOLS_DIR}"
}

# ---------------------------------------------------------------------------
# Check whether the team branch exists on the remote.
# ---------------------------------------------------------------------------
team_branch_exists() {
    local team_slug="$1"
    cd "${INFRA_CLONE_DIR}"
    git ls-remote --exit-code --heads origin "$team_slug" &>/dev/null
}

# ---------------------------------------------------------------------------
# Generate custom secrets config for a team from one or more onboarding files.
# Runs extract_custom_secrets.py from SECRETS_TOOLS_DIR (main branch clone).
# ---------------------------------------------------------------------------
generate_custom_secrets_for_team() {
    local team_slug="$1"
    shift
    local onboarding_files=("$@")
    local output_file="${WORK_DIR}/${team_slug}-custom-secrets.tfvars"
    local error_file="${WORK_DIR}/${team_slug}-custom-secrets.error"

    echo -e "${BLUE}[INFO]${NC} Generating custom secrets configuration for team: ${GREEN}${team_slug}${NC}"
    echo -e "${BLUE}[INFO]${NC} Processing ${#onboarding_files[@]} service(s):"
    for file in "${onboarding_files[@]}"; do
        echo -e "  - $(basename "$file")"
    done

    if ! ensure_secrets_tools; then
        echo -e "${RED}[ERROR]${NC} Cannot generate custom secrets: secrets tools unavailable"
        return 1
    fi

    local script="${SECRETS_TOOLS_DIR}/${SECRETS_SCRIPT_PATH}"

    # Run from SECRETS_TOOLS_DIR so the script resolves
    # scripts/secrets/mandatory_secrets_template.yaml via relative path
    pushd "${SECRETS_TOOLS_DIR}" > /dev/null

    local cmd="python3 ${script} ${team_slug}"
    for file in "${onboarding_files[@]}"; do
        cmd="$cmd \"$file\""
    done

    if ! eval "$cmd" > "$output_file" 2> "$error_file"; then
        echo -e "${RED}[ERROR]${NC} Failed to generate custom secrets configuration for ${team_slug}"
        echo -e "${RED}[ERROR]${NC} Error output:"
        cat "$error_file"
        popd > /dev/null
        return 1
    fi

    if [ -s "$error_file" ]; then
        echo -e "${YELLOW}[WARNING]${NC} Script produced warnings:"
        cat "$error_file"
    fi

    popd > /dev/null

    # Strip the trailing help-text comment emitted by extract_custom_secrets.py
    sed "${SED_I[@]}" '/^# Add the above configuration/,$d' "$output_file"

    echo -e "${GREEN}[SUCCESS]${NC} Generated custom secrets configuration for ${team_slug}"
    echo "$output_file"
    return 0
}

# ---------------------------------------------------------------------------
# Update <team-slug>.auto.tfvars at the repo root with freshly generated
# secrets.  Idempotent: removes stale entries before appending new content.
# ---------------------------------------------------------------------------
update_team_autotfvars() {
    local team_slug="$1"
    local custom_secrets_config_file="$2"
    local tfvars_file="${INFRA_CLONE_DIR}/${team_slug}.auto.tfvars"
    local var_prefix="${team_slug//-/_}"

    echo -e "${BLUE}[INFO]${NC} Updating ${team_slug}.auto.tfvars"

    if [ ! -f "$tfvars_file" ]; then
        echo -e "${YELLOW}[WARNING]${NC} ${team_slug}.auto.tfvars not found: ${tfvars_file}"
        echo -e "${YELLOW}[WARNING]${NC} Team may not yet have a branch — skipping secrets update"
        return 0
    fi

    cp "$tfvars_file" "${tfvars_file}.backup"

    # Remove stale comment headers emitted by extract_custom_secrets.py
    sed "${SED_I[@]}" \
        -e '/^# Slack Notification Configuration$/d' \
        -e '/^# These IDs will be added to secret metadata for notifications$/d' \
        -e '/^# PSIRT IDs for Mend SAST Secrets$/d' \
        -e '/^# One PSIRT ID per service - used to generate Mend SAST secrets dynamically$/d' \
        -e '/^# Custom Secrets Configuration (Team-Managed)$/d' \
        -e '/^# Mandatory secrets (GARA, ServiceNow, FID) are hardcoded in the Terraform module$/d' \
        -e '/^# Mend SAST secrets are generated dynamically from psirt_ids above$/d' \
        -e '/^# Secret names will be: sg-uuc-<team-slug>-<secret-name>$/d' \
        -e '/^# Total custom secrets: [0-9]*$/d' \
        "$tfvars_file"

    # Remove existing psirt_ids (prefixed or legacy non-prefixed)
    sed "${SED_I[@]}" -E "/^psirt_ids[[:space:]]*=.*/d; /^${var_prefix}_psirt_ids[[:space:]]*=.*/d" "$tfvars_file"

    # Remove existing slack_member_ids
    sed "${SED_I[@]}" -E "/^slack_member_ids[[:space:]]*=.*/d; /^${var_prefix}_slack_member_ids[[:space:]]*=.*/d" "$tfvars_file"

    # Remove existing slack_channel
    sed "${SED_I[@]}" -E "/^slack_channel[[:space:]]*=.*/d; /^${var_prefix}_slack_channel[[:space:]]*=.*/d" "$tfvars_file"

    # Remove existing custom_secrets block (bracket-aware, handles prefixed and non-prefixed)
    if grep -qE "^custom_secrets[[:space:]]*=[[:space:]]*\[|^${var_prefix}_custom_secrets[[:space:]]*=[[:space:]]*\[" "$tfvars_file"; then
        awk -v prefix="${var_prefix}" '
        /^custom_secrets[[:space:]]*=[[:space:]]*\[/ || $0 ~ "^" prefix "_custom_secrets[[:space:]]*=[[:space:]]*\\[" {
            in_block=1; bracket_count=1; next
        }
        in_block {
            for (i=1; i<=length($0); i++) {
                c = substr($0, i, 1)
                if (c == "[") bracket_count++
                if (c == "]") bracket_count--
            }
            if (bracket_count == 0) { in_block=0 }
            next
        }
        !in_block { print }
        ' "$tfvars_file" > "${tfvars_file}.tmp"
        mv "${tfvars_file}.tmp" "$tfvars_file"
    fi

    # Append freshly generated content
    echo "" >> "$tfvars_file"
    cat "$custom_secrets_config_file" >> "$tfvars_file"
    echo "" >> "$tfvars_file"

    echo -e "${GREEN}[SUCCESS]${NC} Updated ${team_slug}.auto.tfvars"
    return 0
}

# ---------------------------------------------------------------------------
# Create a PR for one team: checks out the team branch, updates
# <team-slug>.auto.tfvars, opens a PR against the team branch (not main).
# ---------------------------------------------------------------------------
create_team_pr() {
    local team_slug="$1"
    local custom_secrets_config_file="$2"

    local team_branch="${team_slug}"
    local pr_title="chore: Update secrets configuration for ${team_slug}"

    local pr_body="## Automated Secrets Configuration Update

This PR was automatically generated by the UUC onboarding merge pipeline.

### Team
- **Team Slug**: ${team_slug}
- **Branch**: \`${team_branch}\`

### Changes
- Updated \`${team_slug}.auto.tfvars\` with latest secrets configuration
- Extracted ONLY custom secrets (mandatory: false) from onboarding.yaml files
- Combined and deduplicated secrets from all services for this team
- Mandatory secrets (GARA, Mend SAST, ServiceNow, FID) are hardcoded in the Terraform module

### Secrets Configuration
- **Scripts source**: \`scripts/secrets/\` fetched from \`main\` branch (not present on team branches)
- **Template**: \`scripts/secrets/mandatory_secrets_template.yaml\` on \`main\`
- **Custom Secrets**: mandatory: false entries from onboarding.yaml
- **Deduplication**: Multiple services with same secret = single entry

### Next Steps
1. Review the changes in \`${team_slug}.auto.tfvars\`
2. Merge this PR into branch \`${team_branch}\`
3. Run \`terraform apply\` on branch \`${team_branch}\` to provision secrets in IBM Secrets Manager

### Related
- Source: uuc-service-cicd-onboarding repository
- Pipeline: UUC Ops Merge Pipeline
- Generated by: add_update_secrets.sh

---
*This PR was automatically created. Please review carefully before merging.*"

    cd "${INFRA_CLONE_DIR}"

    # ---- Set up team branch ------------------------------------------------
    if ! team_branch_exists "$team_slug"; then
        echo -e "${YELLOW}[WARNING]${NC} Team branch '${team_slug}' does not exist on remote"
        echo -e "${YELLOW}[WARNING]${NC} Skipping ${team_slug} — team must be onboarded via provision_team_infrastructure.sh first"
        return 0
    fi

    echo -e "${BLUE}[INFO]${NC} Checking out team branch: ${team_branch}"
    git fetch origin "$team_branch"
    git checkout "$team_branch"
    git reset --hard "origin/${team_branch}"

    # ---- Update .auto.tfvars -----------------------------------------------
    if ! update_team_autotfvars "$team_slug" "$custom_secrets_config_file"; then
        echo -e "${RED}[ERROR]${NC} Failed to update ${team_slug}.auto.tfvars"
        return 1
    fi

    # ---- Create PR branch off the team branch ------------------------------
    local pr_branch="auto-secrets-${team_slug}-$(date +%Y%m%d-%H%M%S)"
    echo -e "${BLUE}[INFO]${NC} Creating PR branch: ${pr_branch}"
    git checkout -b "$pr_branch"

    # ---- Stage changes -----------------------------------------------------
    git add "${team_slug}.auto.tfvars"

    if git diff --cached --quiet; then
        echo -e "${YELLOW}[WARNING]${NC} No changes detected in ${team_slug}.auto.tfvars — already up to date"
        git checkout "$team_branch"
        return 0
    fi

    # ---- Commit & push -----------------------------------------------------
    git config user.name "clconc"
    git config user.email "clconc@us.ibm.com"
    git commit -m "$pr_title"

    echo -e "${BLUE}[INFO]${NC} Pushing branch to remote"
    git push origin "$pr_branch"

    # ---- Open PR via GitHub API (head → team branch, NOT main) -------------
    echo -e "${BLUE}[INFO]${NC} Creating pull request: ${pr_branch} → ${team_branch}"

    local pr_payload
    pr_payload=$(cat <<EOF
{
  "title": "$pr_title",
  "body": $(echo "$pr_body" | jq -Rs .),
  "head": "$pr_branch",
  "base": "$team_branch"
}
EOF
)

    local pr_response
    pr_response=$(curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://github.ibm.com/api/v3/repos/genctl-cicd/uuc-infrastructure-tf-module/pulls" \
        -d "$pr_payload")

    local pr_url pr_number
    pr_url=$(echo "$pr_response" | jq -r '.html_url // empty')
    pr_number=$(echo "$pr_response" | jq -r '.number // empty')

    if [ -n "$pr_url" ] && [ "$pr_url" != "null" ]; then
        echo -e "${GREEN}[SUCCESS]${NC} Pull request created: PR #${pr_number}: ${pr_url}"
        git checkout "$team_branch"
        return 0
    else
        echo -e "${RED}[ERROR]${NC} Failed to create pull request"
        echo "Response: $pr_response"
        git checkout "$team_branch" 2>/dev/null || true
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------
main() {
    local exit_code=0
    local changed_files=()
    local processed_teams=()

    mkdir -p "$WORK_DIR"

    echo -e "${BLUE}[INFO]${NC} Detecting changed onboarding files..."
    mapfile -t changed_files < <(get_changed_files_from_git)

    if [ ${#changed_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}[WARNING]${NC} No onboarding files changed in this merge"
        echo -e "${BLUE}[INFO]${NC} Skipping secrets sync"
        exit 0
    fi

    echo -e "${GREEN}[INFO]${NC} Found ${#changed_files[@]} changed onboarding file(s)"
    for file in "${changed_files[@]}"; do
        echo -e "  - ${file}"
    done
    echo ""

    # ---- Clone infrastructure repo (full, so we can switch branches) -------
    echo -e "${BLUE}[INFO]${NC} Cloning infrastructure repository..."
    if ! git clone --branch "$INFRASTRUCTURE_BRANCH" "$INFRASTRUCTURE_REPO_URL" "$INFRA_CLONE_DIR" 2>&1 | grep -v "warning: "; then
        echo -e "${RED}[ERROR]${NC} Failed to clone infrastructure repository"
        exit 1
    fi
    echo -e "${GREEN}[SUCCESS]${NC} Infrastructure repository cloned"
    echo ""

    # ---- Group changed files by team slug ----------------------------------
    declare -A team_files
    for onboarding_file in "${changed_files[@]}"; do
        local team_slug
        team_slug=$(extract_team_slug "$onboarding_file")

        if [[ "$onboarding_file" != /* ]]; then
            if [ -n "$PATH_TO_WORKSPACE_REPO" ]; then
                onboarding_file="${PATH_TO_WORKSPACE_REPO}/${onboarding_file}"
            else
                onboarding_file="$(pwd)/${onboarding_file}"
            fi
        fi

        if [ -z "${team_files[$team_slug]}" ]; then
            team_files["$team_slug"]="$onboarding_file"
        else
            team_files["$team_slug"]="${team_files[$team_slug]} $onboarding_file"
        fi
    done

    # ---- Process each team -------------------------------------------------
    for team_slug in "${!team_files[@]}"; do
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}[INFO]${NC} Processing team: ${GREEN}${team_slug}${NC}"

        IFS=' ' read -r -a team_onboarding_files <<< "${team_files[$team_slug]}"

        local custom_secrets_config_file
        custom_secrets_config_file=$(generate_custom_secrets_for_team "$team_slug" "${team_onboarding_files[@]}")

        if [ $? -eq 0 ] && [ -f "$custom_secrets_config_file" ]; then
            if create_team_pr "$team_slug" "$custom_secrets_config_file"; then
                processed_teams+=("$team_slug")
            else
                echo -e "${RED}[ERROR]${NC} Failed to create PR for ${team_slug}"
                exit_code=1
            fi
        else
            echo -e "${RED}[ERROR]${NC} Failed to generate custom secrets for ${team_slug}"
            exit_code=1
        fi

        echo ""
    done

    # ---- Summary -----------------------------------------------------------
    if [ ${#processed_teams[@]} -gt 0 ]; then
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}[SUCCESS]${NC} Secrets sync completed for ${#processed_teams[@]} team(s):"
        for team in "${processed_teams[@]}"; do
            echo -e "  - ${team}"
        done
    else
        echo -e "${YELLOW}[WARNING]${NC} No teams were updated"
        echo -e "${BLUE}[INFO]${NC} Teams may not yet have branches — run provision_team_infrastructure.sh first"
    fi

    echo ""
    echo -e "${BLUE}[INFO]${NC} Cleaning up temporary files..."
    rm -rf "$WORK_DIR"

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    exit $exit_code
}

# Run main function
main "$@"

# Made with Bob
