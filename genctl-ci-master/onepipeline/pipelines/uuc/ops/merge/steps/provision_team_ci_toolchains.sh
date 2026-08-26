#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Team CI Toolchains Provisioning Script
# This script runs in the merge pipeline of uuc-service-cicd-onboarding repo.
# It detects new/changed onboarding YAML files, then creates (or updates) a PR
# in the uuc-toolchains-tf-module repository targeting the team's dedicated
# <team-slug>-ci branch to add new CI toolchain entries.
#
# Branch strategy
# ---------------
# Each team owns a dedicated branch named <team-slug>-ci in the toolchains repo.
# For a brand-new team the branch is scaffolded from the templates/ci/ directory
# on main (mirroring create-team-branch.sh logic), then the PR is opened against
# that new branch.  For an existing team the branch is checked out directly.
#
# Toolchain file location
# -----------------------
# The per-team toolchain definitions live in:
#   <team-slug>-ci-toolchains.tf   (at the repo root of the team branch)
#
# Idempotency / duplicate detection
# ----------------------------------
# Before appending a new toolchain block the script checks whether the
# app_repo, inventory_repo_url, and incident_repo_url triple already appears
# anywhere in the .tf file.  If ALL three are already present the entry is
# skipped with a comment noting the toolchain already exists.
# This makes the script safe to re-run after a partially-merged PR.
#
# Multiple onboarding files → single PR
# --------------------------------------
# All onboarding files belonging to the same team are batched into a single PR
# (matching the pattern in provision_team_infrastructure.sh).

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

# Temporary working directory
WORK_DIR="/tmp/uuc-ci-toolchains-provision-$$"

# Use pre-cloned toolchains repo if available, otherwise clone it fresh
if [ -n "$PATH_TO_UUC_TOOLCHAINS_REPO" ] && [ -d "$PATH_TO_UUC_TOOLCHAINS_REPO/.git" ]; then
    TOOLCHAINS_CLONE_DIR="$PATH_TO_UUC_TOOLCHAINS_REPO"
    USE_EXISTING_CLONE=true
else
    TOOLCHAINS_CLONE_DIR="${WORK_DIR}/toolchains"
    USE_EXISTING_CLONE=false
fi

# Script-level vars for the PR created by create_ci_toolchains_pr() — reset
# before each team so the caller's wait loop never picks up a stale value.
CREATED_TOOLCHAINS_PR_URL=""
CREATED_TOOLCHAINS_PR_NUMBER=""

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🔧  UUC Team CI Toolchains Provisioning${NC}"
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
#   team_name|team_slug|service_name|app_repo|app_branch|app_org
#   |inventory_repo_url|incident_repo_url|service_fid_dev|service_fid_prod|cicd_profile
#
# inventory_repo_url is only populated for cicd_profile=ci_cd.
# incident_repo_url  is only populated for cicd_profile=ci_only or ci_cd.
#
# account_type is NOT read from the YAML — it is sourced from the ACCOUNT_TYPE
# environment variable (default: "dev").
# Only the first app_repo entry is used — each service maps to one toolchain.
# ---------------------------------------------------------------------------
extract_toolchain_info_from_onboarding() {
    local onboarding_file="$1"

    if [ ! -f "$onboarding_file" ]; then
        echo -e "${RED}[ERROR]${NC} Onboarding file not found: $onboarding_file" >&2
        return 1
    fi

    python3 - <<EOF
import yaml, sys, re, os
from pathlib import Path

try:
    with open('$onboarding_file', 'r') as f:
        config = yaml.safe_load(f)

    if not isinstance(config, dict):
        print("ERROR: YAML is not a valid dict", file=sys.stderr)
        sys.exit(1)

    # Load commons.yaml — team-level fields (FIDs) live there
    _utils_dir = str(Path('$onboarding_file').resolve().parent.parent.parent.parent.parent.parent.parent / 'utils')
    _loader_paths = [
        _utils_dir,
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

    cicd_profile = config.get('cicd_profile', '').strip()
    if cicd_profile not in ('minimal', 'ci_only', 'ci_cd', 'cd_only'):
        print(f"ERROR: 'cicd_profile' is missing or invalid (got '{cicd_profile}'). "
              f"Allowed values: minimal | ci_only | ci_cd | cd_only", file=sys.stderr)
        sys.exit(1)

    # App repo — take first entry
    app_repos = config.get('app_repo', []) or []
    if not app_repos:
        print("ERROR: 'app_repo' list is empty", file=sys.stderr)
        sys.exit(1)
    first_app = app_repos[0]
    app_repo   = first_app.get('repo', '').rstrip('/')
    app_branch = first_app.get('branch', 'main')

    # Derive org from URL: https://github.ibm.com/<org>/<repo>
    m = re.match(r'https?://[^/]+/([^/]+)/([^/]+?)(?:\.git)?$', app_repo)
    if not m:
        print(f"ERROR: Could not extract repo_org from app_repo URL: '{app_repo}'. "
              f"Expected format: https://github.ibm.com/<org>/<repo>[.git]", file=sys.stderr)
        sys.exit(1)
    app_org = m.group(1)
    app_repo_with_git = app_repo if app_repo.endswith('.git') else app_repo + '.git'

    # Inventory repo — only relevant for ci_cd
    inv_repo = ''
    if cicd_profile == 'ci_cd':
        inv_cfg  = config.get('inventory_repo', {}) or {}
        inv_repo = inv_cfg.get('repo', '').rstrip('/')
        if inv_repo and not inv_repo.endswith('.git'):
            inv_repo += '.git'

    # Incident repo — relevant for ci_only and ci_cd (not minimal)
    inc_repo = ''
    if cicd_profile in ('ci_only', 'ci_cd'):
        inc_cfg  = config.get('incident_repo', {}) or {}
        inc_repo = inc_cfg.get('repo', '').rstrip('/')
        if inc_repo and not inc_repo.endswith('.git'):
            inc_repo += '.git'

    # Service Functional IDs — now in commons.yaml
    service_fid_dev  = commons.get('service_fid_dev',  '').strip()
    service_fid_prod = commons.get('service_fid_prod', '').strip()

    # CI deployment target — one entry under deployment_targets.CI.vpc_ng or .ngdc
    # The template ships with the literal word "env_code" as a placeholder; skip it.
    # Also skip other well-known placeholder zone names (zone1, zone2, zone3, myzone)
    # that validate_yaml.py treats as errors — we only patch terraform with real values.
    _CI_ZONE_PLACEHOLDERS = {'env_code', 'zone1', 'zone2', 'zone3', 'myzone'}
    ci_env_code = ''
    dt = config.get('deployment_targets', {}) or {}
    ci_dt = dt.get('CI', {}) or {}
    for key in ('vpc_ng', 'ngdc'):
        section = ci_dt.get(key)
        if section:
            # Accept both a list (template default) and a plain dict
            entry = section[0] if isinstance(section, list) else section
            candidate = (entry.get('name', '') or '').strip()
            if candidate and candidate.lower() not in _CI_ZONE_PLACEHOLDERS:
                ci_env_code = candidate
                break

    print(f"{team_name}|{team_slug}|{service_name}|{app_repo_with_git}|{app_branch}|{app_org}|{inv_repo}|{inc_repo}|{service_fid_dev}|{service_fid_prod}|{cicd_profile}|{ci_env_code}")

except yaml.YAMLError as e:
    print(f"ERROR: YAML parse error: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# ---------------------------------------------------------------------------
# Function: patch_ci_pipeline_vars_fid
#
# Patches the "service-functional-id-email" value inside common_tc_env_props
# in the team's <team-slug>-ci-pipeline_vars.tf file.
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
patch_ci_pipeline_vars_fid() {
    local team_slug="$1"
    local service_fid_dev="$2"
    local service_fid_prod="$3"

    # ACCOUNT_TYPE env var — default "dev"
    local account_type="${ACCOUNT_TYPE:-dev}"
    account_type="${account_type,,}"  # lowercase
    [[ "$account_type" == "prod" ]] || account_type="dev"

    local pv_file="${TOOLCHAINS_CLONE_DIR}/${team_slug}-ci-pipeline_vars.tf"

    if [ ! -f "$pv_file" ]; then
        echo -e "${YELLOW}[WARNING]${NC} CI pipeline_vars file not found — skipping FID patch: ${pv_file}" >&2
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
        echo -e "${RED}[ERROR]${NC} service_fid_${account_type} is missing in onboarding YAML — cannot patch CI pipeline_vars for ${team_slug}" >&2
        return 1
    fi

    echo -e "${BLUE}[INFO]${NC} Patching CI pipeline_vars FID (ACCOUNT_TYPE=${account_type}): ${fid_email}"

    python3 - "$pv_file" "$fid_email" <<'PYEOF'
import sys, re

pv_file   = sys.argv[1]
fid_email = sys.argv[2]

# Placeholder string as written in the template — only replace when still at this value.
PLACEHOLDER_FID = "service-functional-id-email"

with open(pv_file) as f:
    content = f.read()

# Only replace when the value is still the placeholder (not a real email).
# Pattern matches:
#   "service-functional-id-email" = {
#     ...
#     value = "service-functional-id-email"   ← only this literal placeholder
#   }
new_content = re.sub(
    r'("service-functional-id-email"\s*=\s*\{[^}]*?value\s*=\s*)"' + re.escape(PLACEHOLDER_FID) + r'"',
    lambda m: m.group(1) + f'"{fid_email}"',
    content,
    count=1,
    flags=re.DOTALL
)

if new_content == content:
    # Either already patched with a real value, or pattern not found — either way, skip.
    print(f"INFO: 'service-functional-id-email' already set or placeholder not found — skipping", file=sys.stderr)
else:
    with open(pv_file, 'w') as f:
        f.write(new_content)
    print(f"INFO: Patched service-functional-id-email → {fid_email}", file=sys.stderr)
PYEOF
}

# ---------------------------------------------------------------------------
# Function: patch_ci_pipeline_vars_target
#
# Patches the "target-environment" and "target-region" values inside
# common_ci_pipeline_env_props in the team's <team-slug>-ci-pipeline_vars.tf.
#
# target-environment = env_code  (e.g. "us-east-prod01-cloud-regional")
# target-region      = first two hyphen-separated segments of env_code
#                      (e.g. "us-east")
#
# Always overwrites the current value — whether it is still the empty
# placeholder "" or a previously set real value.  This ensures that a
# change to deployment_targets.CI in the onboarding YAML is propagated to
# the pipeline_vars.tf on every merge, not just the first time.
#
# If the file is absent this is a warning (not an error) so old branches
# that pre-date the CI target fields are not broken.
#
# Args:
#   $1  team_slug
#   $2  ci_env_code  — raw env_code from deployment_targets.CI
# ---------------------------------------------------------------------------
patch_ci_pipeline_vars_target() {
    local team_slug="$1"
    local ci_env_code="$2"

    if [ -z "$ci_env_code" ]; then
        echo -e "${YELLOW}[WARNING]${NC} No CI env_code found in onboarding YAML — skipping target patch for ${team_slug}" >&2
        return 0
    fi

    local pv_file="${TOOLCHAINS_CLONE_DIR}/${team_slug}-ci-pipeline_vars.tf"

    if [ ! -f "$pv_file" ]; then
        echo -e "${YELLOW}[WARNING]${NC} CI pipeline_vars file not found — skipping target patch: ${pv_file}" >&2
        return 0
    fi

    echo -e "${BLUE}[INFO]${NC} Patching CI pipeline_vars target-environment / target-region for ${team_slug} (env_code: ${ci_env_code})"

    python3 - "$pv_file" "$ci_env_code" <<'PYEOF'
import sys, re

pv_file  = sys.argv[1]
env_code = sys.argv[2]

# Derive target-region: first two hyphen-separated segments of env_code.
# e.g. "us-east-prod01-cloud-regional" → "us-east"
parts = env_code.split('-')
target_region = '-'.join(parts[:2]) if len(parts) >= 2 else env_code

with open(pv_file) as f:
    content = f.read()

patched = False


def replace_value(content, key, new_value):
    """Replace the quoted value inside a { ... } block for the given key.

    Matches both the empty placeholder:
        "key" = { ... value = ""  }
    and a previously set real value:
        "key" = { ... value = "some-old-value"  }

    Returns (new_content, old_value | None, changed).
    old_value is None when the key was not found.
    """
    pattern = re.compile(
        r'("' + re.escape(key) + r'"\s*=\s*\{[^}]*?value\s*=\s*)"([^"]*)"(\s*\})',
        re.DOTALL,
    )
    m = pattern.search(content)
    if not m:
        return content, None, False
    old_value = m.group(2)
    if old_value == new_value:
        return content, old_value, False   # already correct — no write needed
    new_content = pattern.sub(r'\g<1>"' + new_value + r'"\3', content, count=1)
    return new_content, old_value, True


content, old_env, changed = replace_value(content, 'target-environment', env_code)
if changed:
    patched = True
    print(f'INFO: patched target-environment: "{old_env}" → "{env_code}"', file=sys.stderr)
elif old_env is None:
    print('INFO: target-environment key not found in pipeline_vars — skipping', file=sys.stderr)
else:
    print(f'INFO: target-environment already "{env_code}" — no change needed', file=sys.stderr)

content, old_reg, changed = replace_value(content, 'target-region', target_region)
if changed:
    patched = True
    print(f'INFO: patched target-region: "{old_reg}" → "{target_region}"', file=sys.stderr)
elif old_reg is None:
    print('INFO: target-region key not found in pipeline_vars — skipping', file=sys.stderr)
else:
    print(f'INFO: target-region already "{target_region}" — no change needed', file=sys.stderr)

if patched:
    with open(pv_file, 'w') as f:
        f.write(content)
PYEOF
}

# ---------------------------------------------------------------------------
# Function: team_ci_branch_exists
#
# Returns 0 if <team-slug>-ci already exists on the remote, 1 otherwise.
# ---------------------------------------------------------------------------
team_ci_branch_exists() {
    local branch_name="$1"
    cd "${TOOLCHAINS_CLONE_DIR}"
    git fetch origin "$branch_name" &>/dev/null || true
    git show-ref --verify --quiet "refs/remotes/origin/${branch_name}"
}

# ---------------------------------------------------------------------------
# Function: scaffold_team_ci_branch
#
# Creates a brand-new <team-slug>-ci branch in the toolchains repo by
# delegating directly to create-team-branch.sh (scripts/create-team-branch.sh
# on the main branch of uuc-toolchains-tf-module).
#
# create-team-branch.sh is the canonical way to initialise a team branch;
# calling it here keeps the two code paths in sync automatically — any
# future template changes are picked up for free.
#
# The script is run from inside TOOLCHAINS_CLONE_DIR (which is on main at
# this point) so its relative paths (templates/, scripts/) resolve correctly.
# It handles git checkout / push internally; we return to the new branch
# afterwards so the rest of create_ci_toolchains_pr can operate on it.
#
# Args:
#   $1  team_name      — human-readable (e.g. "Core Services")
#   $2  team_slug      — hyphenated lowercase (e.g. "core-services")
#   $3  secret_group   — e.g. "sg-uuc-core-services"
#   $4  resource_group — e.g. "UUC_Core_Services"
# ---------------------------------------------------------------------------
scaffold_team_ci_branch() {
    local team_name="$1"
    local team_slug="$2"
    local secret_group="$3"
    local resource_group="$4"
    local branch_name="${team_slug}-ci"

    echo -e "${BLUE}[INFO]${NC} Scaffolding new CI branch '${branch_name}' via create-team-branch.sh (local only, no push)..."

    # create-team-branch.sh lives on main of the toolchains repo.
    # TOOLCHAINS_CLONE_DIR is currently on main (cloned above), so the
    # scripts/ and templates/ directories are present and accessible.
    local create_branch_script="${TOOLCHAINS_CLONE_DIR}/scripts/create-team-branch.sh"

    if [ ! -f "$create_branch_script" ]; then
        echo -e "${RED}[ERROR]${NC} create-team-branch.sh not found at: ${create_branch_script}" >&2
        echo -e "${RED}[ERROR]${NC} Ensure TOOLCHAINS_CLONE_DIR is on the main branch." >&2
        return 1
    fi

    # Run the script from within the cloned repo so all relative paths work.
    # Pass 'yes' via stdin to bypass the interactive confirmation prompt.
    # NO_PUSH=true suppresses the final 'git push' inside create-team-branch.sh
    # so the scaffolded branch only exists locally.  The toolchain block and
    # terraform fmt are applied on top before create_ci_toolchains_pr() pushes
    # the single PR branch — keeping the remote clean until then.
    # Args: <team-name> <deployment-type> <secret-group> <resource-group>
    (
        cd "${TOOLCHAINS_CLONE_DIR}"
        git config user.name "clconc"
        git config user.email "clconc@us.ibm.com"
        echo "yes" | NO_PUSH=true bash "$create_branch_script" \
            "$team_name" \
            "ci" \
            "$secret_group" \
            "$resource_group"
    ) || {
        echo -e "${RED}[ERROR]${NC} create-team-branch.sh failed for team '${team_name}'" >&2
        return 1
    }

    # The branch now exists locally only.  Switch to it so subsequent git
    # commands in create_ci_toolchains_pr() operate on the correct branch.
    cd "${TOOLCHAINS_CLONE_DIR}"
    git checkout "$branch_name"

    echo -e "${GREEN}[SUCCESS]${NC} Scaffolded CI branch '${branch_name}' locally for ${team_name} (not yet pushed)"
}

# ---------------------------------------------------------------------------
# Function: patch_toolchain_locals_in_tf
#
# For an existing toolchain entry that already matches on repo URLs, checks
# whether cicd_profile, pipeline_types_trigger_data, and pipeline_meta are
# correct and patches them in-place if stale or missing.
#
# Expected values (example for team "fabric", profile "ci_only"):
#   cicd_profile                = "ci_only"
#   pipeline_types_trigger_data = local.fabric_ci_trigger_data_ci_only
#   pipeline_meta               = local.fabric_ci_pipeline_meta_ci_only
#
# The patch is scoped to the toolchain block that contains app_repo so that
# other entries in the same file are not touched.
#
# Returns:
#   0 — file was patched (one or more fields were stale or missing)
#   1 — nothing to patch (all fields already correct)
#
# Args:
#   $1  tf_file
#   $2  app_repo_url
#   $3  team_slug
#   $4  cicd_profile
# ---------------------------------------------------------------------------
patch_toolchain_locals_in_tf() {
    local tf_file="$1"
    local app_repo="$2"
    local team_slug="$3"
    local cicd_profile="$4"

    local app_bare="${app_repo%.git}"
    local team_underscore="${team_slug//-/_}"

    python3 - "$tf_file" "$app_bare" "$team_underscore" "$cicd_profile" <<'PYEOF'
import sys, re

tf_file        = sys.argv[1]
app_bare       = sys.argv[2]
team_us        = sys.argv[3]
cicd_profile   = sys.argv[4]

expected_trigger = f"local.{team_us}_ci_trigger_data_{cicd_profile}"
expected_meta    = f"local.{team_us}_ci_pipeline_meta_{cicd_profile}"

with open(tf_file) as f:
    content = f.read()

# Locate the toolchain block that contains this app_repo URL.
# IMPORTANT: scope the search to inside the toolchains = [ ... ] list only,
# exactly as toolchain_entry_status_in_tf and update_ci_toolchain_repos_in_tf do.
# Walking the entire file finds the outer module { ... } block first (which
# contains every entry), causing count=1 regex substitutions to wrongly patch
# the first occurrence in the file rather than the target toolchain block.
app_pattern = re.escape(app_bare) + r'(?:\.git)?["\']'

# ── Step 1: locate the toolchains = [ ... ] list ─────────────────────────────
list_match = re.search(r'\btoolchains\s*=\s*\[', content)
if not list_match:
    print("WARNING: could not locate 'toolchains = [' in file — skipping patch", file=sys.stderr)
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
    print("WARNING: could not locate closing ']' for toolchains list — skipping patch", file=sys.stderr)
    sys.exit(1)

list_body   = content[list_start:list_end]
list_offset = list_start

# ── Step 2: collect { ... } blocks inside the list ───────────────────────────
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

# ── Step 3: find the block that contains app_bare ────────────────────────────
target_range = None
for start, end in block_ranges:
    block_body = content[start:end]
    # Only check uncommented lines to avoid matching stale commented-out URLs
    uncommented = re.sub(r'#[^\n]*', '', block_body)
    if re.search(app_pattern, uncommented):
        target_range = (start, end)
        break

if target_range is None:
    # Should not happen — caller already confirmed entry exists
    print("WARNING: could not locate toolchain block for patching", file=sys.stderr)
    sys.exit(1)

block_body = content[target_range[0]:target_range[1]]
original_block = block_body
patched = False

# Patch cicd_profile — update if stale, insert after repo_org line if missing
profile_pat = re.compile(r'(cicd_profile\s*=\s*)"[^"]*"')
if profile_pat.search(block_body):
    new_body = profile_pat.sub(r'\g<1>"' + cicd_profile + '"', block_body, count=1)
    if new_body != block_body:
        block_body = new_body
        patched = True
        print(f"INFO: patched cicd_profile → \"{cicd_profile}\"", file=sys.stderr)
else:
    # Field absent — insert it on a new line after the repo_org line
    new_body = re.sub(
        r'(repo_org\s*=\s*"[^"]*")',
        r'\1\n      cicd_profile  = "' + cicd_profile + '"',
        block_body, count=1
    )
    if new_body != block_body:
        block_body = new_body
        patched = True
        print(f"INFO: inserted cicd_profile = \"{cicd_profile}\"", file=sys.stderr)

# Patch pipeline_types_trigger_data if stale
trigger_pat = re.compile(
    r'(pipeline_types_trigger_data\s*=\s*)local\.\S+'
)
if trigger_pat.search(block_body):
    new_body = trigger_pat.sub(r'\g<1>' + expected_trigger, block_body, count=1)
    if new_body != block_body:
        block_body = new_body
        patched = True
        print(f"INFO: patched pipeline_types_trigger_data → {expected_trigger}", file=sys.stderr)

# Patch pipeline_meta if stale
meta_pat = re.compile(
    r'(pipeline_meta\s*=\s*)local\.\S+'
)
if meta_pat.search(block_body):
    new_body = meta_pat.sub(r'\g<1>' + expected_meta, block_body, count=1)
    if new_body != block_body:
        block_body = new_body
        patched = True
        print(f"INFO: patched pipeline_meta → {expected_meta}", file=sys.stderr)

if not patched:
    print("INFO: cicd_profile, pipeline_types_trigger_data, and pipeline_meta are already correct — no patch needed", file=sys.stderr)
    sys.exit(1)

new_content = content[:target_range[0]] + block_body + content[target_range[1]:]
with open(tf_file, 'w') as f:
    f.write(new_content)
sys.exit(0)
PYEOF
}

# ---------------------------------------------------------------------------
# Function: toolchain_entry_status_in_tf
#
# Prints one of three status strings to stdout and always exits 0:
#   "exact"  — entry found and all relevant repo URLs match the onboarding YAML
#   "stale"  — entry found by pipeline_name but one or more repo URLs differ
#   "missing"— no entry found for this pipeline_name
#
# The check is profile-aware:
#   minimal  — matches on app_repo only
#   ci_only  — matches on app_repo + incident_repo_url
#   ci_cd    — matches on app_repo + inventory_repo_url + incident_repo_url
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
# Args:
#   $1  tf_file           — absolute path to the toolchains .tf file
#   $2  service_name      — used to derive pipeline_name (the stable identity key)
#   $3  app_repo_url
#   $4  inventory_repo_url  (empty for minimal/ci_only)
#   $5  incident_repo_url   (empty for minimal)
#   $6  cicd_profile
# ---------------------------------------------------------------------------
toolchain_entry_status_in_tf() {
    local tf_file="$1"
    local service_name="$2"
    local app_repo="$3"
    local inv_repo="$4"
    local inc_repo="$5"
    local cicd_profile="$6"

    [ -f "$tf_file" ] || { echo "missing"; return 0; }

    # Derive pipeline_name slug (mirrors generate_toolchain_block)
    local pipeline_name
    pipeline_name=$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr ' ' '-')

    # Strip trailing .git for a loose match — some entries may omit it
    local app_bare="${app_repo%.git}"
    local inv_bare="${inv_repo%.git}"
    local inc_bare="${inc_repo%.git}"

    python3 - <<EOF
import sys, re

tf_file       = '$tf_file'
pipeline_name = '$pipeline_name'
app_bare      = '$app_bare'
inv_bare      = '$inv_bare'
inc_bare      = '$inc_bare'
cicd_profile  = '$cicd_profile'

with open(tf_file) as f:
    content = f.read()

def url_present_in_block(block, bare_url):
    """True if bare_url (with or without .git) appears in an uncommented line of block."""
    if not bare_url:
        return True  # nothing to check — treat as satisfied
    pattern = re.escape(bare_url) + r'(?:\.git)?["\']'
    # Only check non-commented lines
    uncommented = re.sub(r'#[^\n]*', '', block)
    return bool(re.search(pattern, uncommented))

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
# pipeline_name is the stable identity; repo URLs may have changed.
# Also match the underscore variant (e.g. "uuc_ns3_host_configs") so that
# blocks written by an older buggy run that kept raw underscores are found.
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

# ── Check whether all required repo URLs already match ───────────────────────
check_inv = cicd_profile == 'ci_cd'
check_inc = cicd_profile in ('ci_only', 'ci_cd')

urls_match = (
    url_present_in_block(target_block, app_bare) and
    (not check_inv or url_present_in_block(target_block, inv_bare)) and
    (not check_inc or url_present_in_block(target_block, inc_bare))
)

print("exact" if urls_match else "stale")
sys.exit(0)
EOF
}

# ---------------------------------------------------------------------------
# Function: update_ci_toolchain_repos_in_tf
#
# Finds the toolchain block identified by pipeline_name and patches any repo
# URL fields that differ from the values supplied.
#
# Fields updated (when changed):
#   repo              ← app_repo_url
#   repo_branch       ← app_branch
#   repo_org          ← app_org
#   inventory_repo_url← inv_repo_url  (ci_cd profile only)
#   incident_repo_url ← inc_repo_url  (ci_only / ci_cd profiles)
#
# Returns:
#   0 — one or more fields were patched
#   1 — all fields already up to date (or block not found)
#
# Args:
#   $1  tf_file
#   $2  service_name   — used to derive pipeline_name
#   $3  app_repo_url
#   $4  app_branch
#   $5  app_org
#   $6  inventory_repo_url  (empty for minimal/ci_only)
#   $7  incident_repo_url   (empty for minimal)
#   $8  cicd_profile
# ---------------------------------------------------------------------------
update_ci_toolchain_repos_in_tf() {
    local tf_file="$1"
    local service_name="$2"
    local app_repo="$3"
    local app_branch="$4"
    local app_org="$5"
    local inv_repo="$6"
    local inc_repo="$7"
    local cicd_profile="$8"

    local pipeline_name
    pipeline_name=$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr ' ' '-')

    # Ensure .git suffix on URLs
    local app_repo_git="${app_repo%.git}.git"
    local inv_repo_git="${inv_repo%.git}.git"
    local inc_repo_git="${inc_repo%.git}.git"

    python3 - "$tf_file" "$pipeline_name" \
              "$app_repo_git" "$app_branch" "$app_org" \
              "$inv_repo_git" "$inc_repo_git" \
              "$cicd_profile" <<'PYEOF'
import sys, re

tf_file       = sys.argv[1]
pipeline_name = sys.argv[2]
app_repo      = sys.argv[3]
app_branch    = sys.argv[4]
app_org       = sys.argv[5]
inv_repo      = sys.argv[6]
inc_repo      = sys.argv[7]
cicd_profile  = sys.argv[8]

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
original_body = block_body
patched       = False

def patch_field(body, field_name, new_value):
    """Replace the quoted value of a simple string assignment field in the block."""
    pat = re.compile(r'(' + re.escape(field_name) + r'\s*=\s*)"[^"]*"')
    new_body = pat.sub(r'\g<1>"' + new_value + '"', body, count=1)
    changed = new_body != body
    return new_body, changed

# repo (app repo URL)
block_body, changed = patch_field(block_body, 'repo', app_repo)
if changed:
    patched = True
    print(f"INFO: patched repo → \"{app_repo}\"", file=sys.stderr)

# repo_branch
block_body, changed = patch_field(block_body, 'repo_branch', app_branch)
if changed:
    patched = True
    print(f"INFO: patched repo_branch → \"{app_branch}\"", file=sys.stderr)

# repo_org
block_body, changed = patch_field(block_body, 'repo_org', app_org)
if changed:
    patched = True
    print(f"INFO: patched repo_org → \"{app_org}\"", file=sys.stderr)

# inventory_repo_url (ci_cd only)
if cicd_profile == 'ci_cd' and inv_repo.rstrip('.git'):
    block_body, changed = patch_field(block_body, 'inventory_repo_url', inv_repo)
    if changed:
        patched = True
        print(f"INFO: patched inventory_repo_url → \"{inv_repo}\"", file=sys.stderr)

# incident_repo_url (ci_only / ci_cd)
if cicd_profile in ('ci_only', 'ci_cd') and inc_repo.rstrip('.git'):
    block_body, changed = patch_field(block_body, 'incident_repo_url', inc_repo)
    if changed:
        patched = True
        print(f"INFO: patched incident_repo_url → \"{inc_repo}\"", file=sys.stderr)

if not patched:
    print("INFO: all repo URL fields already up to date — no patch needed", file=sys.stderr)
    sys.exit(1)

new_content = content[:target_range[0]] + block_body + content[target_range[1]:]
with open(tf_file, 'w') as f:
    f.write(new_content)
sys.exit(0)
PYEOF
}

# ---------------------------------------------------------------------------
# Function: generate_toolchain_block
#
# Emits a single toolchain entry { ... } ready to be appended inside the
# toolchains = [ ... ] list in the .tf file.
#
# The block is profile-aware:
#   minimal  — no inventory_repo_url, no incident_repo_url
#   ci_only  — no inventory_repo_url; incident_repo_url included if non-empty
#   ci_cd    — both inventory_repo_url and incident_repo_url included
#
# Profile-specific locals are used for pipeline_types_trigger_data and pipeline_meta.
#
# Args:
#   $1  team_slug
#   $2  service_name         — becomes the pipeline_name / toolchain name base
#   $3  app_repo_url         — full .git URL
#   $4  app_branch
#   $5  app_org
#   $6  inventory_repo_url   (empty for minimal/ci_only)
#   $7  incident_repo_url    (empty for minimal)
#   $8  cicd_profile         — minimal | ci_only | ci_cd
# ---------------------------------------------------------------------------
generate_toolchain_block() {
    local team_slug="$1"
    local service_name="$2"
    local app_repo="$3"
    local app_branch="$4"
    local app_org="$5"
    local inv_repo="$6"
    local inc_repo="$7"
    local cicd_profile="$8"

    # service_slug: lowercase hyphenated form of service_name — used for name,
    # pipeline_name, and local variable references (mirrors how create-team-branch.sh
    # normalises TEAM_NAME → TEAM_NAME_HYPHEN / TEAM_NAME_UNDERSCORE).
    local service_slug team_underscore
    service_slug=$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr ' ' '-')
    # team_underscore is used for the Terraform local variable names, e.g.
    #   local.fabric_ci_tc_env_props  (team=fabric, deployment=ci)
    team_underscore="${team_slug//-/_}"

    # GUID prefix = service_name slug  (e.g. "ns3-ntpsec-<uuid>")
    local guid
    guid=$(python3 -c "import uuid; print('${service_slug}-' + str(uuid.uuid4()))")

    # Ensure app repo URL carries a .git suffix (required by the Terraform module)
    local app_repo_git
    app_repo_git="${app_repo%.git}.git"

    # Build optional repo URL lines based on profile
    local inv_line="" inc_line=""
    if [ "$cicd_profile" = "ci_cd" ] && [ -n "$inv_repo" ]; then
        local inv_repo_git="${inv_repo%.git}.git"
        inv_line="      inventory_repo_url = \"${inv_repo_git}\""
    fi
    if [ "$cicd_profile" != "minimal" ] && [ -n "$inc_repo" ]; then
        local inc_repo_git="${inc_repo%.git}.git"
        inc_line="      incident_repo_url  = \"${inc_repo_git}\""
    fi

    # Profile-specific local variable suffixes
    local profile_suffix="$cicd_profile"

    cat <<EOF
    {
      guid          = "${guid}" # Generate unique GUID using 'uuidgen' locally or online tool
      name          = "${service_slug}-ci-toolchain"
      repo          = "${app_repo_git}"
      pipeline_name = "${service_slug}"
      repo_branch   = "${app_branch}"
      repo_org      = "${app_org}"
      cicd_profile  = "${cicd_profile}"
$([ -n "$inv_line" ] && echo "$inv_line")
$([ -n "$inc_line" ] && echo "$inc_line")
      tags         = ["team:${team_slug}", "type:ci", "template:uuc_common_ci", "profile:${cicd_profile}"]
      resource_grp = var.resource_group
      # ---------------------------------------------------------------------------------
      # - ENV PROPS (toolchain) THAT WILL BE COPIED TO EACH PIPELINE OF A GIVEN TOOLCHAIN
      # ---------------------------------------------------------------------------------
      tc_env_props                = local.${team_underscore}_ci_tc_env_props
      pipeline_types_trigger_data = local.${team_underscore}_ci_trigger_data_${profile_suffix}
      # ---------------------------------------------------------------------------------
      # - PIPELINE SPECIFIC METADATA (pipeline) ie ENV PROPERTIES FOR A GIVEN PIPELINE
      # ---------------------------------------------------------------------------------
      pipeline_meta = local.${team_underscore}_ci_pipeline_meta_${profile_suffix}
    }
EOF
}

# ---------------------------------------------------------------------------
# Function: append_toolchain_to_tf
#
# Inserts a new toolchain block into the toolchains = [ ... ] list inside the
# team's <team-slug>-ci-toolchains.tf file, just before the closing ].
# Uses Python for reliable bracket-depth tracking.
#
# Args:
#   $1  tf_file        — absolute path to the toolchains .tf file
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

print(f"INFO: Appended toolchain block to {tf_file}", file=sys.stderr)
sys.exit(0)
PYEOF
}

# ---------------------------------------------------------------------------
# Function: remove_toolchain_from_tf
#
# Finds the toolchain block identified by pipeline_name inside the
# toolchains = [ ... ] list of the given .tf file and removes it entirely,
# including any preceding or trailing comma/whitespace that would leave the
# list malformed.
#
# Returns:
#   0 — block found and removed
#   1 — block not found (pipeline_name absent) — no file change
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

# ── Collect { ... } block ranges (absolute positions in content) ─────────────
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

# ── Determine the slice to remove (block + surrounding comma + blank lines) ──
# We want to remove:
#   - Any trailing comma after the closing '}'
#   - Any blank lines immediately before or after the block
# Strategy: expand the removal region to include leading/trailing whitespace
# and a comma (either trailing on the previous entry or following this entry).

remove_start = target_range[0]
remove_end   = target_range[1]

# Absorb trailing comma + whitespace after the block
tail = content[remove_end:]
m = re.match(r'\s*,', tail)
if m:
    remove_end += m.end()

# Absorb any remaining leading whitespace / newlines before the block
# back to the previous non-blank line (to avoid leaving an extra blank line)
head = content[:remove_start]
m = re.search(r'\n[ \t]*$', head)
if m:
    remove_start = remove_start - (len(head) - m.start())

new_content = content[:remove_start] + content[remove_end:]

# ── Ensure the last remaining entry in the list does NOT have a trailing comma
# (Terraform / HCL is fine with trailing commas in lists, so this is cosmetic)

with open(tf_file, 'w') as f:
    f.write(new_content)

print(f"INFO: Removed toolchain block for pipeline_name='{pipeline_name}'", file=sys.stderr)
sys.exit(0)
PYEOF
}

# ---------------------------------------------------------------------------
# Function: create_ci_toolchains_pr
#
# Orchestrates the full flow for one team:
#   1. Create/checkout the team CI branch.
#   2. Scaffold it from templates if new.
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
create_ci_toolchains_pr() {
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

    local team_branch="${team_slug}-ci"
    local tf_filename="${team_slug}-ci-toolchains.tf"

    local action="Onboard"
    [ "$is_new_branch" = "false" ] && action="Update"

    local pr_title="feat: Add ${team_name} CI toolchains"

    cd "${TOOLCHAINS_CLONE_DIR}"

    # ── Set up team branch ────────────────────────────────────────────────────
    if [ "$is_new_branch" = "true" ]; then
        # Derive secret/resource group names from team slug
        local secret_group="sg-uuc-${team_slug}"
        local resource_group
        resource_group="UUC_$(echo "${team_name}" | tr ' ' '_')"

        scaffold_team_ci_branch "$team_name" "$team_slug" "$secret_group" "$resource_group"
    else
        echo -e "${BLUE}[INFO]${NC} Checking out existing team branch: ${team_branch}"
        git fetch origin "$team_branch"
        git checkout "$team_branch"
        git reset --hard "origin/${team_branch}"
    fi

    # ── Patch pipeline_vars FID and env target ────────────────────────────────
    # Requires at least one onboarding file to read from.
    # In a pure-offboard scenario (only --offboard args, no new/changed files)
    # onboarding_files is empty — skip to avoid "[ERROR] Onboarding file not found: ".
    if [ ${#onboarding_files[@]} -gt 0 ]; then
        local _first_tc_info _fid_dev _fid_prod
        _first_tc_info=$(extract_toolchain_info_from_onboarding "${onboarding_files[0]}") || true
        local _ci_env_code
        IFS='|' read -r _ _ _ _ _ _ _ _ _fid_dev _fid_prod _ _ci_env_code <<< "$_first_tc_info"
        patch_ci_pipeline_vars_fid    "$team_slug" "$_fid_dev" "$_fid_prod"
        patch_ci_pipeline_vars_target "$team_slug" "$_ci_env_code"
    else
        echo -e "${BLUE}[INFO]${NC} Pure offboard — skipping FID patch and env target update for ${team_slug}"
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
        echo -e "${BLUE}[INFO]${NC} Offboarding ${#offboard_names[@]} CI toolchain(s) for ${team_name}"
        for old_pipeline_name in "${offboard_names[@]}"; do
            echo -e "${BLUE}[INFO]${NC} Removing CI toolchain block for pipeline_name='${old_pipeline_name}'"
            if remove_toolchain_from_tf "$tf_file" "$old_pipeline_name"; then
                echo -e "${GREEN}[SUCCESS]${NC} Removed CI toolchain for '${old_pipeline_name}'"
                removed_services+=("$old_pipeline_name")
                removed_count=$(( removed_count + 1 ))
            else
                echo -e "${YELLOW}[WARNING]${NC} No CI toolchain block found for '${old_pipeline_name}' — already removed or never existed"
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

        local tc_info
        tc_info=$(extract_toolchain_info_from_onboarding "$onboarding_file") || {
            echo -e "${YELLOW}[WARNING]${NC} Failed to extract toolchain info from: $(basename "$onboarding_file") — skipping (file may be part of an offboard)" >&2
            skipped_count=$(( skipped_count + 1 ))
            skip_reasons+=("$(basename "$onboarding_file"): could not parse onboarding YAML (offboard scenario)")
            continue
        }

        local t_team_name t_team_slug service_name app_repo app_branch app_org inv_repo inc_repo _fid_dev_unused _fid_prod_unused cicd_profile _ci_env_code_unused
        IFS='|' read -r t_team_name t_team_slug service_name app_repo app_branch app_org inv_repo inc_repo _fid_dev_unused _fid_prod_unused cicd_profile _ci_env_code_unused <<< "$tc_info"

        echo -e "${BLUE}[INFO]${NC} cicd_profile is '${cicd_profile}' for $(basename "$onboarding_file")"

        # Validate required fields based on profile
        if [ -z "$app_repo" ]; then
            echo -e "${YELLOW}[WARNING]${NC} Missing app_repo URL in: $(basename "$onboarding_file") — skipping" >&2
            skip_reasons+=("$(basename "$onboarding_file"): missing app_repo URL")
            skipped_count=$(( skipped_count + 1 ))
            continue
        fi
        if [ "$cicd_profile" = "ci_cd" ] && [ -z "$inv_repo" ]; then
            echo -e "${YELLOW}[WARNING]${NC} Missing inventory_repo URL for ci_cd profile in: $(basename "$onboarding_file") — skipping" >&2
            skip_reasons+=("$(basename "$onboarding_file"): missing inventory_repo URL (required for ci_cd)")
            skipped_count=$(( skipped_count + 1 ))
            continue
        fi
        if [ "$cicd_profile" != "minimal" ] && [ -z "$inc_repo" ]; then
            echo -e "${YELLOW}[WARNING]${NC} Missing incident_repo URL for ${cicd_profile} profile in: $(basename "$onboarding_file") — skipping" >&2
            skip_reasons+=("$(basename "$onboarding_file"): missing incident_repo URL (required for ${cicd_profile})")
            skipped_count=$(( skipped_count + 1 ))
            continue
        fi

        # Check idempotency: is a toolchain for this service already in the file?
        # toolchain_entry_status_in_tf returns: "exact" | "stale" | "missing"
        local tc_status
        tc_status=$(toolchain_entry_status_in_tf "$tf_file" "$service_name" "$app_repo" "$inv_repo" "$inc_repo" "$cicd_profile")

        if [ "$tc_status" = "stale" ]; then
            # Entry found by pipeline_name but one or more repo URLs changed in the
            # onboarding YAML — update the URLs in-place, then patch locals if needed.
            echo -e "${BLUE}[INFO]${NC} CI toolchain for '${service_name}' exists with stale repo URLs — updating"
            if update_ci_toolchain_repos_in_tf "$tf_file" "$service_name" \
                    "$app_repo" "$app_branch" "$app_org" "$inv_repo" "$inc_repo" "$cicd_profile"; then
                echo -e "${GREEN}[SUCCESS]${NC} Updated repo URLs for '${service_name}'"
            else
                echo -e "${YELLOW}[WARNING]${NC} Repo URL update returned no changes for '${service_name}'"
            fi
            # Also patch locals (cicd_profile / trigger_data / pipeline_meta) in case they are stale too
            patch_toolchain_locals_in_tf "$tf_file" "$app_repo" "$team_slug" "$cicd_profile" || true
            appended_services+=("${service_name} [repos + locals updated]")
            added_toolchain_details+=("${service_name}|${app_repo}|${app_branch}|${inv_repo}|${inc_repo}")
            appended_count=$(( appended_count + 1 ))
            continue
        fi

        if [ "$tc_status" = "exact" ]; then
            echo -e "${BLUE}[INFO]${NC} CI toolchain for '${service_name}' already exists in ${tf_filename} — checking locals"
            # Entry exists and all URLs match: only patch locals if stale
            if patch_toolchain_locals_in_tf "$tf_file" "$app_repo" "$team_slug" "$cicd_profile"; then
                echo -e "${GREEN}[SUCCESS]${NC} Patched stale locals for '${service_name}' (profile: ${cicd_profile})"
                appended_services+=("${service_name} [locals patched]")
                added_toolchain_details+=("${service_name}|${app_repo}|${app_branch}|${inv_repo}|${inc_repo}")
                appended_count=$(( appended_count + 1 ))
            else
                echo -e "${BLUE}[INFO]${NC} Locals already correct for '${service_name}' — skipping"
                skip_reasons+=("${service_name}: CI toolchain already existed (locals up to date)")
                skipped_count=$(( skipped_count + 1 ))
            fi
            continue
        fi

        # tc_status = "missing" — fall through to append new block

        # Generate and append the new toolchain block
        echo -e "${BLUE}[INFO]${NC} Appending toolchain block for '${service_name}' (profile: ${cicd_profile})"
        local block
        block=$(generate_toolchain_block "$team_slug" "$service_name" \
            "$app_repo" "$app_branch" "$app_org" "$inv_repo" "$inc_repo" "$cicd_profile")

        if ! append_toolchain_to_tf "$tf_file" "$block"; then
            echo -e "${RED}[ERROR]${NC} Failed to append toolchain block for: ${service_name}" >&2
            return 1
        fi

        appended_services+=("$service_name")
        added_toolchain_details+=("${service_name}|${app_repo}|${app_branch}|${inv_repo}|${inc_repo}")
        appended_count=$(( appended_count + 1 ))
        echo -e "${GREEN}[SUCCESS]${NC} Appended toolchain for '${service_name}'"
    done

    # ── Bail out if nothing changed ───────────────────────────────────────────
    # Also check whether pipeline_vars.tf was modified by the FID/target patches
    # even when no toolchain blocks were added or removed.
    local _pv_dirty=false
    if [ "$is_new_branch" = "false" ] && [ "$appended_count" -eq 0 ] && [ "$removed_count" -eq 0 ]; then
        local _pv_file="${TOOLCHAINS_CLONE_DIR}/${team_slug}-ci-pipeline_vars.tf"
        if git -C "${TOOLCHAINS_CLONE_DIR}" diff --quiet -- "${team_slug}-ci-pipeline_vars.tf" 2>/dev/null; then
            echo -e "${YELLOW}[WARNING]${NC} All CI toolchains already exist for ${team_name} — no PR needed"
            for reason in "${skip_reasons[@]}"; do
                echo -e "  ↳ ${reason}"
            done
            git checkout "$team_branch" 2>/dev/null || true
            return 2
        else
            echo -e "${BLUE}[INFO]${NC} pipeline_vars.tf was patched (FID/target) — creating PR for ${team_name}"
            _pv_dirty=true
        fi
    fi

    if [ "$_pv_dirty" = "true" ] && [ "$appended_count" -eq 0 ] && [ "$removed_count" -eq 0 ]; then
        pr_title="fix: Update ${team_name} CI pipeline_vars (FID/target)"
    elif [ "$removed_count" -gt 0 ] && [ "$appended_count" -eq 0 ]; then
        pr_title="chore: Offboard ${team_name} CI toolchain(s)"
    elif [ "$appended_count" -eq 1 ]; then
        # Use "update" wording when the change was a repo URL fix, not a new toolchain
        if [[ "${appended_services[0]}" == *"[repos"* ]]; then
            pr_title="fix: Update ${team_name} CI toolchain repo URLs for ${appended_services[0]%% \[*\]}"
        else
            pr_title="feat: Add ${team_name} CI toolchain for ${appended_services[0]}"
        fi
    fi

    git config user.name  "clconc"
    git config user.email "clconc@us.ibm.com"

    local pr_branch="auto-ci-toolchains-${team_slug}-$(date +%Y%m%d-%H%M%S)"
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
        #   3. terraform fmt + git add + commit — toolchain changes land only on pr branch
        #   4. git push origin <pr-branch>   — now 1 commit ahead of origin/<team-branch> ✓
        echo -e "${BLUE}[INFO]${NC} Pushing new team base branch (scaffold state): ${team_branch}"
        git push origin "${team_branch}"
        git checkout -b "$pr_branch"
        if command -v terraform &> /dev/null; then
            echo -e "${BLUE}[INFO]${NC} Running terraform fmt -recursive"
            terraform fmt -recursive \
                && echo -e "${GREEN}[SUCCESS]${NC} Terraform formatting completed" \
                || echo -e "${YELLOW}[WARNING]${NC} terraform fmt failed"
        else
            echo -e "${YELLOW}[WARNING]${NC} terraform not found, skipping fmt"
        fi
        git add .
        if git diff --cached --quiet; then
            echo -e "${YELLOW}[WARNING]${NC} No staged changes — CI toolchains are already up to date"
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
        #   2. terraform fmt + git add + git commit — all happen on the PR branch
        #
        # This guarantees the PR branch has exactly one new commit ahead of
        # origin/<team-branch>, with no stash or index gymnastics required.
        git checkout -b "$pr_branch"
        if command -v terraform &> /dev/null; then
            echo -e "${BLUE}[INFO]${NC} Running terraform fmt -recursive"
            terraform fmt -recursive \
                && echo -e "${GREEN}[SUCCESS]${NC} Terraform formatting completed" \
                || echo -e "${YELLOW}[WARNING]${NC} terraform fmt failed"
        else
            echo -e "${YELLOW}[WARNING]${NC} terraform not found, skipping fmt"
        fi
        git add "$tf_filename" "${team_slug}-ci-pipeline_vars.tf" 2>/dev/null || true
        if git diff --cached --quiet; then
            echo -e "${YELLOW}[WARNING]${NC} No staged changes — CI toolchains are already up to date"
            git checkout "$team_branch" 2>/dev/null || true
            return 2
        fi
        git commit -m "$pr_title"
    fi

    echo -e "${BLUE}[INFO]${NC} Pushing PR branch: ${pr_branch}"
    git push origin "$pr_branch"

    # ── Build PR body ─────────────────────────────────────────────────────────
    local pr_body
    pr_body="## Automated CI Toolchains ${action}: ${team_name}

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
- ✅ Created new team branch \`${team_branch}\` from \`main\` templates
- ✅ Scaffolded all CI template files (\`backend.tf\`, \`common.tf\`, \`variables.tf\`, \`versions.tf\`, \`pipeline_vars.tf\`, \`pipeline_meta.tf\`, \`toolchains.tf\`)
- ✅ Placeholder substitution applied (SECRET_GROUP, RESOURCE_GROUP, TEAM_NAME variants)
"
    fi

    if [ "$removed_count" -gt 0 ]; then
        pr_body+="
### CI Toolchains Offboarded (${removed_count})
"
        for svc in "${removed_services[@]}"; do
            pr_body+="- 🗑️  \`${svc}\` (toolchain block removed)
"
        done
    fi

    pr_body+="
### New CI Toolchains Added / Updated (${appended_count})
"
    for svc in "${appended_services[@]}"; do
        pr_body+="- ✅ \`${svc}\`
"
    done

    if [ "$appended_count" -gt 0 ]; then
        pr_body+="
### Added Toolchain Details
"
        local detail service_name_detail app_repo_detail app_branch_detail inv_repo_detail inc_repo_detail
        for detail in "${added_toolchain_details[@]}"; do
            IFS='|' read -r service_name_detail app_repo_detail app_branch_detail inv_repo_detail inc_repo_detail <<< "$detail"
            pr_body+="- \`${service_name_detail}\`
  - app repo: \`${app_repo_detail}\`
  - app branch: \`${app_branch_detail}\`
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

### Idempotency Check
Each toolchain entry was verified against the existing \`${tf_filename}\` using profile-aware URL matching:
- \`minimal\`  — matched on \`repo\` (app repository URL) only
- \`ci_only\`  — matched on \`repo\` + \`incident_repo_url\`
- \`ci_cd\`    — matched on \`repo\` + \`inventory_repo_url\` + \`incident_repo_url\`

Entries where all relevant URLs already matched were skipped.

### Next Steps
1. Review the appended toolchain block(s) in \`${tf_filename}\`
2. Verify the generated GUIDs are unique (replace if needed)
3. Confirm \`inventory_repo_url\` (ci_cd only) and \`incident_repo_url\` (ci_only/ci_cd) are correct
4. Merge this PR into branch \`${team_branch}\`
5. The merge pipeline will apply the Terraform configuration

### Related
- Source: uuc-service-cicd-onboarding repository
- Pipeline: UUC Ops Merge Pipeline
- Generated by: provision_team_ci_toolchains.sh

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
        # CI pipeline_vars FID is patched with the updated value.
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
        echo -e "${BLUE}[INFO]${NC} Skipping CI toolchains provisioning"
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
        IFS='|' read -r team_name team_slug _ _ _ _ _ _ _ _ _ _ <<< "$tc_info"

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
    # then pass it as --offboard so create_ci_toolchains_pr removes the stale block.
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
            # Convert to a path relative to the onboarding repo root for git show
            local rel_path="${deleted_file#${_onboarding_repo_root}/}"

            # Read the old content from the ONBOARDING repo's previous commit.
            # git -C ensures we operate on the onboarding repo regardless of cwd.
            local old_content
            old_content=$(git -C "$_onboarding_repo_root" show "HEAD~1:${rel_path}" 2>/dev/null) || {
                echo -e "${YELLOW}[WARNING]${NC} Could not read old content for deleted file: ${rel_path} — skipping offboard" >&2
                continue
            }

            # Extract old team_slug and service_name from the deleted YAML content.
            # team_name lives in commons.yaml (same directory as the deleted file),
            # NOT in the service YAML itself.  Read both from git history.
            local _commons_rel_path
            _commons_rel_path="$(dirname "$rel_path")/commons.yaml"
            local old_commons_content
            old_commons_content=$(git -C "$_onboarding_repo_root" show "HEAD~1:${_commons_rel_path}" 2>/dev/null) || \
                old_commons_content=$(git -C "$_onboarding_repo_root" show "HEAD~1:$(dirname "$rel_path")/commons.yml" 2>/dev/null) || \
                old_commons_content=""

            local old_team_slug old_service_name old_pipeline_name
            read -r old_team_slug old_service_name <<< "$(python3 - <<PYEOF
import yaml, sys

service_content = '''${old_content}'''
commons_content = '''${old_commons_content}'''

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

            old_pipeline_name="$old_service_name"  # already slugified above

            echo -e "${BLUE}[INFO]${NC} Offboard: team='${old_team_slug}' pipeline='${old_pipeline_name}' (from deleted ${rel_path})"

            # Accumulate into team_deleted_map — the team may not be in team_info_map
            # (pure offboard with no new/changed files for this team)
            if [ -z "${team_deleted_map[$old_team_slug]+x}" ]; then
                team_deleted_map["$old_team_slug"]="$old_pipeline_name"
                # Ensure team_info_map has an entry so the team loop processes it;
                # use the slug as a stand-in name if we have no better source
                if [ -z "${team_info_map[$old_team_slug]+x}" ]; then
                    team_info_map["$old_team_slug"]="$old_team_slug"
                    team_files_map["$old_team_slug"]=""   # no new files, offboard only
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
        # Ensure absolute path (mirrors the grouping loop above)
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
            # Resolve old path: git diff -M HEAD~1 HEAD -- <new-path> emits a rename line
            # of the form "old-name\tnew-name" when -M (find-renames) is active.
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
        IFS='|' read -r _ _cur_team_slug _cur_svc_slug _ _ _ _ _ _ _ _ _ <<< "$_cur_tc_info"
        # Derive slug from service_name field (field 3, index 2) the same way generate_toolchain_block does
        _cur_svc_slug=$(echo "$_cur_svc_slug" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr ' ' '-')

        # If service_name slug changed, the old block must be removed
        if [ "$_old_svc_slug" != "$_cur_svc_slug" ]; then
            echo -e "${BLUE}[INFO]${NC} Detected CI service_name rename in '$(basename "$_abs_file")': '${_old_svc_slug}' → '${_cur_svc_slug}' — scheduling old block for removal"
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
        local team_branch="${team_slug}-ci"
        echo -e "${BLUE}[INFO]${NC} Processing team: ${GREEN}${team_name}${NC} (branch: ${team_branch})"

        local is_new_branch="false"
        if team_ci_branch_exists "$team_branch"; then
            echo -e "${YELLOW}[INFO]${NC} Team branch '${team_branch}' already exists"
        else
            echo -e "${GREEN}[INFO]${NC} New team detected — will scaffold CI branch from templates"
            is_new_branch="true"
        fi

        # Build the onboarding file list for this team
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
        create_ci_toolchains_pr \
            "$team_name" "$team_slug" "$is_new_branch" \
            "${offboard_args[@]}" \
            "${team_onboarding_files[@]}" || pr_exit_code=$?

        if [ $pr_exit_code -eq 0 ]; then
            processed_teams+=("$team_slug")
            echo -e "${GREEN}[SUCCESS]${NC} CI toolchains PR created for ${team_name}"

            # ── Wait for PR to be merged ──────────────────────────────────────
            if [ -n "$CREATED_TOOLCHAINS_PR_URL" ]; then
                if ! wait_for_pr_merge "$CREATED_TOOLCHAINS_PR_URL" "$team_slug"; then
                    echo -e "${RED}[ERROR]${NC} PR for ${team_name} was not merged within the monitoring window."
                    exit_code=1
                else
                    # PR merged — wait for the triggered merge pipeline to complete
                    if ! wait_for_merge_pipeline \
                            "$CREATED_TOOLCHAINS_PR_URL" \
                            "$CREATED_TOOLCHAINS_PR_NUMBER" \
                            "$team_slug"; then
                        echo -e "${RED}[ERROR]${NC} Merge pipeline for ${team_name} CI toolchains did not succeed."
                        exit_code=1
                    fi
                fi
            else
                echo -e "${YELLOW}[WARNING]${NC} No PR URL captured for ${team_name} — skipping merge monitoring"
            fi

        elif [ $pr_exit_code -eq 2 ]; then
            echo -e "${BLUE}[INFO]${NC} No PR created for ${team_name} — CI toolchains already up to date"
        else
            echo -e "${RED}[ERROR]${NC} Failed to create CI toolchains PR for ${team_name}"
            exit_code=1
        fi

        echo ""
    done

    # ── Summary ───────────────────────────────────────────────────────────────
    if [ ${#processed_teams[@]} -gt 0 ]; then
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}[SUCCESS]${NC} CI toolchains provisioning completed for ${#processed_teams[@]} team(s)"
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
