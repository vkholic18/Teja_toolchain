#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Team CD Toolchains Provisioning Script
# This script runs in the merge pipeline of uuc-service-cicd-onboarding repo.
# It detects new/changed onboarding YAML files, then creates (or updates) a PR
# in the uuc-toolchains-tf-module repository targeting the team's dedicated
# <team-slug>-cd branch to add new CD toolchain entries.
#
# Branch strategy
# ---------------
# Each team owns a dedicated branch named <team-slug>-cd in the toolchains repo.
# For a brand-new team the branch is scaffolded by calling create-team-branch.sh
# with deployment-type "cd" (identical to the CI flow but targeting templates/cd/).
# For an existing team the branch is checked out directly.
#
# Toolchain file location
# -----------------------
# The per-team toolchain definitions live in:
#   <team-slug>-cd-toolchains.tf   (at the repo root of the team branch)
#
# CD vs CI differences
# --------------------
# The CD toolchain module uses template_type = "uuc_common_cd" and carries two
# extra module-level arguments: secrets_manager_data and
# global_toolchain_compliance_tag_v11.  Toolchain entries do NOT include
# repo_branch or repo_org (CD toolchains reference the inventory repo, not the
# app repo directly).
#
# Idempotency / duplicate detection
# ----------------------------------
# Before appending a new toolchain block the script checks whether the
# inventory_repo_url and incident_repo_url pair already appears in the .tf file.
# If both are already present the entry is skipped with an inline comment.
#
# Multiple onboarding files → single PR
# --------------------------------------
# All onboarding files belonging to the same team are batched into a single PR.

set -e  # Exit on error

# Source common utilities
source "${PATH_TO_GENCTL_CI}/onepipeline/utils/onboarding_validation_utils.sh"
source "${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
TOOLCHAINS_REPO="github.ibm.com/genctl-cicd/uuc-toolchains-tf-module"
TOOLCHAINS_REPO_URL="https://${GITHUB_TOKEN}@${TOOLCHAINS_REPO}.git"
TOOLCHAINS_MAIN_BRANCH="main"

# Path to the trigger-generator script (same directory as this script)
GENERATE_TRIGGERS_PY="${PATH_TO_GENCTL_CI}/onepipeline/pipelines/uuc/ops/merge/steps/generate_cd_triggers.py"
# Note: DCMS_ENV_CODE_YAML_URL, UNDERCLOUD_ENV_CODE_YAML_URL, and their LOCAL
# fallback counterparts are defined in onboarding_validation_utils.sh (sourced above).
# resolve_env_code_yaml() is also provided there — use it directly.

# ---------------------------------------------------------------------------
# Trigger-creation flag
# ---------------------------------------------------------------------------
# When ENABLE_TRIGGER_CREATION=false (the default) the script skips all calls
# to generate_cd_triggers.py — neither the team-level tier-default trigger
# locals nor any service-specific override locals are regenerated.  The
# toolchain blocks themselves and the FID patch are still applied normally.
#
# Set ENABLE_TRIGGER_CREATION=true in the pipeline environment properties to
# enable trigger generation for both DCMS and Undercloud teams.
#
# This flag controls both:
#   • patch_cd_trigger_data          (team-level tier-default trigger locals)
#   • patch_cd_service_trigger_override (per-service exclude-filtered locals)
# ---------------------------------------------------------------------------
ENABLE_TRIGGER_CREATION="${ENABLE_TRIGGER_CREATION:-false}"
ENABLE_TRIGGER_CREATION="${ENABLE_TRIGGER_CREATION,,}"  # normalise to lowercase

# Temporary working directory
WORK_DIR="/tmp/uuc-cd-toolchains-provision-$$"

# Use pre-cloned toolchains repo if available, otherwise clone it fresh
if [ -n "$PATH_TO_UUC_TOOLCHAINS_REPO" ] && [ -d "$PATH_TO_UUC_TOOLCHAINS_REPO/.git" ]; then
    TOOLCHAINS_CLONE_DIR="$PATH_TO_UUC_TOOLCHAINS_REPO"
    USE_EXISTING_CLONE=true
else
    TOOLCHAINS_CLONE_DIR="${WORK_DIR}/toolchains"
    USE_EXISTING_CLONE=false
fi

# Script-level vars for the PR created by create_cd_toolchains_pr() — reset
# before each team so the caller's wait loop never picks up a stale value.
CREATED_TOOLCHAINS_PR_URL=""
CREATED_TOOLCHAINS_PR_NUMBER=""

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🚀  UUC Team CD Toolchains Provisioning${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
check_python_available
check_python_dependencies
check_github_token

# ---------------------------------------------------------------------------
# Function: extract_toolchain_info_from_onboarding
#
# Parses an onboarding YAML file and emits a pipe-separated summary line:
#   team_name|team_slug|service_name|inventory_repo_url|incident_repo_url
#   |service_fid_dev|service_fid_prod
#
# account_type is NOT read from the YAML — it is sourced from the ACCOUNT_TYPE
# environment variable (default: "dev").
#
# CD toolchain field mapping (from onboarding.yaml):
#   repo               = inventory_repo.repo   ← inventory repo IS the app repo for CD
#   inventory_repo_url = inventory_repo.repo   ← same URL used for both repo and inventory_repo_url
#   incident_repo_url  = incident_repo.repo    ← actual incident repo from onboarding.yaml
# ---------------------------------------------------------------------------
extract_toolchain_info_from_onboarding() {
    local onboarding_file="$1"

    if [ ! -f "$onboarding_file" ]; then
        echo -e "${RED}[ERROR]${NC} Onboarding file not found: $onboarding_file" >&2
        return 1
    fi

    python3 - <<EOF
import yaml, sys, os
from pathlib import Path

try:
    with open('$onboarding_file', 'r') as f:
        config = yaml.safe_load(f)

    if not isinstance(config, dict):
        print("ERROR: YAML is not a valid dict", file=sys.stderr)
        sys.exit(1)

    # Load commons.yaml — team-level fields (FIDs) live there
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

    team_name = commons.get('team_name', '').strip()
    if not team_name:
        print("ERROR: 'team_name' is missing or empty in commons.yaml", file=sys.stderr)
        sys.exit(1)

    service_name = config.get('service_name', '').strip()
    if not service_name:
        print("ERROR: 'service_name' is missing or empty", file=sys.stderr)
        sys.exit(1)

    team_slug = team_name.lower().replace(' ', '-')

    # Inventory repo — used as BOTH repo and inventory_repo_url in the CD toolchain entry.
    inv_cfg  = config.get('inventory_repo', {}) or {}
    inv_repo = inv_cfg.get('repo', '').rstrip('/')
    if inv_repo and not inv_repo.endswith('.git'):
        inv_repo += '.git'

    # Incident repo
    inc_cfg  = config.get('incident_repo', {}) or {}
    inc_repo = inc_cfg.get('repo', '').rstrip('/')
    if inc_repo and not inc_repo.endswith('.git'):
        inc_repo += '.git'

    if not inv_repo:
        print("ERROR: 'inventory_repo.repo' is missing or empty", file=sys.stderr)
        sys.exit(1)

    if not inc_repo:
        print("ERROR: 'incident_repo.repo' is missing or empty", file=sys.stderr)
        sys.exit(1)

    # Service Functional IDs — now in commons.yaml
    service_fid_dev  = commons.get('service_fid_dev',  '').strip()
    service_fid_prod = commons.get('service_fid_prod', '').strip()

    # ServiceNow CRN — mandatory for ci_cd/cd_only (validated separately by validate_yaml.py)
    servicenow_crn = str(config.get('servicenow_crn') or '').strip()

    print(f"{team_name}|{team_slug}|{service_name}|{inv_repo}|{inc_repo}|{service_fid_dev}|{service_fid_prod}|{servicenow_crn}")

except yaml.YAMLError as e:
    print(f"ERROR: YAML parse error: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# ---------------------------------------------------------------------------
# Function: patch_cd_pipeline_vars_fid
#
# Patches two values in the team's <team-slug>-cd-pipeline_vars.tf file:
#   1. "service-functional-id-email" value under common_tc_env_props
#   2. "assignee" value under common_cd_promotion_pipeline_env_props
#
# The FID email is selected based on the ACCOUNT_TYPE environment variable:
#   ACCOUNT_TYPE=dev  (default) → uses service_fid_dev
#   ACCOUNT_TYPE=prod           → uses service_fid_prod
#
# If the pipeline_vars file is not found this is treated as a warning (not an
# error) so that existing branches that pre-date the FID fields are not broken.
#
# Args:
#   $1  team_slug
#   $2  service_fid_dev
#   $3  service_fid_prod
# ---------------------------------------------------------------------------
patch_cd_pipeline_vars_fid() {
    local team_slug="$1"
    local service_fid_dev="$2"
    local service_fid_prod="$3"

    # ACCOUNT_TYPE env var — default "dev"
    local account_type="${ACCOUNT_TYPE:-dev}"
    account_type="${account_type,,}"  # lowercase
    [[ "$account_type" == "prod" ]] || account_type="dev"

    local pv_file="${TOOLCHAINS_CLONE_DIR}/${team_slug}-cd-pipeline_vars.tf"

    if [ ! -f "$pv_file" ]; then
        echo -e "${YELLOW}[WARNING]${NC} CD pipeline_vars file not found — skipping FID patch: ${pv_file}" >&2
        return 0
    fi

    # Select the FID email based on account type
    local fid_email
    if [ "$account_type" = "prod" ]; then
        fid_email="$service_fid_prod"
    else
        fid_email="$service_fid_dev"
    fi

    if [ -z "$fid_email" ]; then
        echo -e "${RED}[ERROR]${NC} service_fid_${account_type} is missing in onboarding YAML — cannot patch CD pipeline_vars for ${team_slug}" >&2
        return 1
    fi

    echo -e "${BLUE}[INFO]${NC} Patching CD pipeline_vars FID (ACCOUNT_TYPE=${account_type}): ${fid_email}"

    python3 - "$pv_file" "$fid_email" <<'PYEOF'
import sys, re

pv_file   = sys.argv[1]
fid_email = sys.argv[2]

# Placeholder strings as written in the templates — only replace when still at these values.
PLACEHOLDER_FID      = "service-functional-id-email"
PLACEHOLDER_ASSIGNEE = "assignee"

with open(pv_file) as f:
    content = f.read()

patched = False

# 1. Patch "service-functional-id-email" under common_tc_env_props
#    Only replaces when value is still the template placeholder, not a real email.
new_content = re.sub(
    r'("service-functional-id-email"\s*=\s*\{[^}]*?value\s*=\s*)"' + re.escape(PLACEHOLDER_FID) + r'"',
    lambda m: m.group(1) + f'"{fid_email}"',
    content,
    count=1,
    flags=re.DOTALL
)
if new_content != content:
    patched = True
    content = new_content
    print(f"INFO: Patched service-functional-id-email → {fid_email}", file=sys.stderr)
else:
    print(f"INFO: 'service-functional-id-email' already set or placeholder not found — skipping", file=sys.stderr)

# 2. Patch "assignee" under common_cd_promotion_pipeline_env_props
#    Only replaces when value is still the template placeholder, not a real email.
new_content = re.sub(
    r'("assignee"\s*=\s*\{[^}]*?value\s*=\s*)"' + re.escape(PLACEHOLDER_ASSIGNEE) + r'"',
    lambda m: m.group(1) + f'"{fid_email}"',
    content,
    count=1,
    flags=re.DOTALL
)
if new_content != content:
    patched = True
    content = new_content
    print(f"INFO: Patched assignee → {fid_email}", file=sys.stderr)
else:
    print(f"INFO: 'assignee' already set or placeholder not found — skipping", file=sys.stderr)

if patched:
    with open(pv_file, 'w') as f:
        f.write(content)
PYEOF
}

# ---------------------------------------------------------------------------
# Function: patch_cd_trigger_data
#
# Generates/replaces the tier-default trigger local
# (<team_underscore>_cd_pipeline_types_trigger_data_<tier>) inside the
# team's <team-slug>-cd-pipeline_vars.tf file by calling generate_cd_triggers.py.
#
# Also updates the team-level pointer local to reference the tier default
# when it still points to the common module default.
#
# Args:
#   $1  team_slug
#   $2  env_yaml_source  — path or URL to the environment-code YAML
# ---------------------------------------------------------------------------
patch_cd_trigger_data() {
    local team_slug="$1"
    local env_yaml_source="$2"

    if [ "$ENABLE_TRIGGER_CREATION" != "true" ]; then
        echo -e "${YELLOW}[INFO]${NC} Trigger creation disabled (ENABLE_TRIGGER_CREATION=${ENABLE_TRIGGER_CREATION}) — skipping trigger data patch for ${team_slug}"
        return 0
    fi

    local account_type="${ACCOUNT_TYPE:-dev}"
    account_type="${account_type,,}"
    [[ "$account_type" == "prod" ]] || account_type="dev"

    local pv_file="${TOOLCHAINS_CLONE_DIR}/${team_slug}-cd-pipeline_vars.tf"

    if [ ! -f "$pv_file" ]; then
        echo -e "${YELLOW}[WARNING]${NC} CD pipeline_vars file not found — skipping trigger patch: ${pv_file}" >&2
        return 0
    fi

    if [ ! -f "$GENERATE_TRIGGERS_PY" ]; then
        echo -e "${RED}[ERROR]${NC} generate_cd_triggers.py not found at: ${GENERATE_TRIGGERS_PY}" >&2
        return 1
    fi

    echo -e "${BLUE}[INFO]${NC} Patching CD trigger data for ${team_slug} (account_type=${account_type}, source=$(basename "$env_yaml_source"))"

    python3 "$GENERATE_TRIGGERS_PY" \
        --env-yaml      "$env_yaml_source" \
        --team-slug     "$team_slug" \
        --account-type  "$account_type" \
        --tf-file       "$pv_file" \
        2>&1 | while IFS= read -r line; do
            echo -e "${BLUE}[INFO]${NC} [triggers] ${line}"
        done

    local py_exit="${PIPESTATUS[0]}"
    if [ "$py_exit" -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} generate_cd_triggers.py failed (exit ${py_exit}) for team ${team_slug}" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Function: patch_cd_service_trigger_override
#
# Generates a standalone service-specific trigger local
# (<team_underscore>_cd_pipeline_types_trigger_data_<service_underscore>)
# with the excluded target-environments filtered out.
#
# This is a STANDALONE list (not a merge) — the excluded targets are simply
# absent.  Called only when deployment_targets.CD.<tier>.exclude is non-empty
# in the onboarding YAML.
#
# Args:
#   $1  team_slug
#   $2  service_slug     — hyphenated (e.g. auth-service)
#   $3  excludes_csv    — comma-separated target-environment strings to exclude
#   $4  env_yaml_source  — path or URL to the environment-code YAML
# ---------------------------------------------------------------------------
patch_cd_service_trigger_override() {
    local team_slug="$1"
    local service_slug="$2"
    local excludes_csv="$3"
    local env_yaml_source="$4"

    local account_type="${ACCOUNT_TYPE:-dev}"
    account_type="${account_type,,}"
    [[ "$account_type" == "prod" ]] || account_type="dev"

    local pv_file="${TOOLCHAINS_CLONE_DIR}/${team_slug}-cd-pipeline_vars.tf"

    if [ "$ENABLE_TRIGGER_CREATION" != "true" ]; then
        echo -e "${YELLOW}[INFO]${NC} Trigger creation disabled (ENABLE_TRIGGER_CREATION=${ENABLE_TRIGGER_CREATION}) — skipping service trigger override for ${team_slug}/${service_slug}"
        return 0
    fi

    if [ ! -f "$pv_file" ]; then
        echo -e "${YELLOW}[WARNING]${NC} CD pipeline_vars file not found — skipping service override patch: ${pv_file}" >&2
        return 0
    fi

    echo -e "${BLUE}[INFO]${NC} Patching CD service trigger override for ${team_slug}/${service_slug} (excludes: ${excludes_csv})"

    python3 "$GENERATE_TRIGGERS_PY" \
        --env-yaml      "$env_yaml_source" \
        --team-slug     "$team_slug" \
        --account-type  "$account_type" \
        --tf-file       "$pv_file" \
        --excludes      "$excludes_csv" \
        --service-slug  "$service_slug" \
        2>&1 | while IFS= read -r line; do
            echo -e "${BLUE}[INFO]${NC} [triggers] ${line}"
        done

    local py_exit="${PIPESTATUS[0]}"
    if [ "$py_exit" -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} generate_cd_triggers.py (service override) failed (exit ${py_exit}) for ${service_slug}" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Function: get_cd_trigger_local_ref
#
# Prints the Terraform local variable name for pipeline_types_trigger_data
# that a toolchain entry should reference.
#
#   No excludes → <team_underscore>_cd_pipeline_types_trigger_data
#                 (the team-level pointer, already updated to the tier default)
#
#   Has excludes → <team_underscore>_cd_pipeline_types_trigger_data_<service_underscore>
#                  (the standalone service-specific filtered list)
#
# Args:
#   $1  team_slug
#   $2  service_slug   — hyphenated (e.g. auth-service)
#   $3  has_excludes   — "true" | "false"
# ---------------------------------------------------------------------------
get_cd_trigger_local_ref() {
    local team_slug="$1"
    local service_slug="$2"
    local has_excludes="$3"

    local team_us="${team_slug//-/_}"

    if [ "$has_excludes" = "true" ]; then
        local svc_us="${service_slug//-/_}"
        echo "${team_us}_cd_pipeline_types_trigger_data_${svc_us}"
    else
        echo "${team_us}_cd_pipeline_types_trigger_data"
    fi
}

# ---------------------------------------------------------------------------
# Function: extract_cd_excludes_from_onboarding
#
# Reads deployment_targets.CD from the onboarding YAML and returns a
# comma-separated list of target-environments (env_code-cluster strings)
# that should be excluded for the given account type.
#
# For account_type=dev  → reads deployment_targets.CD.integration.exclude
# For account_type=prod → reads deployment_targets.CD.staging.exclude +
#                                deployment_targets.CD.production.exclude
#
# Prints a single comma-separated string to stdout (empty if no excludes).
#
# Args:
#   $1  onboarding_file
# ---------------------------------------------------------------------------
extract_cd_excludes_from_onboarding() {
    local onboarding_file="$1"
    local account_type="${ACCOUNT_TYPE:-dev}"
    account_type="${account_type,,}"
    [[ "$account_type" == "prod" ]] || account_type="dev"

    python3 - "$onboarding_file" "$account_type" <<'PYEOF'
import sys, yaml

onboarding_file = sys.argv[1]
account_type    = sys.argv[2]

try:
    with open(onboarding_file) as f:
        config = yaml.safe_load(f)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)

cd_targets = (config.get('deployment_targets') or {}).get('CD') or {}

if account_type == 'dev':
    tiers = ['integration']
else:
    tiers = ['staging', 'production']

excludes = []
for tier in tiers:
    tier_data = cd_targets.get(tier) or {}
    for item in (tier_data.get('exclude') or []):
        val = str(item).strip()
        if val and val not in excludes:
            excludes.append(val)

print(','.join(excludes))
PYEOF
}

# ---------------------------------------------------------------------------
# Function: patch_cd_toolchain_trigger_ref
#
# For an existing toolchain entry (already present in the .tf file), patches
# the pipeline_types_trigger_data line inside that block to point to the
# correct trigger local ref.
#
# Uses the inventory_repo_url to locate the right block — the same key used
# by toolchain_entry_status_in_tf — then replaces only the
# pipeline_types_trigger_data assignment within that block.
#
# Returns:
#   0 — file was patched (ref was stale)
#   1 — nothing to patch (already correct) or block not found
#
# Args:
#   $1  tf_file         — absolute path to the toolchains .tf file
#   $2  inv_repo_url    — inventory_repo_url to locate the block
#   $3  trigger_ref     — new local name (without "local." prefix)
# ---------------------------------------------------------------------------
patch_cd_toolchain_trigger_ref() {
    local tf_file="$1"
    local inv_repo="$2"
    local trigger_ref="$3"

    local inv_bare="${inv_repo%.git}"

    python3 - "$tf_file" "$inv_bare" "$trigger_ref" <<'PYEOF'
import sys, re

tf_file     = sys.argv[1]
inv_bare    = sys.argv[2]
trigger_ref = sys.argv[3]

with open(tf_file) as f:
    content = f.read()

inv_pattern = re.escape(inv_bare) + r'(?:\.git)?["\']'

# ── Locate the toolchains = [ ... ] list ────────────────────────────────────
# Toolchain entry blocks are nested *inside* the list, not at file top-level,
# so we must first find the list boundaries and scan only inside it.
list_match = re.search(r'\btoolchains\s*=\s*\[', content)
if not list_match:
    print("ERROR: could not locate 'toolchains = [' in file", file=sys.stderr)
    sys.exit(1)

list_start = list_match.end()
depth = 1
list_end = None
for idx in range(list_start, len(content)):
    ch = content[idx]
    if ch == '[':
        depth += 1
    elif ch == ']':
        depth -= 1
        if depth == 0:
            list_end = idx
            break

if list_end is None:
    print("ERROR: could not locate closing ']' for toolchains list", file=sys.stderr)
    sys.exit(1)

# ── Collect { ... } blocks inside the list ──────────────────────────────────
list_body = content[list_start:list_end]
list_offset = list_start

block_ranges = []
depth = 0
block_start = None
for i, ch in enumerate(list_body):
    if ch == '{':
        if depth == 0:
            block_start = i
        depth += 1
    elif ch == '}':
        depth -= 1
        if depth == 0 and block_start is not None:
            # Store absolute positions in content
            block_ranges.append((list_offset + block_start, list_offset + i + 1))
            block_start = None

# ── Find the block whose body contains the target inventory_repo_url ─────────
target_range = None
for start, end in block_ranges:
    block_body = content[start:end]
    # Skip commented-out blocks (majority of text is #-prefixed lines)
    uncommented = re.sub(r'#[^\n]*', '', block_body)
    if re.search(inv_pattern, uncommented):
        target_range = (start, end)
        break

if target_range is None:
    print(f"INFO: block for '{inv_bare}' not found — skipping trigger ref patch", file=sys.stderr)
    sys.exit(1)

block_body = content[target_range[0]:target_range[1]]

# ── Patch pipeline_types_trigger_data inside the located block ───────────────
pat = re.compile(r'(pipeline_types_trigger_data\s*=\s*)local\.\S+')
current = pat.search(block_body)
if not current:
    print("INFO: pipeline_types_trigger_data not found in block — skipping", file=sys.stderr)
    sys.exit(1)

expected = f"local.{trigger_ref}"
if current.group(0).split('=', 1)[1].strip() == expected:
    print(f"INFO: pipeline_types_trigger_data already set to {expected} — no patch needed", file=sys.stderr)
    sys.exit(1)

new_block = pat.sub(r'\g<1>' + expected, block_body, count=1)
new_content = content[:target_range[0]] + new_block + content[target_range[1]:]

with open(tf_file, 'w') as f:
    f.write(new_content)

print(f"INFO: patched pipeline_types_trigger_data → {expected}", file=sys.stderr)
sys.exit(0)
PYEOF
}

# ---------------------------------------------------------------------------
# Function: team_cd_branch_exists
#
# Returns 0 if <team-slug>-cd already exists on the remote, 1 otherwise.
# ---------------------------------------------------------------------------
team_cd_branch_exists() {
    local branch_name="$1"
    cd "${TOOLCHAINS_CLONE_DIR}"
    git fetch origin "$branch_name" &>/dev/null || true
    git show-ref --verify --quiet "refs/remotes/origin/${branch_name}"
}

# ---------------------------------------------------------------------------
# Function: scaffold_team_cd_branch
#
# Creates a brand-new <team-slug>-cd branch in the toolchains repo by
# delegating directly to create-team-branch.sh with deployment-type "cd".
#
# create-team-branch.sh is the canonical way to initialise a team branch;
# calling it here keeps the two code paths in sync automatically — any
# future template changes in templates/cd/ are picked up for free.
#
# Args:
#   $1  team_name      — human-readable (e.g. "Core Services")
#   $2  team_slug      — hyphenated lowercase (e.g. "core-services")
#   $3  secret_group   — e.g. "sg-uuc-core-services"
#   $4  resource_group — e.g. "UUC_Core_Services"
# ---------------------------------------------------------------------------
scaffold_team_cd_branch() {
    local team_name="$1"
    local team_slug="$2"
    local secret_group="$3"
    local resource_group="$4"
    local branch_name="${team_slug}-cd"

    echo -e "${BLUE}[INFO]${NC} Scaffolding new CD branch '${branch_name}' via create-team-branch.sh (local only, no push)..."

    # create-team-branch.sh lives on main of the toolchains repo.
    # TOOLCHAINS_CLONE_DIR is currently on main (cloned above), so the
    # scripts/ and templates/ directories are present and accessible.
    local create_branch_script="${TOOLCHAINS_CLONE_DIR}/scripts/create-team-branch.sh"

    if [ ! -f "$create_branch_script" ]; then
        echo -e "${RED}[ERROR]${NC} create-team-branch.sh not found at: ${create_branch_script}" >&2
        echo -e "${RED}[ERROR]${NC} Ensure TOOLCHAINS_CLONE_DIR is on the main branch." >&2
        return 1
    fi

    # Run from within the cloned repo so all relative paths work.
    # Pass 'yes' via stdin to bypass the interactive confirmation prompt.
    # NO_PUSH=true suppresses the final 'git push' inside create-team-branch.sh
    # so the scaffolded branch only exists locally.  The toolchain block and
    # terraform fmt are applied on top before create_cd_toolchains_pr() pushes
    # the single PR branch — keeping the remote clean until then.
    # Args: <team-name> <deployment-type> <secret-group> <resource-group>
    (
        cd "${TOOLCHAINS_CLONE_DIR}"
        git config user.name "clconc"
        git config user.email "clconc@us.ibm.com"
        echo "yes" | NO_PUSH=true bash "$create_branch_script" \
            "$team_name" \
            "cd" \
            "$secret_group" \
            "$resource_group"
    ) || {
        echo -e "${RED}[ERROR]${NC} create-team-branch.sh failed for team '${team_name}'" >&2
        return 1
    }

    # The branch now exists locally only.  Switch to it so subsequent git
    # commands in create_cd_toolchains_pr() operate on the correct branch.
    cd "${TOOLCHAINS_CLONE_DIR}"
    git checkout "$branch_name"

    echo -e "${GREEN}[SUCCESS]${NC} Scaffolded CD branch '${branch_name}' locally for ${team_name} (not yet pushed)"
}

# ---------------------------------------------------------------------------
# Function: toolchain_entry_status_in_tf
#
# Prints one of three status strings to stdout and always exits 0:
#   "exact"  — entry found and all checked fields match the onboarding YAML
#   "stale"  — entry found by pipeline_name but one or more fields differ
#   "missing"— no entry found for this pipeline_name
#
# Identity anchor: pipeline_name (slug of service_name).
#
# Rename / offboard handling:
#   When a user renames the onboarding file (git mv) and changes service_name,
#   get_deleted_onboarding_files() detects the deleted old file, the main() loop
#   reads the old service_name via git show HEAD~1, derives the old pipeline_name,
#   and passes it as --offboard so this block is removed before the new one is
#   appended.  The net result is offboard + new onboard in a single PR.
#
# For CD toolchains inventory_repo_url, incident_repo_url, and servicenow_crn
# may change when the onboarding YAML is updated.
#
# Args:
#   $1  tf_file           — absolute path to the toolchains .tf file
#   $2  service_name      — used to derive pipeline_name (the stable identity)
#   $3  inventory_repo_url
#   $4  incident_repo_url
#   $5  servicenow_crn    — current value from onboarding YAML (may be empty)
# ---------------------------------------------------------------------------
toolchain_entry_status_in_tf() {
    local tf_file="$1"
    local service_name="$2"
    local inv_repo="$3"
    local inc_repo="$4"
    local servicenow_crn="${5:-}"

    [ -f "$tf_file" ] || { echo "missing"; return 0; }

    # Derive pipeline_name slug (mirrors generate_toolchain_block)
    local pipeline_name
    pipeline_name=$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr ' ' '-')

    # Strip trailing .git for a loose match — some entries may omit it
    local inv_bare="${inv_repo%.git}"
    local inc_bare="${inc_repo%.git}"

    python3 - <<EOF
import sys, re

tf_file         = '$tf_file'
pipeline_name   = '$pipeline_name'
inv_bare        = '$inv_bare'
inc_bare        = '$inc_bare'
servicenow_crn  = '$servicenow_crn'

with open(tf_file) as f:
    content = f.read()

def url_present_in_block(block, bare_url):
    """True if bare_url (with or without .git) appears in an uncommented line of block."""
    if not bare_url:
        return True
    pattern = re.escape(bare_url) + r'(?:\.git)?["\']'
    uncommented = re.sub(r'#[^\n]*', '', block)
    return bool(re.search(pattern, uncommented))

def crn_matches_in_block(block, crn):
    """True when the servicenow_crn value in tc_env_props matches crn.

    Two cases:
      - crn is non-empty: the block must contain  value = "<crn>"  inside a
        servicenow_crn property object on an uncommented line.
      - crn is empty: the block must NOT contain a servicenow_crn property
        object (i.e. tc_env_props must be the bare team-level local, not a
        merge(...) expression).
    """
    uncommented = re.sub(r'#[^\n]*', '', block)
    has_crn_value = bool(re.search(r'"servicenow_crn"\s*=\s*\{', uncommented))
    if crn:
        # Expect servicenow_crn block present with matching value
        if not has_crn_value:
            return False
        return bool(re.search(r'value\s*=\s*"' + re.escape(crn) + r'"', uncommented))
    else:
        # Expect no servicenow_crn block at all
        return not has_crn_value

# ── Locate the toolchains = [ ... ] list ─────────────────────────────────────
list_match = re.search(r'\btoolchains\s*=\s*\[', content)
if not list_match:
    print("missing")
    sys.exit(0)

list_start = list_match.end()
depth = 1
list_end = None
for idx in range(list_start, len(content)):
    ch = content[idx]
    if ch == '[':
        depth += 1
    elif ch == ']':
        depth -= 1
        if depth == 0:
            list_end = idx
            break

if list_end is None:
    print("missing")
    sys.exit(0)

# ── Collect { ... } blocks inside the list ───────────────────────────────────
list_body   = content[list_start:list_end]
list_offset = list_start

block_ranges = []
depth = 0
block_start = None
for i, ch in enumerate(list_body):
    if ch == '{':
        if depth == 0:
            block_start = i
        depth += 1
    elif ch == '}':
        depth -= 1
        if depth == 0 and block_start is not None:
            block_ranges.append((list_offset + block_start, list_offset + i + 1))
            block_start = None

# ── Find block by pipeline_name ───────────────────────────────────────────────
# Also match the underscore variant so that legacy blocks written with raw
# underscores (e.g. "uuc_ns3_host_configs") are found by the hyphen slug.
pipeline_name_us = pipeline_name.replace('-', '_')
name_pattern = re.compile(
    r'pipeline_name\s*=\s*"(?:' + re.escape(pipeline_name) + r'|' + re.escape(pipeline_name_us) + r')"'
)

target_block = None
for start, end in block_ranges:
    block_body = content[start:end]
    if name_pattern.search(block_body):
        target_block = block_body
        break

if target_block is None:
    print("missing")
    sys.exit(0)

# ── Check whether all tracked fields match ───────────────────────────────────
all_match = (
    url_present_in_block(target_block, inv_bare) and
    url_present_in_block(target_block, inc_bare) and
    crn_matches_in_block(target_block, servicenow_crn)
)

print("exact" if all_match else "stale")
sys.exit(0)
EOF
}

# ---------------------------------------------------------------------------
# Function: update_cd_toolchain_repos_in_tf
#
# Finds the CD toolchain block identified by pipeline_name and patches any
# repo URL fields that differ from the values supplied.
#
# Fields updated (when changed):
#   repo               ← inv_repo_url  (inventory repo IS the app repo for CD)
#   inventory_repo_url ← inv_repo_url
#   incident_repo_url  ← inc_repo_url
#
# Returns:
#   0 — one or more fields were patched
#   1 — all fields already up to date (or block not found)
#
# Args:
#   $1  tf_file
#   $2  service_name   — used to derive pipeline_name
#   $3  inventory_repo_url
#   $4  incident_repo_url
# ---------------------------------------------------------------------------
update_cd_toolchain_repos_in_tf() {
    local tf_file="$1"
    local service_name="$2"
    local inv_repo="$3"
    local inc_repo="$4"

    local pipeline_name
    pipeline_name=$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr ' ' '-')

    # Ensure .git suffix on URLs
    local inv_repo_git="${inv_repo%.git}.git"
    local inc_repo_git="${inc_repo%.git}.git"

    python3 - "$tf_file" "$pipeline_name" "$inv_repo_git" "$inc_repo_git" <<'PYEOF'
import sys, re

tf_file       = sys.argv[1]
pipeline_name = sys.argv[2]
inv_repo      = sys.argv[3]
inc_repo      = sys.argv[4]

with open(tf_file) as f:
    content = f.read()

# ── Locate the toolchains = [ ... ] list ─────────────────────────────────────
list_match = re.search(r'\btoolchains\s*=\s*\[', content)
if not list_match:
    print("ERROR: could not locate 'toolchains = [' in file", file=sys.stderr)
    sys.exit(1)

list_start = list_match.end()
depth = 1
list_end = None
for idx in range(list_start, len(content)):
    ch = content[idx]
    if ch == '[':
        depth += 1
    elif ch == ']':
        depth -= 1
        if depth == 0:
            list_end = idx
            break

if list_end is None:
    print("ERROR: could not locate closing ']' for toolchains list", file=sys.stderr)
    sys.exit(1)

list_body   = content[list_start:list_end]
list_offset = list_start

block_ranges = []
depth = 0
block_start = None
for i, ch in enumerate(list_body):
    if ch == '{':
        if depth == 0:
            block_start = i
        depth += 1
    elif ch == '}':
        depth -= 1
        if depth == 0 and block_start is not None:
            block_ranges.append((list_offset + block_start, list_offset + i + 1))
            block_start = None

# ── Find block by pipeline_name ───────────────────────────────────────────────
# Also match the underscore variant so that legacy blocks written with raw
# underscores (e.g. "uuc_ns3_host_configs") are found by the hyphen slug.
pipeline_name_us = pipeline_name.replace('-', '_')
name_pattern = re.compile(
    r'pipeline_name\s*=\s*"(?:' + re.escape(pipeline_name) + r'|' + re.escape(pipeline_name_us) + r')"'
)
target_range = None
for start, end in block_ranges:
    if name_pattern.search(content[start:end]):
        target_range = (start, end)
        break

if target_range is None:
    print(f"WARNING: block for pipeline_name='{pipeline_name}' not found", file=sys.stderr)
    sys.exit(1)

block_body    = content[target_range[0]:target_range[1]]
patched       = False

def patch_field(body, field_name, new_value):
    """Replace the quoted value of a simple string assignment field in the block."""
    pat = re.compile(r'(' + re.escape(field_name) + r'\s*=\s*)"[^"]*"')
    new_body = pat.sub(r'\g<1>"' + new_value + '"', body, count=1)
    changed = new_body != body
    return new_body, changed

# repo (inventory repo acts as app repo for CD — both `repo` and `inventory_repo_url` point here)
block_body, changed = patch_field(block_body, 'repo', inv_repo)
if changed:
    patched = True
    print(f"INFO: patched repo → \"{inv_repo}\"", file=sys.stderr)

# inventory_repo_url
block_body, changed = patch_field(block_body, 'inventory_repo_url', inv_repo)
if changed:
    patched = True
    print(f"INFO: patched inventory_repo_url → \"{inv_repo}\"", file=sys.stderr)

# incident_repo_url
block_body, changed = patch_field(block_body, 'incident_repo_url', inc_repo)
if changed:
    patched = True
    print(f"INFO: patched incident_repo_url → \"{inc_repo}\"", file=sys.stderr)

if not patched:
    print("INFO: all repo URL fields already up to date — no patch needed", file=sys.stderr)
    sys.exit(1)
# Note: servicenow_crn / tc_env_props is patched separately by
# patch_cd_toolchain_servicenow_crn() after this function returns.

new_content = content[:target_range[0]] + block_body + content[target_range[1]:]
with open(tf_file, 'w') as f:
    f.write(new_content)
sys.exit(0)
PYEOF
}

# ---------------------------------------------------------------------------
# Function: patch_cd_toolchain_servicenow_crn
#
# Rewrites the tc_env_props assignment inside an existing CD toolchain block
# to reflect the current servicenow_crn from the onboarding YAML.
#
# Three cases handled:
#   1. crn non-empty, block already has merge(...)  → replace value = "..." only
#   2. crn non-empty, block has bare local ref      → replace whole tc_env_props line
#      with merge(local.<team>_cd_tc_env_props, { "servicenow_crn" = { ... } })
#   3. crn empty,     block has merge(...)          → revert tc_env_props to bare local ref
#
# Returns:
#   0 — file was modified
#   1 — already correct / block not found — no change
#
# Args:
#   $1  tf_file
#   $2  service_name   — used to derive pipeline_name
#   $3  servicenow_crn — new value (may be empty)
#   $4  team_slug
# ---------------------------------------------------------------------------
patch_cd_toolchain_servicenow_crn() {
    local tf_file="$1"
    local service_name="$2"
    local servicenow_crn="$3"
    local team_slug="$4"

    [ -f "$tf_file" ] || return 1

    local pipeline_name team_underscore
    pipeline_name=$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr ' ' '-')
    team_underscore="${team_slug//-/_}"

    python3 - "$tf_file" "$pipeline_name" "$servicenow_crn" "$team_underscore" <<'PYEOF'
import sys, re

tf_file        = sys.argv[1]
pipeline_name  = sys.argv[2]
servicenow_crn = sys.argv[3]
team_us        = sys.argv[4]

bare_local     = f"local.{team_us}_cd_tc_env_props"
merge_template = (
    f'merge(local.{team_us}_cd_tc_env_props, {{\n'
    f'        "servicenow_crn" = {{\n'
    f'          type         = "text"\n'
    f'          value        = "{servicenow_crn}"\n'
    f'          locked       = true\n'
    f'          secret_group = var.secret_group\n'
    f'        }}\n'
    f'      }})'
)

with open(tf_file) as f:
    content = f.read()

# ── Locate the toolchains = [ ... ] list ─────────────────────────────────────
list_match = re.search(r'\btoolchains\s*=\s*\[', content)
if not list_match:
    print("ERROR: could not locate 'toolchains = [' in file", file=sys.stderr)
    sys.exit(1)

list_start = list_match.end()
depth = 1
list_end = None
for idx in range(list_start, len(content)):
    ch = content[idx]
    if ch == '[': depth += 1
    elif ch == ']':
        depth -= 1
        if depth == 0:
            list_end = idx
            break

if list_end is None:
    print("ERROR: could not locate closing ']' for toolchains list", file=sys.stderr)
    sys.exit(1)

list_body   = content[list_start:list_end]
list_offset = list_start

block_ranges = []
depth = 0
block_start = None
for i, ch in enumerate(list_body):
    if ch == '{':
        if depth == 0:
            block_start = i
        depth += 1
    elif ch == '}':
        depth -= 1
        if depth == 0 and block_start is not None:
            block_ranges.append((list_offset + block_start, list_offset + i + 1))
            block_start = None

pipeline_name_us = pipeline_name.replace('-', '_')
name_pattern = re.compile(
    r'pipeline_name\s*=\s*"(?:' + re.escape(pipeline_name) + r'|' + re.escape(pipeline_name_us) + r')"'
)
target_range = None
for start, end in block_ranges:
    if name_pattern.search(content[start:end]):
        target_range = (start, end)
        break

if target_range is None:
    print(f"WARNING: block for pipeline_name='{pipeline_name}' not found — skipping CRN patch", file=sys.stderr)
    sys.exit(1)

block_body = content[target_range[0]:target_range[1]]

# ── Locate the tc_env_props assignment within the block ──────────────────────
# Pattern captures everything from 'tc_env_props' up to (but not including)
# the next top-level key assignment or the closing brace.  We use a
# bracket-depth walk to handle the nested merge(...{ ... }) correctly.
tc_pat = re.compile(r'tc_env_props\s*=\s*', re.MULTILINE)
m = tc_pat.search(block_body)
if not m:
    print("WARNING: tc_env_props not found in block — skipping CRN patch", file=sys.stderr)
    sys.exit(1)

# Walk from the end of 'tc_env_props = ' to find where the value ends.
# Value ends at the first newline that is NOT inside a nested { } or ( ).
val_start = m.end()
pos       = val_start
brace_d   = 0
paren_d   = 0
val_end   = len(block_body)
for i in range(val_start, len(block_body)):
    ch = block_body[i]
    if ch == '{': brace_d += 1
    elif ch == '}':
        if brace_d > 0:
            brace_d -= 1
        else:
            # Closing brace of the toolchain block itself — stop here
            val_end = i
            break
    elif ch == '(': paren_d += 1
    elif ch == ')':
        paren_d -= 1
    elif ch == '\n' and brace_d == 0 and paren_d == 0:
        val_end = i + 1   # include the newline
        break

current_value = block_body[val_start:val_end].rstrip()

# ── Determine what the new value should be ───────────────────────────────────
if servicenow_crn:
    # Case 1: merge already present — replace only the value = "..." line
    crn_val_pat = re.compile(r'(value\s*=\s*)"[^"]*"')
    if '"servicenow_crn"' in current_value:
        new_value = crn_val_pat.sub(r'\g<1>"' + servicenow_crn + '"', current_value, count=1)
        if new_value == current_value:
            print("INFO: servicenow_crn already up to date — no patch needed", file=sys.stderr)
            sys.exit(1)
    else:
        # Case 2: bare local ref — replace whole value with merge(...)
        new_value = merge_template
else:
    # Case 3: crn removed — revert to bare local ref
    if '"servicenow_crn"' not in current_value:
        print("INFO: tc_env_props already bare local ref — no patch needed", file=sys.stderr)
        sys.exit(1)
    new_value = bare_local

new_block = block_body[:m.end()] + new_value + '\n' + block_body[val_end:]
new_content = content[:target_range[0]] + new_block + content[target_range[1]:]

with open(tf_file, 'w') as f:
    f.write(new_content)

print(f"INFO: patched tc_env_props (servicenow_crn → \"{servicenow_crn}\")", file=sys.stderr)
sys.exit(0)
PYEOF
}

# ---------------------------------------------------------------------------
# Function: generate_toolchain_block
#
# Emits a single CD toolchain entry { ... } ready to be appended inside the
# toolchains = [ ... ] list in the <team-slug>-cd-toolchains.tf file.
#
# CD field mapping (source → toolchain .tf):
#   onboarding.yaml inventory_repo.repo → repo               (inventory repo IS the app repo for CD)
#   onboarding.yaml inventory_repo.repo → inventory_repo_url (same URL, both fields point here)
#   onboarding.yaml incident_repo.repo  → incident_repo_url  (actual incident repo)
#
# Args:
#   $1  team_slug
#   $2  service_name
#   $3  inventory_repo_url — from onboarding.yaml inventory_repo.repo; used as repo AND inventory_repo_url
#   $4  incident_repo_url  — from onboarding.yaml incident_repo.repo
# ---------------------------------------------------------------------------
generate_toolchain_block() {
    local team_slug="$1"
    local service_name="$2"
    local inv_repo="$3"   # inventory repo = app repo for CD
    local inc_repo="$4"   # actual incident repo from onboarding.yaml
    local trigger_local_ref="$5"  # terraform local name for pipeline_types_trigger_data
    local servicenow_crn="$6"     # ServiceNow CRN from onboarding YAML

    # service_slug: lowercase hyphenated form of service_name
    local service_slug team_underscore
    service_slug=$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr ' ' '-')
    team_underscore="${team_slug//-/_}"

    # Default trigger ref: team-level pointer (already updated to tier default)
    if [ -z "$trigger_local_ref" ]; then
        trigger_local_ref="${team_underscore}_cd_pipeline_types_trigger_data"
    fi

    # GUID prefix = service slug  (e.g. "ns3-ntpsec-<uuid>")
    local guid
    guid=$(python3 -c "import uuid; print('${service_slug}-' + str(uuid.uuid4()))")

    # Ensure all repo URLs carry a .git suffix
    local inv_repo_git inc_repo_git
    inv_repo_git="${inv_repo%.git}.git"
    inc_repo_git="${inc_repo%.git}.git"

    # tc_env_props: merge the team-level local with the per-service servicenow_crn
    local tc_env_props_hcl
    if [ -n "$servicenow_crn" ]; then
        tc_env_props_hcl='merge(local.'"${team_underscore}"'_cd_tc_env_props, {
        "servicenow_crn" = {
          type         = "text"
          value        = "'"${servicenow_crn}"'"
          locked       = true
          secret_group = var.secret_group
        }
      })'
    else
        tc_env_props_hcl="local.${team_underscore}_cd_tc_env_props"
    fi

    cat <<EOF
    {
      guid               = "${guid}" # Generate unique GUID using 'uuidgen' locally or online tool
      name               = "${service_slug}-cd-toolchain"
      repo               = "${inv_repo_git}"          # inventory repo acts as the app repo for CD
      inventory_repo_url = "${inv_repo_git}"
      incident_repo_url  = "${inc_repo_git}"
      pipeline_name      = "${service_slug}"
      tags               = ["team:${team_slug}", "type:cd", "template:uuc_common_cd"]
      resource_grp       = var.resource_group
      # ---------------------------------------------------------------------------------
      # - ENV PROPS (toolchain) THAT WILL BE COPIED TO EACH PIPELINE OF A GIVEN TOOLCHAIN
      # ---------------------------------------------------------------------------------
      tc_env_props                = ${tc_env_props_hcl}
      pipeline_types_trigger_data = local.${trigger_local_ref}
      # ---------------------------------------------------------------------------------
      # - PIPELINE SPECIFIC METADATA (pipeline) ie ENV PROPERTIES FOR A GIVEN PIPELINE
      # ---------------------------------------------------------------------------------
      pipeline_meta = local.${team_underscore}_cd_pipeline_meta_default
    }
EOF
}

# ---------------------------------------------------------------------------
# Function: append_toolchain_to_tf
#
# Inserts a new toolchain block into the toolchains = [ ... ] list inside the
# team's <team-slug>-cd-toolchains.tf file, just before the closing ].
# Uses Python for reliable bracket-depth tracking.
#
# Args:
#   $1  tf_file         — absolute path to the toolchains .tf file
#   $2  toolchain_block — multi-line HCL string to inject
# ---------------------------------------------------------------------------
append_toolchain_to_tf() {
    local tf_file="$1"
    local toolchain_block="$2"

    python3 - "$tf_file" "$toolchain_block" <<'PYEOF'
import sys, re

tf_file         = sys.argv[1]
toolchain_block = sys.argv[2]

with open(tf_file) as f:
    lines = f.readlines()

content = ''.join(lines)
start_match = re.search(r'toolchains\s*=\s*\[', content)
if not start_match:
    print("ERROR: could not locate 'toolchains = [' block in file", file=sys.stderr)
    sys.exit(1)

list_start = start_match.end()
depth = 1
list_end = None
for idx in range(list_start, len(content)):
    ch = content[idx]
    if ch == '[':
        depth += 1
    elif ch == ']':
        depth -= 1
        if depth == 0:
            list_end = idx
            break

if list_end is None:
    print("ERROR: could not locate closing ']' for toolchains list", file=sys.stderr)
    sys.exit(1)

prefix = content[:list_start]
body = content[list_start:list_end]
suffix = content[list_end:]

body = body.rstrip()
if body.endswith('}'):
    body += ','

new_content = prefix + body + '\n' + toolchain_block.rstrip('\n') + suffix

with open(tf_file, 'w') as f:
    f.write(new_content)

print(f"INFO: Appended CD toolchain block to {tf_file}", file=sys.stderr)
sys.exit(0)

PYEOF
}

# ---------------------------------------------------------------------------
# Function: remove_toolchain_from_tf
#
# Finds the CD toolchain block identified by pipeline_name and removes it
# from the toolchains = [ ... ] list, cleaning up surrounding commas and
# blank lines to keep the file well-formed.
#
# Returns:
#   0 — block found and removed
#   1 — block not found — no file change
#
# Args:
#   $1  tf_file
#   $2  pipeline_name  — exact slug to search for
# ---------------------------------------------------------------------------
remove_toolchain_from_tf() {
    local tf_file="$1"
    local pipeline_name="$2"

    [ -f "$tf_file" ] || return 1

    python3 - "$tf_file" "$pipeline_name" <<'PYEOF'
import sys, re

tf_file       = sys.argv[1]
pipeline_name = sys.argv[2]

with open(tf_file) as f:
    content = f.read()

list_match = re.search(r'\btoolchains\s*=\s*\[', content)
if not list_match:
    print("ERROR: could not locate 'toolchains = [' in file", file=sys.stderr)
    sys.exit(1)

list_start = list_match.end()
depth = 1
list_end = None
for idx in range(list_start, len(content)):
    ch = content[idx]
    if ch == '[':
        depth += 1
    elif ch == ']':
        depth -= 1
        if depth == 0:
            list_end = idx
            break

if list_end is None:
    print("ERROR: could not locate closing ']' for toolchains list", file=sys.stderr)
    sys.exit(1)

list_body   = content[list_start:list_end]
list_offset = list_start

block_ranges = []
depth = 0
block_start = None
for i, ch in enumerate(list_body):
    if ch == '{':
        if depth == 0:
            block_start = i
        depth += 1
    elif ch == '}':
        depth -= 1
        if depth == 0 and block_start is not None:
            block_ranges.append((list_offset + block_start, list_offset + i + 1))
            block_start = None

# Also match the underscore variant so that legacy blocks are found by the
# hyphen slug (e.g. "uuc_ns3_host_configs" matched by "uuc-ns3-host-configs").
pipeline_name_us = pipeline_name.replace('-', '_')
name_pattern = re.compile(
    r'pipeline_name\s*=\s*"(?:' + re.escape(pipeline_name) + r'|' + re.escape(pipeline_name_us) + r')"'
)
target_range = None
for start, end in block_ranges:
    if name_pattern.search(content[start:end]):
        target_range = (start, end)
        break

if target_range is None:
    print(f"INFO: no block found for pipeline_name='{pipeline_name}' — nothing to remove", file=sys.stderr)
    sys.exit(1)

remove_start = target_range[0]
remove_end   = target_range[1]

tail = content[remove_end:]
m = re.match(r'\s*,', tail)
if m:
    remove_end += m.end()

head = content[:remove_start]
m = re.search(r'\n[ \t]*$', head)
if m:
    remove_start = remove_start - (len(head) - m.start())

new_content = content[:remove_start] + content[remove_end:]
with open(tf_file, 'w') as f:
    f.write(new_content)

print(f"INFO: Removed CD toolchain block for pipeline_name='{pipeline_name}'", file=sys.stderr)
sys.exit(0)
PYEOF
}

# ---------------------------------------------------------------------------
# Function: create_cd_toolchains_pr
#
# Orchestrates the full flow for one team:
#   1. Create/checkout the team CD branch.
#   2. Scaffold it from templates/cd/ if new (via create-team-branch.sh).
#   3. Remove offboarded toolchains (deleted/renamed onboarding files).
#   4. For each onboarding file: check existing entries, append/update blocks.
#   5. Create a PR branch, commit, push, open PR via GH API.
#
# Args:
#   $1  team_name
#   $2  team_slug
#   $3  is_new_branch   — "true" | "false"
#   --offboard <pipeline_name>...  (optional) pipeline_names to remove before processing
#   $4+ onboarding_files (absolute paths, one per service for this team)
#
# Sets CREATED_TOOLCHAINS_PR_URL and CREATED_TOOLCHAINS_PR_NUMBER on success.
# Returns:
#   0 — PR created
#   1 — error
#   2 — no changes (all toolchains already present)
# ---------------------------------------------------------------------------
create_cd_toolchains_pr() {
    local team_name="$1"
    local team_slug="$2"
    local is_new_branch="$3"
    shift 3

    # Parse optional --offboard <name>... flag before the onboarding files list
    local offboard_names=()
    while [[ "${1:-}" == "--offboard" ]]; do
        shift
        while [[ $# -gt 0 && "$1" != "--"* && "$1" != /* ]]; do
            offboard_names+=("$1")
            shift
        done
    done

    local onboarding_files=("$@")

    local team_branch="${team_slug}-cd"
    local tf_filename="${team_slug}-cd-toolchains.tf"

    local action="Onboard"
    [ "$is_new_branch" = "false" ] && action="Update"

    local pr_title="feat: Add ${team_name} CD toolchains"

    cd "${TOOLCHAINS_CLONE_DIR}"

    # ── Set up team branch ────────────────────────────────────────────────────
    if [ "$is_new_branch" = "true" ]; then
        local secret_group="sg-uuc-${team_slug}"
        local resource_group
        resource_group="UUC_$(echo "${team_name}" | tr ' ' '_')"

        scaffold_team_cd_branch "$team_name" "$team_slug" "$secret_group" "$resource_group"
    else
        echo -e "${BLUE}[INFO]${NC} Checking out existing team branch: ${team_branch}"
        git fetch origin "$team_branch"
        git checkout "$team_branch"
        git reset --hard "origin/${team_branch}"
    fi

    # ── Patch pipeline_vars FID and CD trigger data ───────────────────────────
    # These steps require at least one onboarding file to read from.
    # In a pure-offboard scenario (only --offboard args, no new/changed files)
    # onboarding_files is empty — skip both blocks entirely so we don't emit
    # "[ERROR] Onboarding file not found: " or misleading "ci_only/minimal" messages.
    local _env_yaml_source
    _env_yaml_source=$(resolve_env_code_yaml "$team_slug")

    if [ ${#onboarding_files[@]} -gt 0 ]; then
        # Extract FIDs from the first onboarding file; they must be consistent
        # across all files for a given team (documented in onboarding.yaml).
        local _first_tc_info _fid_dev _fid_prod
        _first_tc_info=$(extract_toolchain_info_from_onboarding "${onboarding_files[0]}") || true
        IFS='|' read -r _ _ _ _ _ _fid_dev _fid_prod <<< "$_first_tc_info"
        patch_cd_pipeline_vars_fid "$team_slug" "$_fid_dev" "$_fid_prod"

        # Patch CD trigger data — only when at least one file needs a CD toolchain.
        # Trigger regeneration runs unconditionally when any service in the batch has
        # cicd_profile=ci_cd.  If ALL files are ci_only/minimal (no CD toolchains are
        # needed) we skip it entirely — inserting trigger locals when no CD toolchains
        # exist causes terraform validate to fail because the referenced inventory
        # branches / environment codes have nothing to deploy against.
        local _any_cd_profile=false
        for _f in "${onboarding_files[@]}"; do
            local _p
            _p=$(python3 -c "
import yaml, sys
try:
    print(yaml.safe_load(open('${_f}')).get('cicd_profile',''))
except: pass
" 2>/dev/null)
            if [ "$_p" = "ci_cd" ] || [ "$_p" = "cd_only" ]; then
                _any_cd_profile=true
                break
            fi
        done

        if [ "$_any_cd_profile" = "true" ]; then
            echo -e "${BLUE}[INFO]${NC} Regenerating CD trigger data from: ${_env_yaml_source}"
            patch_cd_trigger_data "$team_slug" "$_env_yaml_source" || return 1
        else
            echo -e "${BLUE}[INFO]${NC} All onboarding files are ci_only/minimal — skipping CD trigger data regeneration for ${team_slug}"
        fi
    else
        echo -e "${BLUE}[INFO]${NC} Pure offboard — skipping FID patch and trigger data regeneration for ${team_slug}"
    fi

    # ── Locate the toolchains .tf file ───────────────────────────────────────
    local tf_file="${TOOLCHAINS_CLONE_DIR}/${tf_filename}"

    if [ ! -f "$tf_file" ]; then
        echo -e "${RED}[ERROR]${NC} Toolchains file not found: ${tf_filename}" >&2
        return 1
    fi

    # ── Offboard: remove toolchain blocks for deleted/renamed services ────────
    local removed_count=0
    local removed_services=()
    if [ "${#offboard_names[@]}" -gt 0 ]; then
        echo -e "${BLUE}[INFO]${NC} Offboarding ${#offboard_names[@]} CD toolchain(s) for ${team_name}"
        for old_pipeline_name in "${offboard_names[@]}"; do
            echo -e "${BLUE}[INFO]${NC} Removing CD toolchain block for pipeline_name='${old_pipeline_name}'"
            if remove_toolchain_from_tf "$tf_file" "$old_pipeline_name"; then
                echo -e "${GREEN}[SUCCESS]${NC} Removed CD toolchain for '${old_pipeline_name}'"
                removed_services+=("$old_pipeline_name")
                removed_count=$(( removed_count + 1 ))
            else
                echo -e "${YELLOW}[WARNING]${NC} No CD toolchain block found for '${old_pipeline_name}' — already removed or never existed"
            fi
        done
    fi

    # ── Process each onboarding file ─────────────────────────────────────────
    local appended_count=0
    local skipped_count=0
    local skip_reasons=()
    local appended_services=()
    local added_toolchain_details=()

    for onboarding_file in "${onboarding_files[@]}"; do
        echo -e "${BLUE}[INFO]${NC} Processing: $(basename "$onboarding_file")"

        # Skip services whose cicd_profile does not require a CD toolchain
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
except Exception as e:
    sys.exit(1)
" 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$_profile" ]; then
            echo -e "${YELLOW}[WARNING]${NC} Could not read cicd_profile from $(basename "$onboarding_file") — skipping (file may be part of an offboard/rename)" >&2
            skip_reasons+=("$(basename "$onboarding_file"): could not read cicd_profile")
            skipped_count=$(( skipped_count + 1 ))
            continue
        fi
        if [ "$_profile" = "minimal" ] || [ "$_profile" = "ci_only" ]; then
            # Profile does not require a CD toolchain — but the service may have
            # previously been ci_cd and already have a block in the .tf file.
            # If so, remove it now (downgrade from ci_cd → ci_only/minimal).
            local _svc_name_for_removal
            _svc_name_for_removal=$(python3 -c "
import yaml, sys
try:
    print(yaml.safe_load(open('${onboarding_file}')).get('service_name',''))
except: pass
" 2>/dev/null)
            local _pipeline_name_for_removal
            _pipeline_name_for_removal=$(echo "$_svc_name_for_removal" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr ' ' '-')
            if [ -n "$_pipeline_name_for_removal" ] && [ -f "$tf_file" ]; then
                if remove_toolchain_from_tf "$tf_file" "$_pipeline_name_for_removal"; then
                    echo -e "${GREEN}[SUCCESS]${NC} Removed stale CD toolchain for '${_svc_name_for_removal}' (profile downgraded to ${_profile})"
                    removed_services+=("${_svc_name_for_removal} [profile downgraded to ${_profile}]")
                    removed_count=$(( removed_count + 1 ))
                else
                    echo -e "${BLUE}[INFO]${NC} cicd_profile is '${_profile}' for $(basename "$onboarding_file") — CD toolchain not required, skipping"
                fi
            else
                echo -e "${BLUE}[INFO]${NC} cicd_profile is '${_profile}' for $(basename "$onboarding_file") — CD toolchain not required, skipping"
            fi
            skip_reasons+=("$(basename "$onboarding_file"): cicd_profile=${_profile}, no CD toolchain provisioned")
            skipped_count=$(( skipped_count + 1 ))
            continue
        fi

        local tc_info
        tc_info=$(extract_toolchain_info_from_onboarding "$onboarding_file") || {
            echo -e "${YELLOW}[WARNING]${NC} Failed to extract toolchain info from: $(basename "$onboarding_file") — skipping (file may be part of an offboard)" >&2
            skipped_count=$(( skipped_count + 1 ))
            skip_reasons+=("$(basename "$onboarding_file"): could not parse onboarding YAML (offboard scenario)")
            continue
        }

        local t_team_name t_team_slug service_name inv_repo inc_repo _fid_dev_unused _fid_prod_unused servicenow_crn
        IFS='|' read -r t_team_name t_team_slug service_name inv_repo inc_repo _fid_dev_unused _fid_prod_unused servicenow_crn <<< "$tc_info"

        # Validate required fields
        if [ -z "$inv_repo" ] || [ -z "$inc_repo" ]; then
            echo -e "${YELLOW}[WARNING]${NC} Missing inventory/incident URL in: $(basename "$onboarding_file") — skipping" >&2
            skip_reasons+=("$(basename "$onboarding_file"): missing inventory or incident repo URL")
            skipped_count=$(( skipped_count + 1 ))
            continue
        fi

        # ── Extract per-service excludes and patch service override local ─────
        # This runs unconditionally — even if the toolchain block already exists,
        # the exclude list in the onboarding YAML may have changed and the
        # service-specific trigger local in pipeline_vars.tf must be kept in sync.
        #
        # When ENABLE_TRIGGER_CREATION=false the override local is never written,
        # so _has_excludes is forced to "false" to keep the trigger ref pointing
        # at the team-level pointer instead of a dangling service-specific local.
        local _svc_excludes _has_excludes _trigger_ref
        local _svc_slug
        _svc_slug=$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr ' ' '-')
        _svc_excludes=$(extract_cd_excludes_from_onboarding "$onboarding_file") || _svc_excludes=""
        if [ -n "$_svc_excludes" ] && [ "$ENABLE_TRIGGER_CREATION" = "true" ]; then
            _has_excludes="true"
            echo -e "${BLUE}[INFO]${NC} Service '${service_name}' has excludes: ${_svc_excludes}"
            patch_cd_service_trigger_override "$team_slug" "$_svc_slug" "$_svc_excludes" "$_env_yaml_source" || return 1
        elif [ -n "$_svc_excludes" ]; then
            echo -e "${YELLOW}[INFO]${NC} Service '${service_name}' has excludes but trigger creation is disabled — trigger ref will use team default"
            _has_excludes="false"
        else
            _has_excludes="false"
        fi
        _trigger_ref=$(get_cd_trigger_local_ref "$team_slug" "$_svc_slug" "$_has_excludes")

        # ── Check idempotency: is this toolchain block already in the file? ───
        # Checked AFTER excludes so the pipeline_vars.tf override is always
        # up to date even when no new toolchain block needs to be appended.
        # toolchain_entry_status_in_tf returns: "exact" | "stale" | "missing"
        # Pass servicenow_crn so a changed CRN is detected as "stale".
        local tc_status
        tc_status=$(toolchain_entry_status_in_tf "$tf_file" "$service_name" "$inv_repo" "$inc_repo" "$servicenow_crn")

        if [ "$tc_status" = "stale" ]; then
            # Entry found by pipeline_name but one or more fields changed in the
            # onboarding YAML — update repos, servicenow_crn, and trigger ref.
            echo -e "${BLUE}[INFO]${NC} CD toolchain for '${service_name}' exists with stale fields — updating"
            if update_cd_toolchain_repos_in_tf "$tf_file" "$service_name" "$inv_repo" "$inc_repo"; then
                echo -e "${GREEN}[SUCCESS]${NC} Updated repo URLs for '${service_name}'"
            else
                echo -e "${YELLOW}[WARNING]${NC} Repo URL update returned no changes for '${service_name}'"
            fi
            # Patch servicenow_crn / tc_env_props (covers add, update, and removal)
            if patch_cd_toolchain_servicenow_crn "$tf_file" "$service_name" "$servicenow_crn" "$team_slug"; then
                echo -e "${GREEN}[SUCCESS]${NC} Patched servicenow_crn in tc_env_props for '${service_name}'"
            fi
            # Also patch trigger ref — the updated inv_repo is the new lookup key
            patch_cd_toolchain_trigger_ref "$tf_file" "$inv_repo" "$_trigger_ref" || true
            appended_services+=("${service_name} [repos + crn + trigger ref updated]")
            added_toolchain_details+=("${service_name}|${inv_repo}|${inc_repo}")
            appended_count=$(( appended_count + 1 ))
            continue
        fi

        if [ "$tc_status" = "exact" ]; then
            echo -e "${BLUE}[INFO]${NC} CD toolchain for '${service_name}' already exists in ${tf_filename} — checking trigger ref and CRN"
            # Entry exists and all fields match. Still attempt to patch trigger ref
            # and servicenow_crn in case either is stale for a different reason
            # (e.g. excludes changed, CRN updated).
            local _crn_changed=false
            if patch_cd_toolchain_servicenow_crn "$tf_file" "$service_name" "$servicenow_crn" "$team_slug"; then
                echo -e "${GREEN}[SUCCESS]${NC} Patched servicenow_crn in tc_env_props for '${service_name}'"
                _crn_changed=true
            fi
            if patch_cd_toolchain_trigger_ref "$tf_file" "$inv_repo" "$_trigger_ref"; then
                echo -e "${GREEN}[SUCCESS]${NC} Patched pipeline_types_trigger_data → local.${_trigger_ref} for '${service_name}'"
                appended_services+=("${service_name} [trigger ref${_crn_changed:+ + crn} updated]")
                added_toolchain_details+=("${service_name}|${inv_repo}|${inc_repo}")
                appended_count=$(( appended_count + 1 ))
            elif [ "$_crn_changed" = "true" ]; then
                appended_services+=("${service_name} [crn updated]")
                added_toolchain_details+=("${service_name}|${inv_repo}|${inc_repo}")
                appended_count=$(( appended_count + 1 ))
            else
                echo -e "${BLUE}[INFO]${NC} All fields already correct for '${service_name}' — skipping"
                skip_reasons+=("${service_name}: CD toolchain already existed (all fields up to date)")
                skipped_count=$(( skipped_count + 1 ))
            fi
            continue
        fi

        # tc_status = "missing" — fall through to append new block

        # Generate and append the new toolchain block
        echo -e "${BLUE}[INFO]${NC} Appending CD toolchain block for '${service_name}' (trigger_ref: ${_trigger_ref})"
        local block
        block=$(generate_toolchain_block "$team_slug" "$service_name" "$inv_repo" "$inc_repo" "$_trigger_ref" "$servicenow_crn")

        if ! append_toolchain_to_tf "$tf_file" "$block"; then
            echo -e "${RED}[ERROR]${NC} Failed to append toolchain block for: ${service_name}" >&2
            return 1
        fi

        appended_services+=("$service_name")
        added_toolchain_details+=("${service_name}|${inv_repo}|${inc_repo}")
        appended_count=$(( appended_count + 1 ))
        echo -e "${GREEN}[SUCCESS]${NC} Appended CD toolchain for '${service_name}'"
    done

    # ── Bail out if nothing changed ───────────────────────────────────────────
    # IMPORTANT: check pipeline_vars.tf for trigger-data changes BEFORE bailing.
    # A service with excludes that already has a toolchain block will have
    # appended_count=0 but pipeline_vars.tf will be dirty with the new
    # service-specific override local — that still needs a PR.
    if [ "$appended_count" -eq 0 ] && [ "$removed_count" -eq 0 ] && [ "$is_new_branch" = "false" ]; then
        if git diff --quiet "${team_slug}-cd-pipeline_vars.tf" 2>/dev/null; then
            echo -e "${YELLOW}[WARNING]${NC} All CD toolchains already exist for ${team_name} and trigger data unchanged — no PR needed"
            for reason in "${skip_reasons[@]}"; do
                echo -e "  ↳ ${reason}"
            done
            git checkout "$team_branch" 2>/dev/null || true
            return 2
        else
            echo -e "${BLUE}[INFO]${NC} No new toolchain blocks but trigger data changed — will open PR for ${team_name}"
            pr_title="chore: Update ${team_name} CD trigger data (service-specific overrides)"
            appended_count=1  # allow the PR flow to proceed
        fi
    fi

    if [ "$removed_count" -gt 0 ] && [ "$appended_count" -eq 0 ]; then
        pr_title="chore: Offboard ${team_name} CD toolchain(s)"
    elif [ "$appended_count" -eq 1 ] && [ "${#appended_services[@]}" -eq 1 ]; then
        # Use "update" wording when the change was a repo URL fix, not a new toolchain
        if [[ "${appended_services[0]}" == *"[repos"* ]]; then
            pr_title="fix: Update ${team_name} CD toolchain repo URLs for ${appended_services[0]%% \[*\]}"
        else
            pr_title="feat: Add ${team_name} CD toolchain for ${appended_services[0]}"
        fi
    fi

    git config user.name  "clconc"
    git config user.email "clconc@us.ibm.com"

    local pr_branch="auto-cd-toolchains-${team_slug}-$(date +%Y%m%d-%H%M%S)"
    echo -e "${BLUE}[INFO]${NC} Creating PR branch: ${pr_branch}"

    if [ "$is_new_branch" = "true" ]; then
        # ── New team ────────────────────────────────────────────────────────────
        # The team branch only exists locally at its scaffold commit (NO_PUSH=true
        # kept create-team-branch.sh from pushing it).  The base branch for the PR
        # must exist on the remote BEFORE the PR branch diverges from it — otherwise
        # both point to the same commit and GitHub rejects with HTTP 422.
        #
        # Correct order:
        #   1. Push the local team branch as-is (scaffold state) → this becomes the PR base
        #   2. git checkout -b <pr-branch>   — branches off that same scaffold commit
        #   3. terraform fmt -recursive + git add + commit — toolchain changes land only on pr branch
        #   4. git push origin <pr-branch>   — now 1 commit ahead of origin/<team-branch> ✓
        echo -e "${BLUE}[INFO]${NC} Pushing new team base branch (scaffold state): ${team_branch}"
        git push origin "${team_branch}"
        git checkout -b "$pr_branch"
        if command -v terraform &> /dev/null; then
            echo -e "${BLUE}[INFO]${NC} Running terraform fmt -recursive"
            terraform fmt -recursive . \
                && echo -e "${GREEN}[SUCCESS]${NC} Terraform formatting completed" \
                || echo -e "${YELLOW}[WARNING]${NC} terraform fmt failed"
        else
            echo -e "${YELLOW}[WARNING]${NC} terraform not found, skipping fmt"
        fi
        git add .
        if git diff --cached --quiet; then
            echo -e "${YELLOW}[WARNING]${NC} No staged changes — CD toolchains are already up to date"
            git checkout "$team_branch" 2>/dev/null || true
            return 2
        fi
        git commit -m "$pr_title"
    else
        # ── Existing team ───────────────────────────────────────────────────────
        # The team branch already exists on the remote (checked out + reset --hard
        # to origin/<team-branch>).  We must NOT commit on the team branch — doing
        # so would put the local branch ahead of origin, making the PR branch
        # identical to origin/<team-branch> and causing the GitHub API to return
        # "No commits between <base> and <head>" (HTTP 422).
        #
        # Correct order:
        #   1. Create the PR branch off the clean team-branch HEAD (no changes yet)
        #   2. terraform fmt -recursive + git add + git commit — all happen on the PR branch
        #
        # This guarantees the PR branch has exactly one new commit ahead of
        # origin/<team-branch>, with no stash or index gymnastics required.
        git checkout -b "$pr_branch"
        if command -v terraform &> /dev/null; then
            echo -e "${BLUE}[INFO]${NC} Running terraform fmt -recursive"
            terraform fmt -recursive . \
                && echo -e "${GREEN}[SUCCESS]${NC} Terraform formatting completed" \
                || echo -e "${YELLOW}[WARNING]${NC} terraform fmt failed"
        else
            echo -e "${YELLOW}[WARNING]${NC} terraform not found, skipping fmt"
        fi
        git add .
        if git diff --cached --quiet; then
            echo -e "${YELLOW}[WARNING]${NC} No staged changes — CD toolchains are already up to date"
            git checkout "$team_branch" 2>/dev/null || true
            return 2
        fi
        git commit -m "$pr_title"
    fi

    echo -e "${BLUE}[INFO]${NC} Pushing PR branch: ${pr_branch}"
    git push origin "$pr_branch"

    # ── Build PR body ─────────────────────────────────────────────────────────
    local pr_body
    pr_body="## Automated CD Toolchains ${action}: ${team_name}

This PR was automatically generated by the UUC onboarding merge pipeline.

### Team Information
- **Team Name**: ${team_name}
- **Team Slug**: ${team_slug}
- **Branch**: \`${team_branch}\`
- **Action**: ${action}
"

    if [ "$is_new_branch" = "true" ]; then
        pr_body+="
### Branch Scaffold
- ✅ Created new team branch \`${team_branch}\` from \`main\` templates/cd/
- ✅ Scaffolded all CD template files (\`backend.tf\`, \`common.tf\`, \`variables.tf\`, \`versions.tf\`, \`pipeline_vars.tf\`, \`pipeline_meta.tf\`, \`toolchains.tf\`)
- ✅ Placeholder substitution applied (SECRET_GROUP, RESOURCE_GROUP, TEAM_NAME variants)
"
    fi

    if [ "$removed_count" -gt 0 ]; then
        pr_body+="
### CD Toolchains Offboarded (${removed_count})
"
        for svc in "${removed_services[@]}"; do
            pr_body+="- 🗑️  \`${svc}\` (toolchain block removed)
"
        done
    fi

    pr_body+="
### New CD Toolchains Added / Updated (${appended_count})
"
    for svc in "${appended_services[@]}"; do
        pr_body+="- ✅ \`${svc}\`
"
    done

    if [ "$appended_count" -gt 0 ]; then
        pr_body+="
### Added Toolchain Details
"
        local detail service_name_detail inv_repo_detail inc_repo_detail
        for detail in "${added_toolchain_details[@]}"; do
            IFS='|' read -r service_name_detail inv_repo_detail inc_repo_detail <<< "$detail"
            pr_body+="- \`${service_name_detail}\`
  - repo: \`${inv_repo_detail}\`
  - inventory repo: \`${inv_repo_detail}\`
  - incident repo: \`${inc_repo_detail}\`
"
        done
    fi

    if [ "${#skip_reasons[@]}" -gt 0 ]; then
        pr_body+="
### Already Existing / Skipped (${skipped_count})
"
        for reason in "${skip_reasons[@]}"; do
            pr_body+="- ⏭️  ${reason}
"
        done
    fi

    pr_body+="
### Files Changed
- \`${tf_filename}\`
- \`${team_slug}-cd-pipeline_vars.tf\` (trigger data regenerated from environment-code YAML)

### Idempotency Check
Each toolchain entry was verified against the existing \`${tf_filename}\` by matching the pair:
- \`inventory_repo_url\`
- \`incident_repo_url\`

Entries where both already matched were skipped with an inline comment.

### Next Steps
1. Review the appended toolchain block(s) in \`${tf_filename}\`
2. Verify the generated GUIDs are unique (replace if needed)
3. Confirm \`inventory_repo_url\` and \`incident_repo_url\` are correct
4. Merge this PR into branch \`${team_branch}\`
5. The merge pipeline will apply the Terraform configuration

### Related
- Source: uuc-service-cicd-onboarding repository
- Pipeline: UUC Ops Merge Pipeline
- Generated by: provision_team_cd_toolchains.sh

---
*This PR was automatically created. Please review carefully before merging.*"

    # ── Open PR via GitHub API (head → team branch, NOT main) ─────────────────
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
        -H "Authorization: token ${AUTO_PR_GITHUB_TOKEN:-${GITHUB_TOKEN}}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://github.ibm.com/api/v3/repos/genctl-cicd/uuc-toolchains-tf-module/pulls" \
        -d "$pr_payload")

    local pr_url pr_number
    pr_url=$(echo    "$pr_response" | jq -r '.html_url // empty')
    pr_number=$(echo "$pr_response" | jq -r '.number   // empty')

    if [ -n "$pr_url" ] && [ "$pr_url" != "null" ]; then
        echo -e "${GREEN}[SUCCESS]${NC} Pull request created successfully!"
        echo -e "${CYAN}PR #${pr_number}: ${pr_url}${NC}"
        CREATED_TOOLCHAINS_PR_URL="$pr_url"
        CREATED_TOOLCHAINS_PR_NUMBER="$pr_number"
        git checkout "$team_branch" 2>/dev/null || true
        return 0
    else
        echo -e "${RED}[ERROR]${NC} Failed to create pull request"
        echo "GitHub API response: $pr_response" >&2
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

    # ── Parse arguments ───────────────────────────────────────────────────────
    # --files <file1> [<file2> ...] — explicitly supply individual onboarding
    #   files instead of auto-detecting via git diff.
    #   Env-var equivalent: FORCE_ONBOARDING_FILES (space-separated paths).
    #
    # --dir <directory> — collect every *-onboarding.yaml|yml found under the
    #   given directory and add them to the file list (uses find_onboarding_files
    #   from onboarding_validation_utils.sh).
    #   Env-var equivalent: FORCE_ONBOARDING_DIR (single directory path).
    #
    # Both flags may be combined; --dir results are appended to --files.
    # When either is supplied, git-diff detection is skipped entirely.
    local force_files=()
    local force_dir=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --files)
                shift
                while [[ $# -gt 0 && "$1" != --* ]]; do
                    force_files+=("$1")
                    shift
                done
                ;;
            --dir)
                shift
                force_dir="$1"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # PROCESS_ALL_FILES=true — cron / manual full-branch run.
    # Checks out ONBOARDING_BRANCH and pre-populates force_files with every
    # *-onboarding.yaml on it, bypassing git-diff entirely.
    # Evaluated before all other env-var fallbacks so it takes highest priority.
    if [[ "${PROCESS_ALL_FILES:-false}" == "true" ]] && [ ${#force_files[@]} -eq 0 ]; then
        mapfile -t force_files < <(get_all_files_from_branch)
    fi

    # Env-var fallbacks
    if [ ${#force_files[@]} -eq 0 ] && [ -n "$FORCE_ONBOARDING_FILES" ]; then
        IFS=' ' read -ra force_files <<< "$FORCE_ONBOARDING_FILES"
    fi
    if [ -z "$force_dir" ] && [ -n "$FORCE_ONBOARDING_DIR" ]; then
        force_dir="$FORCE_ONBOARDING_DIR"
    fi

    # Expand --dir into individual files and append to force_files
    if [ -n "$force_dir" ]; then
        if [ ! -d "$force_dir" ]; then
            echo -e "${RED}[ERROR]${NC} --dir path is not a directory: ${force_dir}" >&2
            exit 1
        fi
        echo -e "${BLUE}[INFO]${NC} Scanning directory for onboarding files: ${force_dir}"
        local dir_files=()
        mapfile -t dir_files < <(find_onboarding_files "$force_dir")
        if [ ${#dir_files[@]} -eq 0 ]; then
            echo -e "${YELLOW}[WARNING]${NC} No onboarding files found in directory: ${force_dir}"
        else
            echo -e "${GREEN}[INFO]${NC} Found ${#dir_files[@]} onboarding file(s) in directory"
            force_files+=("${dir_files[@]}")
        fi
    fi

    mkdir -p "$WORK_DIR"

    # ── Detect deleted onboarding files early ────────────────────────────────
    # Must happen BEFORE the "no changed files" guard so that a pure-offboard
    # PR (file deleted, nothing added) still proceeds to create the removal PR.
    # When --files / --dir / PROCESS_ALL_FILES is used the caller controls which
    # files to process; deletion detection is skipped in that mode.
    local deleted_onboarding_files=()
    local _onboarding_repo_root
    if [ -n "$PATH_TO_WORKSPACE_REPO" ] && [ -d "$PATH_TO_WORKSPACE_REPO" ]; then
        _onboarding_repo_root="$PATH_TO_WORKSPACE_REPO"
    else
        _onboarding_repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
        [ -z "$_onboarding_repo_root" ] && _onboarding_repo_root="$(dirname "$TOOLCHAINS_CLONE_DIR")"
    fi
    if [ ${#force_files[@]} -eq 0 ]; then
        mapfile -t deleted_onboarding_files < <(get_deleted_onboarding_files 2>/dev/null) || true
    fi

    # ── Detect changed files ──────────────────────────────────────────────────
    if [ ${#force_files[@]} -gt 0 ]; then
        echo -e "${GREEN}[INFO]${NC} Using explicitly supplied onboarding file(s) (--files / --dir / FORCE_ONBOARDING_FILES / FORCE_ONBOARDING_DIR)"
        changed_files=("${force_files[@]}")
    else
        echo -e "${BLUE}[INFO]${NC} Detecting changed onboarding files..."
        mapfile -t changed_files < <(get_changed_files_from_git)

        # commons.yaml is team-level — when only it changes (e.g. a FID is
        # updated) no *-onboarding.yaml file appears in the diff, so
        # get_changed_files_from_git returns nothing.  Detect this case and fall
        # back to processing ALL service onboarding files on the branch so the
        # CD pipeline_vars FID is patched with the updated value.
        if [ ${#changed_files[@]} -eq 0 ] && commons_changed_in_pr; then
            echo -e "${BLUE}[INFO]${NC} commons.yaml changed — collecting all service onboarding files for re-provisioning"
            local commons_dir="${PATH_TO_WORKSPACE_REPO:-$(pwd)}"
            mapfile -t changed_files < <(find_onboarding_files "$commons_dir")
            if [ ${#changed_files[@]} -gt 0 ]; then
                echo -e "${GREEN}[INFO]${NC} Found ${#changed_files[@]} onboarding file(s) to re-process due to commons.yaml change"
            fi
        fi
    fi

    if [ ${#changed_files[@]} -eq 0 ] && [ ${#deleted_onboarding_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}[WARNING]${NC} No onboarding files changed or deleted in this merge"
        echo -e "${BLUE}[INFO]${NC} Skipping CD toolchains provisioning"
        exit 0
    fi

    if [ ${#changed_files[@]} -gt 0 ]; then
        echo -e "${GREEN}[INFO]${NC} Found ${#changed_files[@]} changed onboarding file(s)"
        for file in "${changed_files[@]}"; do
            echo -e "  - ${file}"
        done
        echo ""
    fi
    if [ ${#deleted_onboarding_files[@]} -gt 0 ]; then
        echo -e "${GREEN}[INFO]${NC} Found ${#deleted_onboarding_files[@]} deleted onboarding file(s) — will offboard"
    fi
    echo ""

    # ── Clone / verify toolchains repo ───────────────────────────────────────
    if [ "$USE_EXISTING_CLONE" = "true" ]; then
        echo -e "${BLUE}[INFO]${NC} Using pre-cloned toolchains repository: ${TOOLCHAINS_CLONE_DIR}"
        cd "$TOOLCHAINS_CLONE_DIR"
        git fetch origin "$TOOLCHAINS_MAIN_BRANCH"
        git checkout "$TOOLCHAINS_MAIN_BRANCH"
        git reset --hard "origin/${TOOLCHAINS_MAIN_BRANCH}"
        echo -e "${GREEN}[SUCCESS]${NC} Toolchains repository ready"
    else
        echo -e "${BLUE}[INFO]${NC} Cloning toolchains repository (main)..."
        if ! git clone --branch "$TOOLCHAINS_MAIN_BRANCH" "$TOOLCHAINS_REPO_URL" \
                "$TOOLCHAINS_CLONE_DIR" 2>&1 | grep -v "warning: "; then
            echo -e "${RED}[ERROR]${NC} Failed to clone toolchains repository"
            exit 1
        fi
        echo -e "${GREEN}[SUCCESS]${NC} Toolchains repository cloned"
    fi
    echo ""

    # ── Group changed files by team ───────────────────────────────────────────
    declare -A team_info_map   # team_slug → "team_name"
    declare -A team_files_map  # team_slug → "|"-separated absolute file paths

    for onboarding_file in "${changed_files[@]}"; do
        # Ensure absolute path
        if [[ "$onboarding_file" != /* ]]; then
            if [ -n "$PATH_TO_WORKSPACE_REPO" ]; then
                onboarding_file="${PATH_TO_WORKSPACE_REPO}/${onboarding_file}"
            else
                onboarding_file="$(pwd)/${onboarding_file}"
            fi
        fi

        local tc_info
        tc_info=$(extract_toolchain_info_from_onboarding "$onboarding_file") || {
            echo -e "${YELLOW}[WARNING]${NC} Could not parse onboarding file (may be deleted/renamed as part of offboard): $onboarding_file — skipping from grouping" >&2
            continue
        }

        local team_name team_slug
        IFS='|' read -r team_name team_slug _ _ _ _ _ <<< "$tc_info"

        team_info_map["$team_slug"]="$team_name"

        if [ -z "${team_files_map[$team_slug]+x}" ]; then
            team_files_map["$team_slug"]="$onboarding_file"
        else
            team_files_map["$team_slug"]="${team_files_map[$team_slug]}|$onboarding_file"
        fi
    done

    # ── Process deleted/renamed onboarding files → offboard their toolchains ──
    # A git mv + service_name rename shows up as: old file deleted, new file added.
    # We read the old service_name from git history to derive the old pipeline_name,
    # then pass it as --offboard so create_cd_toolchains_pr removes the stale block.
    #
    # In addition: a modified file whose service_name was changed in-place does NOT
    # appear in the deleted list, but it still requires the old toolchain block to be
    # removed before the new one is appended.  We detect this by reading the old
    # service_name for every changed file from HEAD~1 and comparing it to the current
    # service_name.  When they differ the old pipeline_name is added to team_deleted_map.
    #
    # NOTE: deleted_onboarding_files and _onboarding_repo_root were already populated
    # above (before the exit-0 guard) so that pure-offboard PRs (file deleted, nothing
    # added) are not skipped.  We reuse those variables here — do not re-declare them.
    declare -A team_deleted_map  # team_slug → "|"-separated pipeline_names to remove

    if [ "${#deleted_onboarding_files[@]}" -gt 0 ]; then
        echo -e "${BLUE}[INFO]${NC} Found ${#deleted_onboarding_files[@]} deleted onboarding file(s) — processing offboards"

        for deleted_file in "${deleted_onboarding_files[@]}"; do
            local rel_path="${deleted_file#${_onboarding_repo_root}/}"

            local old_content
            old_content=$(git -C "$_onboarding_repo_root" show "HEAD~1:${rel_path}" 2>/dev/null) || {
                echo -e "${YELLOW}[WARNING]${NC} Could not read old content for deleted file: ${rel_path} — skipping offboard" >&2
                continue
            }

            local old_team_slug old_service_name old_pipeline_name

            # team_name lives in commons.yaml (same directory as the deleted file),
            # NOT in the service YAML itself.  Read both from git history.
            local _commons_rel_path
            _commons_rel_path="$(dirname "$rel_path")/commons.yaml"
            local old_commons_content
            old_commons_content=$(git -C "$_onboarding_repo_root" show "HEAD~1:${_commons_rel_path}" 2>/dev/null) || \
                old_commons_content=$(git -C "$_onboarding_repo_root" show "HEAD~1:$(dirname "$rel_path")/commons.yml" 2>/dev/null) || \
                old_commons_content=""

            read -r old_team_slug old_service_name <<< "$(python3 - <<PYEOF
import yaml, sys

service_content  = '''${old_content}'''
commons_content  = '''${old_commons_content}'''

try:
    svc = yaml.safe_load(service_content) or {}
    com = yaml.safe_load(commons_content) or {} if commons_content.strip() else {}

    # team_name is in commons.yaml; fall back to the service YAML for
    # older files that still carry it inline.
    tn = (com.get('team_name') or svc.get('team_name') or '').strip().lower().replace(' ', '-')
    sn = (svc.get('service_name') or '').strip()
    slug = sn.lower().replace('_', '-').replace(' ', '-')

    if not tn or not slug:
        sys.exit(1)
    print(tn, slug)
except Exception:
    sys.exit(1)
PYEOF
)"
            if [ -z "$old_team_slug" ] || [ -z "$old_service_name" ]; then
                echo -e "${YELLOW}[WARNING]${NC} Could not parse team/service from deleted file: ${rel_path} — skipping offboard" >&2
                continue
            fi

            old_pipeline_name="$old_service_name"

            echo -e "${BLUE}[INFO]${NC} Offboard: team='${old_team_slug}' pipeline='${old_pipeline_name}' (from deleted ${rel_path})"

            if [ -z "${team_deleted_map[$old_team_slug]+x}" ]; then
                team_deleted_map["$old_team_slug"]="$old_pipeline_name"
                if [ -z "${team_info_map[$old_team_slug]+x}" ]; then
                    team_info_map["$old_team_slug"]="$old_team_slug"
                    team_files_map["$old_team_slug"]=""
                fi
            else
                team_deleted_map["$old_team_slug"]="${team_deleted_map[$old_team_slug]}|$old_pipeline_name"
            fi
        done
    fi

    # ── Detect in-place edits and git-renames where service_name changed ─────
    # Two scenarios both leave a stale pipeline_name block in the .tf:
    #   1. File modified in-place with service_name changed.
    #   2. File renamed (git mv) with service_name changed — git diff --name-only
    #      only reports the NEW filename; git show HEAD~1:<new-path> fails because
    #      the new path didn't exist at HEAD~1.
    # Fix: for each changed file, first try git show HEAD~1:<new-path> (covers
    # in-place edits).  On failure, look up the old path via git diff -M (rename
    # detection) and try HEAD~1:<old-path> instead.  When the old service_name
    # slug differs from the current one, register it as an offboard.
    for onboarding_file in "${changed_files[@]}"; do
        local _abs_file="$onboarding_file"
        if [[ "$_abs_file" != /* ]]; then
            if [ -n "$PATH_TO_WORKSPACE_REPO" ]; then
                _abs_file="${PATH_TO_WORKSPACE_REPO}/${_abs_file}"
            else
                _abs_file="$(pwd)/${_abs_file}"
            fi
        fi

        # Only process files that still exist (skip pure-deleted ones already handled above)
        [ -f "$_abs_file" ] || continue

        local _rel_path="${_abs_file#${_onboarding_repo_root}/}"

        # Try the current path first (covers in-place edits).
        # If that fails the file was renamed — look up its old path via rename detection.
        local _old_svc_content _old_rel_path="$_rel_path"
        if ! _old_svc_content=$(git -C "$_onboarding_repo_root" show "HEAD~1:${_rel_path}" 2>/dev/null); then
            local _old_path_candidate
            _old_path_candidate=$(git -C "$_onboarding_repo_root" \
                diff --name-status -M HEAD~1 HEAD -- "$_rel_path" 2>/dev/null \
                | awk '/^R/ { print $2 }' | head -1)
            [ -n "$_old_path_candidate" ] || continue
            _old_rel_path="$_old_path_candidate"
            _old_svc_content=$(git -C "$_onboarding_repo_root" show "HEAD~1:${_old_rel_path}" 2>/dev/null) || continue
        fi

        # Also retrieve the old commons.yaml for team_name
        local _commons_rel="$(dirname "$_old_rel_path")/commons.yaml"
        local _old_commons_content
        _old_commons_content=$(git -C "$_onboarding_repo_root" show "HEAD~1:${_commons_rel}" 2>/dev/null) || \
            _old_commons_content=$(git -C "$_onboarding_repo_root" show "HEAD~1:$(dirname "$_old_rel_path")/commons.yml" 2>/dev/null) || \
            _old_commons_content=""

        # Extract old team_slug and old pipeline_name slug
        local _old_team_slug _old_svc_slug
        read -r _old_team_slug _old_svc_slug <<< "$(python3 - <<PYEOF
import yaml, sys
svc_txt = '''${_old_svc_content}'''
com_txt = '''${_old_commons_content}'''
try:
    svc = yaml.safe_load(svc_txt) or {}
    com = yaml.safe_load(com_txt) or {} if com_txt.strip() else {}
    tn = (com.get('team_name') or svc.get('team_name') or '').strip().lower().replace(' ', '-')
    sn = (svc.get('service_name') or '').strip()
    slug = sn.lower().replace('_', '-').replace(' ', '-')
    if not tn or not slug:
        sys.exit(1)
    print(tn, slug)
except Exception:
    sys.exit(1)
PYEOF
)"
        [ -z "$_old_team_slug" ] || [ -z "$_old_svc_slug" ] && continue

        # Extract current service_name slug from the current file content
        local _cur_tc_info _cur_svc_slug
        _cur_tc_info=$(extract_toolchain_info_from_onboarding "$_abs_file" 2>/dev/null) || continue
        local _cur_team_slug
        IFS='|' read -r _ _cur_team_slug _cur_svc_slug _ _ _ _ <<< "$_cur_tc_info"
        # Derive slug from service_name field (field 3, index 2) the same way generate_toolchain_block does
        _cur_svc_slug=$(echo "$_cur_svc_slug" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr ' ' '-')

        # If service_name slug changed, the old block must be removed
        if [ "$_old_svc_slug" != "$_cur_svc_slug" ]; then
            echo -e "${BLUE}[INFO]${NC} Detected CD service_name rename in '$(basename "$_abs_file")': '${_old_svc_slug}' → '${_cur_svc_slug}' — scheduling old block for removal"
            if [ -z "${team_deleted_map[$_old_team_slug]+x}" ]; then
                team_deleted_map["$_old_team_slug"]="$_old_svc_slug"
                if [ -z "${team_info_map[$_old_team_slug]+x}" ]; then
                    team_info_map["$_old_team_slug"]="$_old_team_slug"
                    team_files_map["$_old_team_slug"]=""
                fi
            else
                team_deleted_map["$_old_team_slug"]="${team_deleted_map[$_old_team_slug]}|${_old_svc_slug}"
            fi
        fi
    done

    # ── Process each unique team ──────────────────────────────────────────────
    for team_slug in "${!team_info_map[@]}"; do
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        local team_name="${team_info_map[$team_slug]}"
        local team_branch="${team_slug}-cd"
        echo -e "${BLUE}[INFO]${NC} Processing team: ${GREEN}${team_name}${NC} (branch: ${team_branch})"

        local is_new_branch="false"
        if team_cd_branch_exists "$team_branch"; then
            echo -e "${YELLOW}[INFO]${NC} Team branch '${team_branch}' already exists"
        else
            echo -e "${GREEN}[INFO]${NC} New team detected — will scaffold CD branch from templates"
            is_new_branch="true"
        fi

        IFS='|' read -ra team_onboarding_files <<< "${team_files_map[$team_slug]}"
        # Filter out empty strings (pure-offboard teams have no new files)
        local filtered_files=()
        for f in "${team_onboarding_files[@]}"; do
            [ -n "$f" ] && filtered_files+=("$f")
        done
        team_onboarding_files=("${filtered_files[@]}")

        # Build --offboard args for deleted/renamed services on this team
        local offboard_args=()
        if [ -n "${team_deleted_map[$team_slug]+x}" ] && [ -n "${team_deleted_map[$team_slug]}" ]; then
            IFS='|' read -ra _del_names <<< "${team_deleted_map[$team_slug]}"
            offboard_args+=(--offboard)
            offboard_args+=("${_del_names[@]}")
        fi

        # Reset script-level PR vars before each team
        CREATED_TOOLCHAINS_PR_URL=""
        CREATED_TOOLCHAINS_PR_NUMBER=""

        local pr_exit_code=0
        if ! create_cd_toolchains_pr \
            "$team_name" "$team_slug" "$is_new_branch" \
            "${offboard_args[@]}" \
            "${team_onboarding_files[@]}"; then
            pr_exit_code=$?
        fi

        if [ $pr_exit_code -eq 0 ]; then
            processed_teams+=("$team_slug")
            echo -e "${GREEN}[SUCCESS]${NC} CD toolchains PR created for ${team_name}"

            # ── Wait for PR to be merged ──────────────────────────────────────
            if [ -n "$CREATED_TOOLCHAINS_PR_URL" ]; then
                if ! wait_for_pr_merge "$CREATED_TOOLCHAINS_PR_URL" "$team_slug"; then
                    echo -e "${RED}[ERROR]${NC} PR for ${team_name} was not merged within the monitoring window."
                    exit_code=1
                else
                    if ! wait_for_merge_pipeline \
                            "$CREATED_TOOLCHAINS_PR_URL" \
                            "$CREATED_TOOLCHAINS_PR_NUMBER" \
                            "$team_slug"; then
                        echo -e "${RED}[ERROR]${NC} Merge pipeline for ${team_name} CD toolchains did not succeed."
                        exit_code=1
                    fi
                fi
            else
                echo -e "${YELLOW}[WARNING]${NC} No PR URL captured for ${team_name} — skipping merge monitoring"
            fi

        elif [ $pr_exit_code -eq 2 ]; then
            echo -e "${BLUE}[INFO]${NC} No PR created for ${team_name} — CD toolchains already up to date"
        else
            echo -e "${RED}[ERROR]${NC} Failed to create CD toolchains PR for ${team_name}"
            exit_code=1
        fi

        echo ""
    done

    # ── Summary ───────────────────────────────────────────────────────────────
    if [ ${#processed_teams[@]} -gt 0 ]; then
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}[SUCCESS]${NC} CD toolchains provisioning completed for ${#processed_teams[@]} team(s)"
        echo -e "${BLUE}Teams processed:${NC}"
        for team in "${processed_teams[@]}"; do
            echo -e "  - ${team}"
        done
    else
        echo -e "${YELLOW}[INFO]${NC} No teams were provisioned"
    fi

    if [ "$USE_EXISTING_CLONE" = "false" ]; then
        echo ""
        echo -e "${BLUE}[INFO]${NC} Cleaning up temporary files..."
        rm -rf "$WORK_DIR"
    fi

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    exit $exit_code
}

# Run main function
main "$@"

# Made with Bob
