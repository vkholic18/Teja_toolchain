#!/usr/bin/env python3

"""
CI/CD Onboarding YAML Validation Script
Validates a <service_name>-onboarding.yaml file for completeness and correctness.

Generic design — usable from both PR and Merge pipelines:
  - All pipeline-context values (branch names, changed files, labels) are
    captured once into an ExecutionContext dataclass at startup.
  - Validation functions accept ctx: ExecutionContext; none read os.environ
    directly, making them importable and testable without side-effects.
  - validate_file() is the programmatic entry point for callers that import
    this module (e.g. merge pipeline scripts).
  - main() is the CLI entry point used by the shell wrappers.
"""

import sys
import re
import os
import argparse
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Any, Optional

try:
    import yaml
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyyaml", "--quiet"])
    import yaml

# Locate commons_loader relative to this file so it works from any cwd.
# parents[5] = .../genctl-ci/onepipeline  → .../genctl-ci/onepipeline/utils
_UTILS_DIR = Path(__file__).resolve().parents[5] / "utils"
if str(_UTILS_DIR) not in sys.path:
    sys.path.insert(0, str(_UTILS_DIR))

try:
    from commons_loader import (
        load_commons,
        locate_commons,
        CommonsNotFoundError,
        CommonsParseError,
    )
except ImportError:
    # Graceful degradation: if commons_loader is unavailable (e.g. unit test
    # running outside the full repo tree) define stubs so the rest of the
    # module can still be imported.
    class CommonsNotFoundError(FileNotFoundError):  # type: ignore[no-redef]
        def __init__(self, search_dir=""):
            super().__init__(f"commons.yaml not found in '{search_dir}'")

    class CommonsParseError(ValueError):  # type: ignore[no-redef]
        pass

    def load_commons(ref_path):  # type: ignore[no-redef]
        raise CommonsNotFoundError(str(Path(ref_path).parent))

    def locate_commons(ref_path):  # type: ignore[no-redef]
        return None

# ---------------------------------------------------------------------------
# Color codes
# ---------------------------------------------------------------------------
RED    = '\033[0;31m'
GREEN  = '\033[0;32m'
YELLOW = '\033[1;33m'
BLUE   = '\033[0;34m'
NC     = '\033[0m'

# ---------------------------------------------------------------------------
# Validation state — kept as module-level so print_* helpers stay simple.
# Reset via _reset_counters() at the start of each validate_file() call so
# the module is safe to call multiple times in the same process.
# ---------------------------------------------------------------------------
errors   = 0
warnings = 0
debug_mode = False


def _reset_counters():
    global errors, warnings
    errors = 0
    warnings = 0


# ---------------------------------------------------------------------------
# Static configuration
# ---------------------------------------------------------------------------

VALID_TEAMS = [
    "Fabric", "DCMS", "SLAD", "Core Services", "COS", "File Block",
    "Network Underlay", "Network Services", "Observability", "PAG",
    "Pentest", "Seceng", "VPC",
]
_VALID_TEAMS_LOWER = {t.lower(): t for t in VALID_TEAMS}

VALID_CICD_PROFILES = ['minimal', 'ci_only', 'ci_cd', 'cd_only']

# Fields that belong exclusively in commons.yaml and must NOT appear in a
# service onboarding file.
COMMONS_ONLY_FIELDS = [
    'service_fid_dev',
    'service_fid_prod',
    'service_fid_dev_github_username',
    'service_fid_prod_github_username',
    'psirt_id',
    'ibm_cloud_account_dev',
    'ibm_cloud_account_prod',
    'secrets',
]

# Mandatory secret definitions — platform-managed, must not be altered.
MANDATORY_SECRETS_TEMPLATE = {
    "CI": [
        {"name": "gara-signing-credentials",   "description": "GARA code signing credentials",          "mandatory": True},
        {"name": "gara-signing-key",            "description": "GARA code signing key",                  "mandatory": True},
        {"name": "mend-org-token",              "description": "Mend SAST organization token",           "mandatory": True},
        {"name": "mend-user-key",               "description": "Mend SAST user key",                     "mandatory": True},
        {"name": "mend-product-token",          "description": "Mend SAST product token",                "mandatory": True},
    ],
    "CD": [
        {"name": "service-now-prod-iam-token",        "description": "ServiceNow production IAM token",       "mandatory": True},
        {"name": "service-now-test-iam-token",        "description": "ServiceNow test IAM token",             "mandatory": True},
        {"name": "gara-code-signing-certificate",     "description": "GARA code signing certificate",         "mandatory": True},
    ],
    "common": [
        {"name": "service-functional-id-dev-cloud-apikey",  "description": "Service functional ID dev IBM Cloud API key",                                  "mandatory": True},
        {"name": "service-functional-id-prod-cloud-apikey", "description": "Service functional ID production IBM Cloud API key",                            "mandatory": True},
        {"name": "service-functional-id-dev-ghe-pat",       "description": "Service functional ID dev GitHub Enterprise personal access token",             "mandatory": True},
        {"name": "service-functional-id-prod-ghe-pat",      "description": "Service functional ID production GitHub Enterprise personal access token",      "mandatory": True},
    ],
}

# Profile-aware mandatory secrets (what commons.yaml MUST contain per profile)
MANDATORY_SECRETS_TEMPLATE_BY_PROFILE = {
    'minimal':  {'common': MANDATORY_SECRETS_TEMPLATE['common']},
    'ci_only':  {'CI': MANDATORY_SECRETS_TEMPLATE['CI'], 'common': MANDATORY_SECRETS_TEMPLATE['common']},
    'ci_cd':    MANDATORY_SECRETS_TEMPLATE,
    'cd_only':  {'CD': MANDATORY_SECRETS_TEMPLATE['CD'], 'common': MANDATORY_SECRETS_TEMPLATE['common']},
}

# Mandatory file definitions — platform-managed.
MANDATORY_FILES_TEMPLATE = {
    "CI": [
        {"path": "hack/ci/build.sh",           "can_be_empty": False, "executable": True},
        {"path": "hack/ci/run-unit-tests.sh",  "can_be_empty": False, "executable": True},
        {"path": "hack/ci/build-meta.yaml",    "can_be_empty": False, "executable": False},
        {"path": "hack/ci/pipeline.yaml",      "can_be_empty": False, "executable": False},
    ],
    "CD": [
        {"path": "hack/cd/pre-reqs.sh",           "can_be_empty": False, "executable": True},
        {"path": "hack/cd/deploy.sh",             "can_be_empty": False, "executable": True},
        {"path": "hack/cd/acceptance-tests.sh",   "can_be_empty": False, "executable": True},
    ],
}

MANDATORY_FILES_TEMPLATE_BY_PROFILE = {
    'minimal':  {'CI': [{"path": "hack/ci/build.sh", "can_be_empty": False, "executable": True}]},
    'ci_only':  {'CI': MANDATORY_FILES_TEMPLATE['CI']},
    'ci_cd':    MANDATORY_FILES_TEMPLATE,
    'cd_only':  {'CD': MANDATORY_FILES_TEMPLATE['CD']},
}

# Human-readable validation scope per profile.
# commons.yaml fields are shown with a [commons] prefix.
_PROFILE_VALIDATION_SCOPE = {
    'minimal': {
        'validated': [
            'service_name', 'cicd_profile',
            'compliance_bucket', 'app_repo',
            'slack_member_ids', 'slack_channel',
            'mandatory_files.CI → hack/ci/build.sh only',
            '[commons] team_name',
            '[commons] service_fid_dev, service_fid_dev_github_username',
            '[commons] ibm_cloud_account_dev',
            '[commons] secrets.common (4 mandatory)',
        ],
        'skipped': [
            '[commons] service_fid_prod / service_fid_prod_github_username (no production deployment)',
            '[commons] psirt_id (no SAST scanning)',
            '[commons] secrets.CI / secrets.CD mandatory secrets (none required for minimal)',
            'inventory_repo (no compliance inventory)',
            'incident_repo (no CD pipeline)',
            'servicenow_crn (ci_cd / cd_only only)',
            'mandatory_files.CD (no CD pipeline)',
            'optional_files.mend (no SAST scanning)',
            'deployment_targets (no CI/CD environments)',
        ],
    },
    'ci_only': {
        'validated': [
            'service_name', 'cicd_profile',
            'compliance_bucket', 'app_repo',
            'incident_repo',
            'slack_member_ids', 'slack_channel',
            'mandatory_files.CI (all 4 files)',
            'optional_files.mend',
            '[commons] team_name',
            '[commons] service_fid_dev, service_fid_prod',
            '[commons] service_fid_dev_github_username, service_fid_prod_github_username',
            '[commons] psirt_id',
            '[commons] ibm_cloud_account_dev, ibm_cloud_account_prod',
            '[commons] secrets.CI (5 mandatory), secrets.common (4 mandatory)',
        ],
        'skipped': [
            'inventory_repo (no compliance inventory for ci_only)',
            'servicenow_crn (ci_cd / cd_only only)',
            '[commons] secrets.CD mandatory secrets (no CD pipeline)',
            'mandatory_files.CD (no CD pipeline)',
            'deployment_targets.CI (no CI test environments for libraries/SDKs)',
            'deployment_targets.CD (no CD pipeline)',
        ],
    },
    'ci_cd': {
        'validated': [
            'service_name', 'cicd_profile',
            'compliance_bucket', 'app_repo',
            'inventory_repo', 'incident_repo',
            'slack_member_ids', 'slack_channel',
            'servicenow_crn',
            'mandatory_files.CI (all 4 files)', 'mandatory_files.CD (all 3 files)',
            'optional_files.mend',
            'deployment_targets.CI', 'deployment_targets.CD',
            '[commons] team_name',
            '[commons] service_fid_dev, service_fid_prod',
            '[commons] service_fid_dev_github_username, service_fid_prod_github_username',
            '[commons] psirt_id',
            '[commons] ibm_cloud_account_dev, ibm_cloud_account_prod',
            '[commons] secrets.CI (5 mandatory), secrets.CD (3 mandatory), secrets.common (4 mandatory)',
        ],
        'skipped': [],
    },
    'cd_only': {
        'validated': [
            'service_name', 'cicd_profile',
            'compliance_bucket', 'app_repo',
            'inventory_repo', 'incident_repo',
            'slack_member_ids', 'slack_channel',
            'servicenow_crn',
            'mandatory_files.CD (all 3 files)',
            'deployment_targets.CD',
            '[commons] team_name',
            '[commons] service_fid_dev, service_fid_prod',
            '[commons] service_fid_dev_github_username, service_fid_prod_github_username',
            '[commons] ibm_cloud_account_dev, ibm_cloud_account_prod',
            '[commons] secrets.CD (3 mandatory), secrets.common (4 mandatory)',
        ],
        'skipped': [
            '[commons] psirt_id (no SAST scanning)',
            '[commons] secrets.CI mandatory secrets (no CI pipeline)',
            'mandatory_files.CI (no CI pipeline)',
            'optional_files.mend (no CI pipeline)',
            'deployment_targets.CI (no CI pipeline)',
        ],
    },
}

# Platform-managed reference template filenames — must never be changed by
# service teams.  commons.yaml is included so the same protection applies.
_REFERENCE_TEMPLATES = frozenset({
    'commons.yaml', 'commons.yml',
    'onboarding-minimal.yaml',  'onboarding-minimal.yml',
    'onboarding-ci_only.yaml',  'onboarding-ci_only.yml',
    'onboarding-ci_cd.yaml',    'onboarding-ci_cd.yml',
    'onboarding-cd_only.yaml',  'onboarding-cd_only.yml',
    # Legacy bare template
    'onboarding.yaml', 'onboarding.yml',
})


# ---------------------------------------------------------------------------
# ExecutionContext — captures all pipeline/environment values once at startup
# ---------------------------------------------------------------------------

@dataclass
class ExecutionContext:
    """Immutable snapshot of the execution environment.

    Populated from environment variables in build_context().  Pass this to
    any validation function that needs pipeline-specific information so that
    the functions themselves are environment-agnostic and unit-testable.
    """
    # The branch the PR targets (or the current branch in merge context)
    pr_basebranch: str = ""
    # The contributor's working branch (PR head branch)
    pr_branch: str = ""
    # Labels on the PR (comma/newline separated string)
    pr_labels: str = ""
    # Pipeline type: "pr" | "merge" | "" (unknown / local)
    pipeline_type: str = ""
    # Raw changed-files string (newline-separated, may include git status prefix)
    changed_files_raw: str = ""
    # Explicit path to commons.yaml (overrides auto-discovery when set)
    commons_path: str = ""
    # Debug mode flag
    debug: bool = False

    @property
    def changed_files(self) -> List[str]:
        """Parsed list of changed file entries."""
        return [l.strip() for l in self.changed_files_raw.splitlines() if l.strip()]

    @property
    def pr_label_set(self) -> set:
        return {lbl.strip() for lbl in re.split(r'[,\n]', self.pr_labels) if lbl.strip()}


def build_context(debug: bool = False, commons_path: str = "") -> ExecutionContext:
    """Build an ExecutionContext from the current environment variables."""
    raw_changed = ""
    for env_var in ('CHANGED_FILES', 'PR_CHANGED_FILES', 'GIT_CHANGED_FILES'):
        val = os.environ.get(env_var, '').strip()
        if val:
            raw_changed = val
            break

    return ExecutionContext(
        pr_basebranch   = os.environ.get('PR_BASEBRANCH', '').strip(),
        pr_branch       = os.environ.get('PR_BRANCH', '').strip(),
        pr_labels       = os.environ.get('PR_LABELS', '').strip(),
        pipeline_type   = os.environ.get('PIPELINE_TYPE', '').strip().lower(),
        changed_files_raw = raw_changed,
        commons_path    = commons_path,
        debug           = debug,
    )


# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

def print_error(msg: str):
    global errors
    print(f"{RED}[ERROR]{NC} {msg}")
    errors += 1

def print_warning(msg: str):
    global warnings
    print(f"{YELLOW}[WARNING]{NC} {msg}")
    warnings += 1

def print_success(msg: str):
    print(f"{GREEN}[SUCCESS]{NC} {msg}")

def print_info(msg: str):
    print(f"{BLUE}[INFO]{NC} {msg}")

def print_debug(msg: str):
    if debug_mode:
        print(f"{BLUE}[DEBUG]{NC} {msg}")


# ---------------------------------------------------------------------------
# YAML loading
# ---------------------------------------------------------------------------

def load_yaml(file_path: str) -> Dict:
    try:
        with open(file_path, 'r') as f:
            return yaml.safe_load(f) or {}
    except FileNotFoundError:
        print_error(f"YAML file not found: {file_path}")
        sys.exit(1)
    except yaml.YAMLError as e:
        print_error(f"Failed to parse YAML file: {e}")
        sys.exit(1)
    except Exception as e:
        print_error(f"Unexpected error loading YAML: {e}")
        sys.exit(1)


# ---------------------------------------------------------------------------
# commons.yaml loading — used early, errors are fatal
# ---------------------------------------------------------------------------

def load_commons_for_file(yaml_file: str, ctx: ExecutionContext) -> Optional[Dict]:
    """Load commons.yaml for the given service yaml file.

    Resolution order:
      1. ctx.commons_path (explicit override — useful from merge scripts)
      2. Auto-discovery: commons.yaml in the same directory as yaml_file

    Returns the parsed dict, or None after printing an error (which
    increments the error counter so validation will fail).
    """
    commons_file = ctx.commons_path or None

    if not commons_file:
        found = locate_commons(yaml_file)
        commons_file = str(found) if found else None

    if not commons_file:
        search_dir = str(Path(yaml_file).resolve().parent)
        print_error(
            f"commons.yaml not found in '{search_dir}'. "
            f"Every team branch must have a commons.yaml at its root. "
            f"See the reference template: commons.yaml in the uuc-service-cicd-onboarding repo."
        )
        return None

    try:
        data = load_commons(commons_file)
        print_success(f"commons.yaml loaded: {commons_file}")
        return data
    except CommonsParseError as exc:
        print_error(str(exc))
        return None


# ---------------------------------------------------------------------------
# Helper: cicd_profile from service data
# ---------------------------------------------------------------------------

def _get_cicd_profile(data: Dict) -> Optional[str]:
    return data.get('cicd_profile')


# ---------------------------------------------------------------------------
# Changed-files resolution (generic — works for PR and merge contexts)
# ---------------------------------------------------------------------------

def _get_changed_files(ctx: ExecutionContext) -> List[str]:
    """Return changed files list.  Tries env vars first, then git diff."""
    if ctx.changed_files:
        print_debug(f"Using changed files from environment: {ctx.changed_files}")
        return ctx.changed_files

    repo_root = Path(__file__).resolve().parents[7]
    diff_candidates: List[str] = []

    if ctx.pipeline_type == 'merge':
        # Merge context: compare HEAD~1..HEAD
        diff_candidates.append('HEAD~1')
    else:
        if ctx.pr_basebranch:
            diff_candidates.extend([
                f"origin/{ctx.pr_basebranch}",
                ctx.pr_basebranch,
            ])

    seen: set = set()
    for candidate in diff_candidates:
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        try:
            result = subprocess.run(
                ['git', 'diff', '--name-status', candidate, 'HEAD'],
                cwd=repo_root, capture_output=True, text=True, check=True,
            )
            files = [l.strip() for l in result.stdout.splitlines() if l.strip()]
            if files:
                print_debug(f"Changed files from git diff against '{candidate}': {files}")
                return files
        except Exception as exc:
            print_debug(f"git diff against '{candidate}' failed: {exc}")

    print_warning("Could not determine changed files — template protection check skipped")
    return []


# ---------------------------------------------------------------------------
# Team onboarding file discovery
# ---------------------------------------------------------------------------

def _find_team_onboarding_files(yaml_file: str, commons_data: Dict) -> List[Path]:
    """Return all *-onboarding.yaml files in the same directory as yaml_file."""
    yaml_path = Path(yaml_file).resolve()
    directory = yaml_path.parent
    return sorted(
        p for p in directory.glob('*-onboarding.yaml')
        if p.is_file()
    )


# ---------------------------------------------------------------------------
# Validation scope printer
# ---------------------------------------------------------------------------

def print_validation_scope(profile: str):
    scope = _PROFILE_VALIDATION_SCOPE.get(profile)
    if not scope:
        return
    print(f"{BLUE}{'─' * 55}{NC}")
    print(f"{BLUE}  Validation scope for cicd_profile: {profile}{NC}")
    print(f"{BLUE}{'─' * 55}{NC}")
    print(f"{GREEN}  Will validate:{NC}")
    for item in scope['validated']:
        print(f"    ✓  {item}")
    if scope['skipped']:
        print(f"{YELLOW}  Will skip (not required for '{profile}'):{NC}")
        for item in scope['skipped']:
            print(f"    –  {item}")
    print(f"{BLUE}{'─' * 55}{NC}")


# ===========================================================================
# COMMONS.YAML VALIDATIONS
# ===========================================================================

def validate_commons_team_name(commons_data: Dict):
    """Validate team_name in commons.yaml."""
    print_info("  [commons] Validating team_name...")
    team_name = commons_data.get('team_name')
    if not team_name:
        print_error("commons.yaml: team_name is missing or empty")
        return
    if team_name.lower() == "myteamname":
        print_error("commons.yaml: team_name is still the placeholder 'myteamname'")
        return
    canonical = _VALID_TEAMS_LOWER.get(team_name.lower())
    if canonical is None:
        print_error(f"commons.yaml: Invalid team_name '{team_name}'. Must be one of: {', '.join(VALID_TEAMS)}")
    else:
        if team_name != canonical:
            print_warning(f"commons.yaml: team_name '{team_name}' accepted but canonical form is '{canonical}'")
        print_success(f"commons.yaml: team_name is valid: {team_name}")


def validate_commons_functional_ids(commons_data: Dict, profile: str):
    """Validate FIDs in commons.yaml (profile-aware for prod FID)."""
    print_info("  [commons] Validating service functional IDs...")
    email_re = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

    fid_dev  = commons_data.get('service_fid_dev')
    fid_prod = commons_data.get('service_fid_prod')
    udev     = commons_data.get('service_fid_dev_github_username')
    uprod    = commons_data.get('service_fid_prod_github_username')

    # --- dev FID (always required) ---
    if not fid_dev:
        print_error("commons.yaml: service_fid_dev is missing")
    elif fid_dev in ('my_fid@ibm.com', 'myfid@ibm.com'):
        print_error(f"commons.yaml: service_fid_dev is still a placeholder: {fid_dev}")
    elif not re.match(email_re, fid_dev):
        print_error(f"commons.yaml: service_fid_dev has invalid email format: {fid_dev}")
    else:
        print_success(f"commons.yaml: service_fid_dev is valid: {fid_dev}")

    if not udev:
        print_error("commons.yaml: service_fid_dev_github_username is missing")
    elif udev in ('my_fid_github_username',):
        print_error(f"commons.yaml: service_fid_dev_github_username is still a placeholder: {udev}")
    else:
        print_success(f"commons.yaml: service_fid_dev_github_username is valid: {udev}")

    # --- prod FID (not required for minimal) ---
    if profile == 'minimal':
        print_info("  [commons] service_fid_prod not required for profile 'minimal' — skipping")
    else:
        if not fid_prod:
            print_error("commons.yaml: service_fid_prod is missing")
        elif fid_prod in ('my_fid_prod@ibm.com', 'myfid_prod@ibm.com', 'my_fid@ibm.com'):
            print_error(f"commons.yaml: service_fid_prod is still a placeholder: {fid_prod}")
        elif not re.match(email_re, fid_prod):
            print_error(f"commons.yaml: service_fid_prod has invalid email format: {fid_prod}")
        else:
            print_success(f"commons.yaml: service_fid_prod is valid: {fid_prod}")

        if not uprod:
            print_error("commons.yaml: service_fid_prod_github_username is missing")
        elif uprod in ('my_fid_prod_github_username',):
            print_error(f"commons.yaml: service_fid_prod_github_username is still a placeholder: {uprod}")
        else:
            print_success(f"commons.yaml: service_fid_prod_github_username is valid: {uprod}")

        if fid_dev and fid_prod and fid_dev == fid_prod:
            print_warning("commons.yaml: service_fid_dev and service_fid_prod are the same — consider separate FIDs")


def validate_commons_psirt_id(commons_data: Dict, profile: str):
    """Validate psirt_id in commons.yaml (skipped for minimal and cd_only)."""
    print_info("  [commons] Validating psirt_id...")
    if profile in ('minimal', 'cd_only'):
        print_info(f"  [commons] psirt_id not required for profile '{profile}' — skipping")
        return
    psirt_id = commons_data.get('psirt_id')
    if not psirt_id:
        print_error("commons.yaml: psirt_id is missing")
        return
    if re.match(r'^PSIRT_PRD0+$', str(psirt_id)):
        print_error(f"commons.yaml: psirt_id contains only zeros (placeholder): {psirt_id}")
        return
    if not re.match(r'^PSIRT_PRD\d{7}$', str(psirt_id)):
        print_error(f"commons.yaml: psirt_id format invalid (expected PSIRT_PRDxxxxxxx, 7 digits): {psirt_id}")
    else:
        print_success(f"commons.yaml: psirt_id is valid: {psirt_id}")


def validate_commons_ibm_cloud_accounts(commons_data: Dict):
    """Validate IBM Cloud accounts in commons.yaml (optional)."""
    print_info("  [commons] Validating IBM Cloud accounts (optional)...")
    dev  = commons_data.get('ibm_cloud_account_dev')
    prod = commons_data.get('ibm_cloud_account_prod')
    if dev and dev != 'my_dev_account':
        print_success(f"commons.yaml: ibm_cloud_account_dev: {dev}")
    else:
        print_warning("commons.yaml: ibm_cloud_account_dev not provided (optional)")
    if prod and prod != 'my_prod_account':
        print_success(f"commons.yaml: ibm_cloud_account_prod: {prod}")
    else:
        print_warning("commons.yaml: ibm_cloud_account_prod not provided (optional)")


def validate_commons_secrets(commons_data: Dict, profile: str):
    """Validate the secrets section in commons.yaml (profile-aware)."""
    print_info("  [commons] Validating secrets configuration...")
    effective_template = MANDATORY_SECRETS_TEMPLATE_BY_PROFILE.get(profile, MANDATORY_SECRETS_TEMPLATE)
    secret_groups = commons_data.get('secrets', [])

    if not secret_groups:
        print_error("commons.yaml: 'secrets' section is missing or empty")
        return

    team_name = commons_data.get('team_name', '')
    team_slug = team_name.lower().replace(' ', '-') if team_name else ''
    secret_group_prefix = f"sg-uuc-{team_slug}-" if team_slug else ""

    for group in secret_groups:
        group_name = group.get('name')
        items      = group.get('items', [])
        print_info(f"  [commons]   Checking secret group: {group_name} ({len(items)} items)")

        template_secrets = effective_template.get(group_name, [])

        # If this group has no entries in the profile-effective template but IS
        # a known platform-managed group (e.g. 'CD' when profile='ci_only'),
        # fall back to the full MANDATORY_SECRETS_TEMPLATE so that per-item
        # matching still recognises those secrets as platform-managed rather
        # than treating them as custom secrets and flagging mandatory=true.
        # The count check below is intentionally skipped for out-of-scope groups.
        _platform_secrets_for_group = template_secrets or MANDATORY_SECRETS_TEMPLATE.get(group_name, [])
        _group_in_scope = bool(template_secrets)  # True only when this group is required for the profile

        if _group_in_scope:
            mandatory_count = sum(1 for it in items if it.get('mandatory') is True)
            expected        = len(template_secrets)
            if mandatory_count < expected:
                print_error(
                    f"commons.yaml: secret group '{group_name}' has {mandatory_count} mandatory "
                    f"secrets but expected {expected} — platform-managed secrets may have been removed"
                )
            elif mandatory_count > expected:
                print_error(
                    f"commons.yaml: secret group '{group_name}' has {mandatory_count} mandatory "
                    f"secrets but expected {expected} — custom secrets must have mandatory=false"
                )
            else:
                print_success(f"commons.yaml: secret group '{group_name}' has correct mandatory count: {mandatory_count}")
        else:
            # If this group is a known platform-managed group (present in the
            # full MANDATORY_SECRETS_TEMPLATE), it simply isn't required for
            # this profile (e.g. the 'CD' group when profile='ci_only').
            # commons.yaml is shared across services, so another service on the
            # same branch may need a different profile. Do NOT flag these as
            # rogue — they are valid platform-managed secrets for a different
            # profile scope.
            if group_name in MANDATORY_SECRETS_TEMPLATE:
                pass  # known platform group, not required for this profile — skip
            else:
                rogue = [it.get('name') for it in items if it.get('mandatory') is True]
                if rogue:
                    print_error(
                        f"commons.yaml: secret group '{group_name}' has no platform-mandatory secrets "
                        f"for profile '{profile}', but found mandatory=true on: {rogue}"
                    )

        found_mandatory: set = set()
        for item in items:
            secret_name      = item.get('name')
            secret_desc      = item.get('description')
            secret_mandatory = item.get('mandatory')

            is_mandatory  = False
            matched_tmpl  = None
            for tmpl in _platform_secrets_for_group:
                tname = tmpl['name']
                if 'mend' in tname:
                    if tname in str(secret_name):
                        is_mandatory = True; matched_tmpl = tmpl; found_mandatory.add(tname); break
                else:
                    if tname == secret_name:
                        is_mandatory = True; matched_tmpl = tmpl; found_mandatory.add(tname); break

            if is_mandatory and matched_tmpl:
                if secret_mandatory != matched_tmpl['mandatory']:
                    print_error(
                        f"commons.yaml: mandatory secret '{secret_name}' has mandatory={secret_mandatory} "
                        f"instead of {matched_tmpl['mandatory']} — DO NOT MODIFY"
                    )
                tmpl_desc = matched_tmpl['description']
                if 'Mend SAST' in tmpl_desc:
                    if 'Mend SAST' not in str(secret_desc):
                        print_error(f"commons.yaml: mandatory secret '{secret_name}' description was modified")
                elif tmpl_desc not in str(secret_desc) and 'PSIRT_PRD' not in str(secret_desc):
                    print_error(f"commons.yaml: mandatory secret '{secret_name}' description was modified. Expected: '{tmpl_desc}'")
            else:
                # Custom secret
                if '<your_secret_name>' in str(secret_name) or '<your_secret_description>' in str(secret_desc):
                    print_warning(f"commons.yaml: custom secret contains placeholder values — replace before onboarding")
                if secret_mandatory is True:
                    print_error(f"commons.yaml: custom secret '{secret_name}' must not have mandatory=true")
                if secret_group_prefix and isinstance(secret_name, str) and secret_name.startswith(secret_group_prefix):
                    print_error(
                        f"commons.yaml: custom secret '{secret_name}' must not include the secret group prefix "
                        f"'{secret_group_prefix}' — the prefix is added automatically during provisioning"
                    )
                # Validate unique_per_cluster field if present
                upc = item.get('unique_per_cluster')
                if upc is not None and not isinstance(upc, bool):
                    print_error(
                        f"commons.yaml: custom secret '{secret_name}' has invalid unique_per_cluster value "
                        f"'{upc}' — must be true or false (boolean)"
                    )

            if not secret_name:
                print_error(f"commons.yaml: a secret in group '{group_name}' is missing 'name'")
            if not secret_desc:
                print_error(f"commons.yaml: secret '{secret_name}' is missing 'description'")
            if secret_mandatory is None:
                print_error(f"commons.yaml: secret '{secret_name}' is missing 'mandatory' field")

        if template_secrets:
            missing = {t['name'] for t in template_secrets} - found_mandatory
            for mname in missing:
                for t in template_secrets:
                    if t['name'] == mname:
                        print_error(
                            f"commons.yaml: mandatory secret '{mname}' is missing from group "
                            f"'{group_name}' — DO NOT REMOVE platform-managed secrets"
                        )
                        break

    # ── Duplicate custom secret name check (across all groups) ────────────────
    # Since ALL secrets are team-level in commons.yaml (shared across every
    # service in the team), a duplicate name in any group would provision the
    # same secret twice and cause a Terraform error.  Fail early here so the
    # team can fix it before merge.
    print_info("  [commons] Checking for duplicate custom secret names across all groups...")
    seen_custom_names: Dict[str, str] = {}   # name → "group/name" first location
    duplicate_found = False
    for group in secret_groups:
        group_name = group.get('name', '')
        for item in group.get('items', []):
            if item.get('mandatory', False):
                continue  # platform-managed secrets are intentionally identical across branches
            sname = item.get('name')
            if not sname:
                continue
            location = f"group '{group_name}'"
            if sname in seen_custom_names:
                print_error(
                    f"commons.yaml: duplicate custom secret name '{sname}' found in {location} — "
                    f"already declared in {seen_custom_names[sname]}. "
                    f"Each secret name must be unique across the entire commons.yaml. "
                    f"Remove the duplicate entry before merging."
                )
                duplicate_found = True
            else:
                seen_custom_names[sname] = location
    if not duplicate_found:
        print_success("commons.yaml: no duplicate custom secret names found")

    print_success("commons.yaml: secrets validation completed")


def validate_commons_yaml(yaml_file: str, commons_data: Dict, profile: str):
    """Run all commons.yaml validations.  Called once per service file validated."""
    print_info("Validating commons.yaml...")
    print()
    validate_commons_team_name(commons_data)
    print()
    validate_commons_functional_ids(commons_data, profile)
    print()
    validate_commons_psirt_id(commons_data, profile)
    print()
    validate_commons_ibm_cloud_accounts(commons_data)
    print()
    validate_commons_secrets(commons_data, profile)


# ===========================================================================
# SERVICE ONBOARDING FILE VALIDATIONS
# ===========================================================================

def validate_no_commons_fields_in_service(data: Dict):
    """Error if any commons-only field is still present in the service yaml.

    This enforces the rule that team-level data (FIDs, psirt_id, IBM Cloud
    accounts, and ALL secrets) must only live in commons.yaml.  Keeping
    secrets in a service onboarding file is explicitly rejected because:
      - secrets are provisioned once per team secret-group, not per service
      - updating a secret in one service file would silently diverge from
        other service files on the same branch
    """
    print_info("Validating that commons-only fields are not present in service file...")
    found_any = False
    for field_name in COMMONS_ONLY_FIELDS:
        if field_name in data:
            if field_name == 'secrets':
                print_error(
                    f"Field 'secrets' must NOT be present in a service onboarding file. "
                    f"Secrets are provisioned once per team and must be maintained exclusively "
                    f"in commons.yaml. Move the entire 'secrets' section to commons.yaml."
                )
            else:
                print_error(
                    f"Field '{field_name}' must not be present in the service onboarding file — "
                    f"move it to commons.yaml"
                )
            found_any = True
    if not found_any:
        print_success("No commons-only fields found in service file — clean separation confirmed")


def validate_commons_pr_invariants(
    search_dir: str,
    ctx: ExecutionContext,
) -> int:
    """Enforce PR-level invariants around commons.yaml.  Called ONCE per PR
    (before iterating over individual service onboarding files), not once per
    service file.

    Three rules are checked:

    1. commons.yaml must already exist on the target branch when a PR adds a
       new service onboarding file.  A team cannot onboard their first service
       without first creating commons.yaml.

    2. A PR must not delete commons.yaml.  Deleting the file would break all
       subsequent merge-pipeline runs for that team branch.

    3. The 'secrets' section must only live in commons.yaml.  (Belt-and-
       suspenders check at the PR level in addition to the per-file check.)
       Any service onboarding file that still contains a 'secrets' key is
       rejected here.

    Args:
        search_dir: The directory (branch workspace root) to search in.
        ctx:        ExecutionContext with PR/pipeline values.

    Returns:
        Number of errors found (0 = pass, >0 = fail).
    """
    local_errors = 0

    print_info("Validating commons.yaml PR-level invariants...")

    # ── Resolve commons.yaml presence ────────────────────────────────────────
    commons_path = locate_commons(search_dir)
    commons_exists = commons_path is not None

    # ── Rule 2: commons.yaml must not be deleted in this PR ──────────────────
    changed = _get_changed_files(ctx)
    deleted_names = {
        Path(line.split('\t', 1)[-1]).name
        for line in changed if line.startswith('D\t')
    }
    if 'commons.yaml' in deleted_names or 'commons.yml' in deleted_names:
        deleted_file = 'commons.yaml' if 'commons.yaml' in deleted_names else 'commons.yml'
        print_error(
            f"This PR deletes '{deleted_file}'. commons.yaml must never be removed — "
            f"it is required for all team branch operations (secret provisioning, "
            f"toolchain setup, and onboarding validation). "
            f"If you intended to restructure the file, rename it instead."
        )
        local_errors += 1

    # ── Determine new onboarding files added in this PR ──────────────────────
    new_onboarding_files = [
        Path(line.split('\t', 1)[-1])
        for line in changed
        if line.startswith('A\t') and line.split('\t', 1)[-1].endswith(('-onboarding.yaml', '-onboarding.yml'))
        and not line.split('\t', 1)[-1].endswith(('-timed-onboarding.yaml', '-timed-onboarding.yml'))
    ]
    # Filter out platform reference templates
    new_onboarding_files = [
        p for p in new_onboarding_files
        if p.name not in _REFERENCE_TEMPLATES
    ]

    # ── Rule 1: commons.yaml must pre-exist when adding a service file ────────
    if new_onboarding_files and not commons_exists:
        print_error(
            f"This PR adds {len(new_onboarding_files)} new service onboarding file(s) but "
            f"commons.yaml does not exist in '{search_dir}'. "
            f"commons.yaml must be created BEFORE or IN THE SAME PR as the first service "
            f"onboarding file. "
            f"See the reference template in the uuc-service-cicd-onboarding repository."
        )
        for p in new_onboarding_files:
            print_info(f"  New file detected: {p.name}")
        local_errors += 1
    elif new_onboarding_files and commons_exists:
        print_success(
            f"commons.yaml present — {len(new_onboarding_files)} new service file(s) can proceed"
        )

    # ── Rule 3: no 'secrets' key in any service onboarding file in this PR ───
    # Walk all changed/added service onboarding files and check for secrets key.
    changed_service_files = [
        Path(line.split('\t', 1)[-1])
        for line in changed
        if not line.startswith('D\t')          # skip deleted files
        and line.split('\t', 1)[-1].endswith(('-onboarding.yaml', '-onboarding.yml'))
        and not line.split('\t', 1)[-1].endswith(('-timed-onboarding.yaml', '-timed-onboarding.yml'))
    ]
    changed_service_files = [
        p for p in changed_service_files
        if p.name not in _REFERENCE_TEMPLATES
    ]

    for svc_path in changed_service_files:
        abs_path = (Path(search_dir) / svc_path).resolve()
        if not abs_path.is_file():
            # Try as an already-absolute path (git outputs repo-relative paths)
            abs_path = svc_path.resolve()
        if not abs_path.is_file():
            continue
        try:
            with open(abs_path) as fh:
                svc_data = yaml.safe_load(fh) or {}
            if isinstance(svc_data, dict) and 'secrets' in svc_data:
                print_error(
                    f"'{abs_path.name}' contains a 'secrets' section. "
                    f"Secrets must ONLY be defined in commons.yaml — they are provisioned "
                    f"once per team secret-group, not per service. "
                    f"Remove the 'secrets' section from '{abs_path.name}' and add any "
                    f"custom secrets to the appropriate group in commons.yaml instead."
                )
                local_errors += 1
        except Exception as exc:
            print_debug(f"Could not pre-check '{abs_path}' for secrets key: {exc}")

    if local_errors == 0:
        print_success("commons.yaml PR-level invariants: all checks passed")

    global errors
    errors += local_errors
    return local_errors


def validate_cicd_profile(data: Dict):
    print_info("Validating cicd_profile...")
    profile = data.get('cicd_profile')
    if not profile:
        print_error(f"cicd_profile is required. Allowed values: {' | '.join(VALID_CICD_PROFILES)}")
        return
    if profile not in VALID_CICD_PROFILES:
        print_error(f"cicd_profile '{profile}' is invalid. Allowed values: {' | '.join(VALID_CICD_PROFILES)}")
    else:
        print_success(f"cicd_profile is valid: {profile}")
        print()
        print_validation_scope(profile)


# ---------------------------------------------------------------------------
# CD profiles — any profile that provisions a CD toolchain
# ---------------------------------------------------------------------------
_CD_PROFILES = frozenset({'ci_cd', 'cd_only'})


def validate_cicd_profile_change(yaml_file: str, data: Dict, ctx: ExecutionContext):
    """Warn when a PR downgrades cicd_profile away from a CD-bearing value.

    A downgrade from 'ci_cd' / 'cd_only' → 'ci_only' / 'minimal' means the
    service no longer wants a CD toolchain.  The merge pipeline does NOT
    automatically remove the existing CD toolchain block from the toolchains
    TF repository — that requires an explicit offboard (deleting this file or
    manually removing the block).

    This check is skipped when:
      - The file is new in this PR (no HEAD~1 version to compare against).
      - HEAD~1 is unavailable (shallow clone, initial commit, etc.).
      - The pipeline context does not provide enough git information.

    An upgrade (ci_only → ci_cd) is intentional and needs no warning.
    A same-value edit produces no output.
    """
    print_info("Checking cicd_profile for CD toolchain impact...")

    new_profile = data.get('cicd_profile', '')
    if not new_profile:
        # Already flagged as missing by validate_cicd_profile — skip.
        return

    # ── Determine whether this file is newly added in this PR ────────────────
    changed = _get_changed_files(ctx)
    yaml_name = Path(yaml_file).name
    is_new_file = any(
        line.startswith('A\t') and Path(line.split('\t', 1)[-1]).name == yaml_name
        for line in changed
    )
    if is_new_file:
        print_debug(f"'{yaml_name}' is a new file — no previous cicd_profile to compare")
        return

    # ── Resolve the repo root to run git show against ─────────────────────────
    repo_root = Path(__file__).resolve().parents[7]

    # Try to find a valid base ref in order of preference:
    #   1. origin/<pr_basebranch>  (most accurate for PR context)
    #   2. HEAD~1                  (merge context / local)
    base_candidates: List[str] = []
    if ctx.pr_basebranch:
        base_candidates.append(f"origin/{ctx.pr_basebranch}")
    base_candidates.append("HEAD~1")

    old_content: Optional[str] = None
    # Path relative to repo root — git show needs a repo-relative path.
    try:
        rel_path = Path(yaml_file).resolve().relative_to(repo_root.resolve())
    except ValueError:
        # yaml_file is outside the detected repo root — fall back to filename only.
        rel_path = Path(yaml_name)

    for ref in base_candidates:
        try:
            result = subprocess.run(
                ['git', 'show', f'{ref}:{rel_path}'],
                cwd=repo_root, capture_output=True, text=True,
            )
            if result.returncode == 0 and result.stdout.strip():
                old_content = result.stdout
                print_debug(f"Read previous '{yaml_name}' from '{ref}'")
                break
        except Exception as exc:
            print_debug(f"git show '{ref}:{rel_path}' failed: {exc}")

    if old_content is None:
        print_debug(f"Could not read previous version of '{yaml_name}' — skipping profile-change check")
        return

    # ── Parse the old profile ─────────────────────────────────────────────────
    try:
        old_data = yaml.safe_load(old_content) or {}
    except yaml.YAMLError as exc:
        print_debug(f"Could not parse previous '{yaml_name}': {exc}")
        return

    old_profile = old_data.get('cicd_profile', '')
    if not old_profile or old_profile == new_profile:
        # No change.
        return

    old_has_cd = old_profile in _CD_PROFILES
    new_has_cd = new_profile in _CD_PROFILES

    if old_has_cd and not new_has_cd:
        # ── Downgrade: CD toolchain becomes orphaned ──────────────────────────
        print_warning(
            f"cicd_profile changed from '{old_profile}' → '{new_profile}'. "
            f"The previous profile provisioned a CD toolchain. Changing to "
            f"'{new_profile}' means the merge pipeline will NO LONGER manage "
            f"that CD toolchain — but the existing block in the toolchains TF "
            f"repository will NOT be removed automatically."
        )
        print_warning(
            f"Required manual action: to decommission the CD toolchain for "
            f"'{data.get('service_name', yaml_name)}', you must either:\n"
            f"  1. Delete this onboarding file (triggers automatic offboarding), or\n"
            f"  2. Manually remove the '{data.get('service_name', '')}' block from "
            f"the toolchains TF repo."
        )
    elif not old_has_cd and new_has_cd:
        # ── Upgrade: new CD toolchain will be provisioned ─────────────────────
        print_info(
            f"cicd_profile upgraded from '{old_profile}' → '{new_profile}'. "
            f"A new CD toolchain will be provisioned on merge."
        )
    else:
        # Both profiles are in the same class (e.g. ci_only → minimal).
        print_info(
            f"cicd_profile changed from '{old_profile}' → '{new_profile}' "
            f"(no CD toolchain impact)."
        )


def validate_service_name(data: Dict):
    print_info("Validating service name...")
    service_name = data.get('service_name')
    if not service_name:
        print_error("service_name is missing or empty")
        return
    if service_name == "myservicename":
        print_error("service_name is still the placeholder 'myservicename'")
        return
    placeholder_patterns = ['myservice', 'service_name', 'servicename', 'test', 'example']
    if any(p in service_name.lower() for p in placeholder_patterns):
        print_warning(f"service_name '{service_name}' may contain a placeholder value")
    if not re.match(r'^[a-zA-Z0-9_-]+$', service_name):
        print_error(f"service_name '{service_name}' contains invalid characters (alphanumeric, hyphens, underscores only)")
    else:
        print_success(f"service_name is valid: {service_name}")


def validate_inventory_repo(data: Dict, commons_data: Optional[Dict] = None):
    print_info("Validating inventory repository...")
    profile = _get_cicd_profile(data)
    if profile in ('minimal', 'ci_only'):
        print_info(f"cicd_profile is '{profile}' — inventory_repo is not required, skipping")
        return
    inventory_repo = data.get('inventory_repo') or {}
    repo   = inventory_repo.get('repo')
    branch = inventory_repo.get('branch')
    create = inventory_repo.get('create', False)

    create_requested = str(create).lower() == 'true'
    print_info(
        f"inventory_repo.create: {create} — "
        f"{'pipeline will fork compliance-inventory template' if create_requested else 'using existing repository'}"
    )

    placeholders = ['myinventoryrepo', 'myteamname', 'myrepo', 'myorg']
    has_placeholder = repo and any(p in str(repo).lower() for p in placeholders)

    if not repo:
        print_error("inventory_repo.repo is missing")
    elif has_placeholder:
        print_error(f"inventory_repo.repo contains a placeholder value: {repo}")
    else:
        print_success(f"inventory_repo.repo: {repo}")
        url_parts = (repo.rstrip('/').removesuffix('.git')).split('/')
        if len(url_parts) >= 2:
            inventory_org  = url_parts[-2]
            inventory_name = url_parts[-1]
            print_success(f"  Org: {inventory_org}  Repo: {inventory_name}")
            # team_name lives in commons.yaml — use commons_data when available,
            # fall back to service data for backward compatibility.
            team_name  = (commons_data or {}).get('team_name', '') or data.get('team_name', '')
            app_repos  = data.get('app_repo', [])
            if team_name and team_name != 'myteamname' and app_repos:
                app_repo_url = app_repos[0].get('repo', '')
                if app_repo_url and 'myorg' not in app_repo_url and 'myrepo' not in app_repo_url:
                    app_repo_name  = (app_repo_url.rstrip('/').removesuffix('.git')).split('/')[-1]
                    formatted_team = team_name.lower().replace(' ', '-')
                    expected       = f"uuc-{formatted_team}-{app_repo_name}-compliance-inventory"
                    if inventory_name not in (expected, f"{expected}.git"):
                        print_error(f"inventory_repo name format incorrect. Expected: .../{expected}, Got: .../{inventory_name}")
                    else:
                        print_success(f"inventory_repo naming format correct: {expected}")

    if not branch:
        print_error("inventory_repo.branch is missing")
    else:
        print_success(f"inventory_repo.branch: {branch}")


def validate_incident_repo(data: Dict):
    print_info("Validating incident repository...")
    profile = _get_cicd_profile(data)
    if profile == 'minimal':
        print_info("cicd_profile is 'minimal' — incident_repo is not required, skipping")
        return
    incident_repo = data.get('incident_repo') or {}
    repo   = incident_repo.get('repo')
    branch = incident_repo.get('branch')
    create = incident_repo.get('create', False)

    create_requested = str(create).lower() == 'true'
    print_info(
        f"incident_repo.create: {create} — "
        f"{'pipeline will create a blank repo with README' if create_requested else 'using existing repository'}"
    )

    placeholders = ['myincidentrepo', 'myorg']
    has_placeholder = repo and any(p in str(repo).lower() for p in placeholders)

    if not repo:
        print_error("incident_repo.repo is missing")
    elif has_placeholder:
        print_error(f"incident_repo.repo contains a placeholder value: {repo}")
    else:
        print_success(f"incident_repo.repo: {repo}")
        url_parts = (repo.rstrip('/').removesuffix('.git')).split('/')
        if len(url_parts) >= 2:
            print_success(f"  Org: {url_parts[-2]}  Repo: {url_parts[-1]}")

    if not branch:
        print_error("incident_repo.branch is missing")
    else:
        print_success(f"incident_repo.branch: {branch}")


def validate_compliance_bucket(data: Dict):
    print_info("Validating compliance bucket configuration...")
    compliance_bucket = data.get('compliance_bucket') or {}
    use_existing = compliance_bucket.get('use_existing', False)
    endpoint     = compliance_bucket.get('endpoint')
    bucket_name  = compliance_bucket.get('name')

    if use_existing:
        print_info("Using existing compliance bucket — validating custom endpoint and bucket name...")
        if not endpoint:
            print_error("compliance_bucket.endpoint is required when use_existing is true")
        elif 's3.eu-gb.cloud-object-storage.appdomain.cloud' in str(endpoint):
            print_error("compliance_bucket.endpoint is still the default placeholder — provide your custom endpoint")
        else:
            print_success(f"compliance_bucket.endpoint: {endpoint}")

        if not bucket_name:
            print_error("compliance_bucket.name is required when use_existing is true")
        elif bucket_name == 'my_bucket':
            print_error("compliance_bucket.name is still the placeholder 'my_bucket'")
        else:
            print_success(f"compliance_bucket.name: {bucket_name}")

        print_warning("Ensure 'onepipelineci@ibm.com' has write access to your custom compliance bucket")
    else:
        print_success("Using CICD-managed compliance bucket (auto-named uuc-<team-slug>-ci-storage)")


def validate_app_repo(data: Dict):
    print_info("Validating application repositories...")
    app_repos = data.get('app_repo', [])
    if not app_repos:
        print_error("No application repositories defined")
        return
    for i, app_repo in enumerate(app_repos, 1):
        repo   = app_repo.get('repo')
        branch = app_repo.get('branch')
        if not repo or 'myorg' in str(repo) or 'myrepo' in str(repo):
            print_error(f"App repository #{i} is missing or contains placeholder (myorg/myrepo)")
        else:
            print_success(f"App repository #{i}: {repo}")
        if not branch:
            print_error(f"App repository #{i} branch is missing")
        else:
            print_success(f"App repository #{i} branch: {branch}")


def validate_servicenow_crn(data: Dict):
    print_info("Validating ServiceNow CRN...")
    profile = _get_cicd_profile(data)
    if profile in ('minimal', 'ci_only'):
        print_info(f"cicd_profile is '{profile}' — servicenow_crn is not required, skipping")
        return
    # For ci_cd and cd_only profiles servicenow_crn is mandatory.
    crn = data.get('servicenow_crn')
    if not crn or not str(crn).strip():
        print_error(f"servicenow_crn is mandatory for cicd_profile='{profile}' but is missing")
        return
    if str(crn).strip() in ('<your_servicenow_crn>', '<your_servicenow_crn_mask>'):
        print_error(f"servicenow_crn is still the placeholder value — replace with your actual CRN (mandatory for cicd_profile='{profile}')")
        return
    print_success(f"servicenow_crn is provided: {crn}")


def validate_slack_config(data: Dict):
    print_info("Validating Slack configuration...")
    slack_member_ids = data.get('slack_member_ids', [])
    if not slack_member_ids:
        print_error("slack_member_ids are mandatory but not provided")
        return
    example_ids = {'U01234ABCDE', 'U56789FGHIJ'}
    if any(mid in example_ids for mid in slack_member_ids):
        print_error("slack_member_ids contain example placeholder values — replace with real Slack member IDs")
    else:
        print_success(f"slack_member_ids provided ({len(slack_member_ids)} members)")

    slack_channel = data.get('slack_channel')
    if slack_channel:
        if 'my-team-alerts' in str(slack_channel) or 'your-channel' in str(slack_channel):
            print_error(f"slack_channel contains placeholder value: {slack_channel}")
        else:
            print_success(f"slack_channel: {slack_channel}")
    else:
        print_info("slack_channel not provided (optional) — will use default channel")


def validate_mandatory_files(data: Dict):
    """Validate mandatory files configuration (profile-aware)."""
    print_info("Validating mandatory files configuration...")
    profile  = _get_cicd_profile(data)
    effective = MANDATORY_FILES_TEMPLATE_BY_PROFILE.get(profile, MANDATORY_FILES_TEMPLATE)

    file_groups = data.get('mandatory_files', [])
    if not file_groups:
        print_error("No mandatory file groups defined")
        return

    for group in file_groups:
        group_name = group.get('name')
        repo       = group.get('repo')
        branch     = group.get('branch')
        files      = group.get('files', [])

        if profile in ('minimal', 'ci_only') and group_name == 'CD':
            print_info(f"cicd_profile is '{profile}' — mandatory_files group 'CD' not required, skipping")
            continue
        if profile == 'cd_only' and group_name == 'CI':
            print_info("cicd_profile is 'cd_only' — mandatory_files group 'CI' not required, skipping")
            continue

        print_info(f"Checking mandatory file group: {group_name}")

        if not repo or 'myrepo' in str(repo) or 'myorg' in str(repo):
            print_error(f"mandatory_files group '{group_name}' has invalid or placeholder repo")
        else:
            print_success(f"mandatory_files group '{group_name}' repo: {repo}")

        if not branch:
            print_error(f"mandatory_files group '{group_name}' is missing branch")
        else:
            print_success(f"mandatory_files group '{group_name}' branch: {branch}")

        template_files = effective.get(group_name, [])

        if not files:
            print_error(f"mandatory_files group '{group_name}' has no files defined")
        else:
            required_paths = {tf['path'] for tf in template_files}
            file_paths     = {f.get('path') for f in files if f.get('path')}

            for missing_path in required_paths - file_paths:
                print_error(f"Mandatory file '{missing_path}' is missing from group '{group_name}' (DO NOT REMOVE)")

            if profile == 'minimal' and group_name == 'CI':
                print_info("cicd_profile is 'minimal' — only 'hack/ci/build.sh' enforced; extra files are allowed")
            else:
                if len(template_files) > 0 and len(files) != len(template_files):
                    print_error(
                        f"mandatory_files group '{group_name}' has {len(files)} files but expected "
                        f"{len(template_files)} (DO NOT MODIFY file list)"
                    )
                else:
                    print_success(f"mandatory_files group '{group_name}' has {len(files)} file(s) defined")

            full_template_map = {tf['path']: tf for tf in MANDATORY_FILES_TEMPLATE.get(group_name, [])}

            for file_item in files:
                file_path    = file_item.get('path')
                can_be_empty = file_item.get('can_be_empty')
                executable   = file_item.get('executable')

                if not file_path:
                    print_error(f"File in group '{group_name}' is missing path")
                    continue

                if file_path in full_template_map:
                    tmpl_file = full_template_map[file_path]
                    if executable != tmpl_file['executable']:
                        print_error(
                            f"File '{file_path}' in group '{group_name}' has executable={executable} "
                            f"but expected {tmpl_file['executable']} (DO NOT MODIFY)"
                        )
                    if can_be_empty != tmpl_file['can_be_empty']:
                        if not tmpl_file['can_be_empty'] and can_be_empty:
                            print_warning(f"File '{file_path}' in group '{group_name}' changes can_be_empty from default false to true")
                        else:
                            print_warning(f"File '{file_path}' in group '{group_name}' has can_be_empty={can_be_empty} (template default: {tmpl_file['can_be_empty']})")
                else:
                    if len(full_template_map) > 0:
                        print_error(f"File '{file_path}' in group '{group_name}' is not a platform-managed file (DO NOT ADD custom files to mandatory_files)")

                if can_be_empty is None:
                    print_error(f"File '{file_path}' in group '{group_name}' is missing can_be_empty property")
                if executable is None:
                    print_error(f"File '{file_path}' in group '{group_name}' is missing executable property")


def validate_optional_files(data: Dict):
    """Validate optional files configuration."""
    print_info("Validating optional files configuration...")
    profile     = _get_cicd_profile(data)
    file_groups = data.get('optional_files', [])

    if not file_groups:
        print_info("No optional file groups defined (optional)")
        return

    for group in file_groups:
        group_name = group.get('name')
        if profile in ('minimal', 'cd_only') and group_name == 'mend':
            print_info(f"cicd_profile is '{profile}' — optional_files group 'mend' not applicable (no SAST scanning), skipping")
            continue
        repo   = group.get('repo')
        branch = group.get('branch')
        files  = group.get('files', [])

        print_info(f"Checking optional file group: {group_name}")
        if not repo:
            print_error(f"Optional files group '{group_name}' is missing repo")
        elif 'myrepo' in str(repo) or 'myorg' in str(repo):
            print_error(f"Optional files group '{group_name}' has placeholder repo value")
        else:
            print_success(f"Optional files group '{group_name}' repo: {repo}")

        if not branch or branch == 'default':
            print_warning(f"Optional files group '{group_name}' has missing or placeholder branch")
        else:
            print_success(f"Optional files group '{group_name}' branch: {branch}")

        if not files:
            print_warning(f"Optional files group '{group_name}' has no files defined")
        else:
            print_success(f"Optional files group '{group_name}' has {len(files)} file(s)")
            for file_item in files:
                file_path    = file_item.get('path')
                can_be_empty = file_item.get('can_be_empty')
                executable   = file_item.get('executable')
                if not file_path:
                    print_error(f"File in optional group '{group_name}' is missing path")
                if can_be_empty is None:
                    print_error(f"File '{file_path}' in optional group '{group_name}' is missing can_be_empty")
                if executable is None:
                    print_error(f"File '{file_path}' in optional group '{group_name}' is missing executable")


def validate_deployment_targets(data: Dict):
    """Validate deployment targets (profile-aware)."""
    print_info("Validating deployment targets...")
    profile = _get_cicd_profile(data)
    if profile == 'minimal':
        print_info("cicd_profile is 'minimal' — deployment_targets not required, skipping")
        return
    if profile == 'ci_only':
        print_info("cicd_profile is 'ci_only' — deployment_targets not required, skipping")
        return

    deployment_targets = data.get('deployment_targets', {})

    ci_zone_placeholders  = ['zone1', 'zone2', 'zone3', 'myzone', 'env_code']
    cd_override_placeholders = [
        'myspecialzone', 'myspecialzone1', 'myspecialregion', 'myspecialregion1',
        'anotherzone', 'thirdzone', 'env_code', 'region1', 'region2',
    ]

    # CI targets — only for ci_cd profile
    if profile == 'ci_cd':
        ci_targets = deployment_targets.get('CI', {})
        if not ci_targets:
            print_error("No CI deployment targets defined")
        elif not isinstance(ci_targets, dict):
            print_error("CI deployment targets should be a dict organized by datacenter types (vpc_ng, ngdc)")
        else:
            allowed_types = ['vpc_ng', 'ngdc']
            for key in ci_targets:
                if key not in allowed_types:
                    print_error(f"Invalid datacenter type '{key}' in CI deployment targets — only 'vpc_ng' and 'ngdc' are allowed")

            # Exactly one of vpc_ng / ngdc must be defined — not both.
            # Placeholder-aware exceptions avoid blocking PRs that were
            # scaffolded from the template and not yet fully cleaned up:
            #
            #   Case A — both sections all-placeholder:
            #     Neither filled in yet. Warn; do not block.
            #
            #   Case B — one section has real values, the other is all-placeholder:
            #     User filled in the correct section and left the template remnant.
            #     Warn pointing to the section to remove; do not block.
            #
            #   Case C — both sections have at least one real value:
            #     Genuine misconfiguration — hard error.
            has_vpc_ng = bool(ci_targets.get('vpc_ng'))
            has_ngdc   = bool(ci_targets.get('ngdc'))
            if has_vpc_ng and has_ngdc:
                def _all_placeholders(entries):
                    return all(
                        (e.get('name', '') or '').lower() in ci_zone_placeholders
                        for e in (entries if isinstance(entries, list) else [entries])
                    )
                vpc_ng_all_ph = _all_placeholders(ci_targets['vpc_ng'])
                ngdc_all_ph   = _all_placeholders(ci_targets['ngdc'])

                if vpc_ng_all_ph and ngdc_all_ph:
                    # Case A — both unfilled
                    print_warning(
                        "CI deployment targets defines both 'vpc_ng' and 'ngdc' but all zone "
                        "names are still placeholders — remove the section that does not apply "
                        "to this service before merging to production"
                    )
                elif ngdc_all_ph and not vpc_ng_all_ph:
                    # Case B — vpc_ng has real values, ngdc is a leftover template entry
                    print_warning(
                        "CI deployment targets defines both 'vpc_ng' and 'ngdc'. "
                        "'vpc_ng' has real zone values — 'ngdc' appears to be an unfilled "
                        "template entry. Remove the 'ngdc' section before merging to production."
                    )
                elif vpc_ng_all_ph and not ngdc_all_ph:
                    # Case B — ngdc has real values, vpc_ng is a leftover template entry
                    print_warning(
                        "CI deployment targets defines both 'vpc_ng' and 'ngdc'. "
                        "'ngdc' has real zone values — 'vpc_ng' appears to be an unfilled "
                        "template entry. Remove the 'vpc_ng' section before merging to production."
                    )
                else:
                    # Case C — both have real values
                    print_error(
                        "CI deployment targets must define exactly one of 'vpc_ng' or 'ngdc', "
                        "not both — remove the one that does not apply to this service"
                    )
            elif not has_vpc_ng and not has_ngdc:
                print_warning("CI deployment targets has neither 'vpc_ng' nor 'ngdc' — target patching will be skipped at merge time")
            else:
                dc_type = 'vpc_ng' if has_vpc_ng else 'ngdc'
                dc_targets = ci_targets[dc_type]
                print_success(f"CI deployment targets for '{dc_type}' defined ({len(dc_targets)} zone(s))")
                for i, target in enumerate(dc_targets, 1):
                    target_name  = target.get('name')
                    default_size = target.get('default_size')
                    if not target_name:
                        print_error(f"CI {dc_type} target #{i} is missing name")
                    elif target_name.lower() in ci_zone_placeholders:
                        print_warning(
                            f"CI {dc_type} target '{target_name}' appears to be a placeholder — "
                            f"replace it with the actual environment/zone name before merging"
                        )
                    else:
                        print_success(f"CI {dc_type} target #{i}: name='{target_name}'")
                    if not default_size:
                        print_error(f"CI {dc_type} target '{target_name or f'#{i}'}' is missing default_size")

    # CD targets — for ci_cd and cd_only
    cd_targets = deployment_targets.get('CD', {})
    allowed_envs = ['integration', 'staging', 'production']
    if not cd_targets:
        print_error("No CD deployment targets defined")
    else:
        for env in cd_targets:
            if env not in allowed_envs:
                print_error(f"Invalid environment '{env}' in CD deployment targets — only {allowed_envs} are allowed")
        for env in allowed_envs:
            if env not in cd_targets:
                print_error(f"CD '{env}' environment is missing from deployment_targets — all three must be present")
        for env in allowed_envs:
            env_config = cd_targets.get(env, {})
            if not env_config:
                continue
            targets      = env_config.get('targets')
            target_type  = env_config.get('type')
            default_size = env_config.get('default_size')
            override_size = env_config.get('override_size', []) or []
            exclude      = env_config.get('exclude', []) or []

            if targets is None:
                print_warning(f"CD {env} has no 'targets' — defaults to 'all' at provisioning time")
            elif isinstance(targets, list) and len(targets) == 0:
                print_warning(f"CD {env} has an empty targets list — no secrets will be provisioned")
            elif targets == 'all':
                print_success(f"CD {env} targets: all")
            elif isinstance(targets, list):
                print_success(f"CD {env} targets: {len(targets)} specific region(s)")
            else:
                print_warning(f"CD {env} targets value '{targets}' is not 'all' or a list")

            if not target_type:
                print_error(f"CD {env} is missing 'type'")
            elif target_type not in ('zonal', 'regional'):
                print_error(f"CD {env} has invalid type '{target_type}' — must be 'zonal' or 'regional'")
            else:
                print_success(f"CD {env} type: {target_type}")

            if not default_size:
                print_error(f"CD {env} is missing 'default_size'")
            else:
                print_success(f"CD {env} default_size: {default_size}")

            for excl in exclude:
                if str(excl).lower() in cd_override_placeholders:
                    print_warning(f"CD {env} exclude entry '{excl}' appears to be a placeholder")
            for override in override_size:
                ot = override.get('target')
                if ot and ot.lower() in cd_override_placeholders:
                    print_warning(f"CD {env} override_size target '{ot}' appears to be a placeholder")


def validate_repo_consistency(data: Dict):
    """Validate that repo/branch are consistent across app_repo, mandatory_files, optional_files."""
    print_info("Validating repository consistency...")
    app_repos = data.get('app_repo', [])
    if not app_repos:
        print_warning("No app_repo defined — skipping consistency check")
        return

    ref_repo   = app_repos[0].get('repo')
    ref_branch = app_repos[0].get('branch')
    if not ref_repo or not ref_branch:
        print_warning("app_repo repo or branch missing — skipping consistency check")
        return

    print_info(f"Reference repo: {ref_repo} (branch: {ref_branch})")

    for group in data.get('mandatory_files', []):
        gname = group.get('name')
        if group.get('repo') and group.get('repo') != ref_repo:
            print_error(f"mandatory_files group '{gname}' repo does not match app_repo '{ref_repo}'")
        if group.get('branch') and group.get('branch') != ref_branch:
            print_error(f"mandatory_files group '{gname}' branch does not match app_repo branch '{ref_branch}'")

    for group in data.get('optional_files', []):
        gname = group.get('name')
        if group.get('repo') and group.get('repo') != ref_repo:
            print_error(f"optional_files group '{gname}' repo does not match app_repo '{ref_repo}'")
        if group.get('branch') and group.get('branch') != ref_branch:
            print_error(f"optional_files group '{gname}' branch does not match app_repo branch '{ref_branch}'")

    print_success("Repository consistency validation completed")


def validate_filename(yaml_file: str, data: Dict, ctx: ExecutionContext):
    """Validate filename rules for team onboarding files."""
    print_info("Validating filename format...")
    filename = os.path.basename(yaml_file)

    if filename in _REFERENCE_TEMPLATES:
        changed_files = _get_changed_files(ctx)
        if changed_files:
            changed_entries = {Path(line.split('\t', 1)[-1]).name for line in changed_files}
            if filename in changed_entries:
                if 'uuc-devops' in ctx.pr_label_set:
                    print_warning(f"File '{filename}' is a platform-managed template but allowed because PR label 'uuc-devops' is present")
                else:
                    print_error(f"File '{filename}' must not be changed by service teams — it is a platform-managed reference template")
                    print_info("  If this is a DevOps change, add the PR label 'uuc-devops'")
                    return
            deleted_entries = {
                Path(line.split('\t', 1)[-1]).name
                for line in changed_files if line.startswith('D\t')
            }
            if filename in deleted_entries:
                print_error(f"Deleting '{filename}' is not allowed — platform-managed reference template must remain in the repository")
                return
        print_success(f"Reference template filename '{filename}' is acceptable")
        return

    service_name = data.get('service_name')
    if not service_name or service_name == 'myservicename':
        print_warning("Cannot validate filename format: service_name is missing or still a placeholder")
        return

    expected = f"{service_name}-onboarding.yaml"
    if filename != expected:
        print_error(f"Filename does not follow the required format")
        print_error(f"  Expected: {expected}")
        print_error(f"  Got:      {filename}")
        print_info( f"  Format: <service_name>-onboarding.yaml")
    else:
        print_success(f"Filename format is correct: {filename}")


def validate_team_onboarding_consistency(yaml_file: str, commons_data: Dict):
    """Validate that all service files in the team branch reference the same commons team_name."""
    print_info("Validating cross-service onboarding consistency...")
    onboarding_files = _find_team_onboarding_files(yaml_file, commons_data)
    if len(onboarding_files) <= 1:
        print_info("Only one service onboarding file found — cross-service consistency check skipped")
        return

    commons_team = commons_data.get('team_name', '')
    for other_file in onboarding_files:
        if other_file.resolve() == Path(yaml_file).resolve():
            continue
        other_data = load_yaml(str(other_file))
        # team_name is now only in commons — verify service files don't disagree
        other_team = other_data.get('team_name', '')
        if other_team and commons_team and other_team != commons_team:
            print_error(
                f"Service file '{other_file.name}' has team_name '{other_team}' but commons.yaml "
                f"has team_name '{commons_team}' — team_name must only be in commons.yaml"
            )

    print_success("Cross-service onboarding consistency validation completed")


def validate_branch_slug(commons_data: Dict, ctx: ExecutionContext):
    """Validate that team_name in commons.yaml matches the target branch name."""
    print_info("Validating team slug against target branch name...")

    if not ctx.pr_basebranch:
        print_warning("PR_BASEBRANCH is not set — branch slug check skipped (local/merge run?)")
        return

    if not ctx.pr_basebranch.endswith('-onboarding'):
        print_info(f"Target branch '{ctx.pr_basebranch}' is not an onboarding branch — slug check skipped")
        return

    expected_slug = ctx.pr_basebranch[: -len('-onboarding')]
    team_name     = commons_data.get('team_name', '')

    if not team_name or team_name == 'myteamname':
        print_warning("commons.yaml team_name is missing or placeholder — branch slug check skipped")
        return

    actual_slug = team_name.lower().replace(' ', '-')
    if actual_slug != expected_slug:
        print_error(f"commons.yaml team_name slug '{actual_slug}' does not match target branch slug '{expected_slug}'")
        print_error(f"  Target branch  : {ctx.pr_basebranch}")
        print_error(f"  Expected slug  : {expected_slug}")
        print_info( f"  Fix: set team_name in commons.yaml to the team that owns branch '{ctx.pr_basebranch}'")
    else:
        print_success(f"team_name slug matches target branch: '{actual_slug}' == '{expected_slug}'")


def validate_pr_head_branch(ctx: ExecutionContext):
    """Validate that the PR head branch does not end with '-onboarding'."""
    print_info("Validating PR head branch name...")
    if not ctx.pr_branch:
        print_warning("PR_BRANCH is not set — head branch check skipped (local/merge run?)")
        return
    if ctx.pr_branch.endswith('-onboarding'):
        slug = ctx.pr_branch[:-len('-onboarding')]
        print_error(f"PR head branch '{ctx.pr_branch}' ends with reserved '-onboarding' suffix")
        print_error(f"  This suffix is reserved for team base branches only")
        print_info( f"  Rename your working branch — e.g. feat/{slug}-<description>")
    else:
        print_success(f"PR head branch name is valid: '{ctx.pr_branch}'")


# ===========================================================================
# Programmatic entry point (importable by merge scripts)
# ===========================================================================

def validate_file(
    yaml_file: str,
    ctx: Optional[ExecutionContext] = None,
) -> int:
    """Validate a single service onboarding YAML file.

    This is the generic programmatic entry point.  Call this from any
    pipeline step — PR or merge — by constructing an ExecutionContext and
    passing it here.

    Args:
        yaml_file:   Absolute or relative path to the service onboarding file.
        ctx:         ExecutionContext with pipeline-specific values.  If None,
                     one is built from the current environment variables.

    Returns:
        0  — validation passed (errors == 0)
        1  — validation failed (errors > 0)
    """
    global debug_mode
    _reset_counters()

    if ctx is None:
        ctx = build_context()

    debug_mode = ctx.debug

    print("=" * 55)
    print("  CI/CD Onboarding YAML Validation")
    print("=" * 55)
    if debug_mode:
        print(f"{YELLOW}[DEBUG MODE ENABLED]{NC}")
    print()

    print_debug(f"Loading service YAML: {yaml_file}")
    data = load_yaml(yaml_file)
    print_debug(f"Loaded {len(data)} top-level keys from service file")

    # ── 1. Profile (must come first — everything else is profile-aware) ───────
    validate_cicd_profile(data)
    print()
    profile = _get_cicd_profile(data)

    # ── 1b. Profile change impact (PR context — skipped gracefully otherwise) ─
    validate_cicd_profile_change(yaml_file, data, ctx)
    print()

    # ── 2. Filename / template protection ─────────────────────────────────────
    validate_filename(yaml_file, data, ctx)
    print()

    # ── 3. Branch checks (PR context only — skipped gracefully when missing) ──
    # These call through ctx so they work in merge context too (just skipped).
    # Branch slug is validated against commons, loaded below.
    validate_pr_head_branch(ctx)
    print()

    # ── 4. Load commons.yaml (mandatory — hard fail if missing) ───────────────
    commons_data = load_commons_for_file(yaml_file, ctx)
    if commons_data is None:
        # Error already recorded; print summary and exit.
        print("=" * 55)
        print("  Validation Summary")
        print("=" * 55)
        print_error(f"Validation aborted — commons.yaml is required")
        return 1
    print()

    # ── 5. Branch slug (uses commons team_name) ───────────────────────────────
    validate_branch_slug(commons_data, ctx)
    print()

    # ── 6. Ensure no commons-only fields in service file ─────────────────────
    validate_no_commons_fields_in_service(data)
    print()

    # ── 7. Validate commons.yaml ──────────────────────────────────────────────
    validate_commons_yaml(yaml_file, commons_data, profile or 'ci_cd')
    print()

    # ── 8. Cross-service consistency (uses commons) ───────────────────────────
    validate_team_onboarding_consistency(yaml_file, commons_data)
    print()

    # ── 9. Service-specific field validations ─────────────────────────────────
    validate_service_name(data)
    print()

    validate_inventory_repo(data, commons_data)
    print()

    validate_incident_repo(data)
    print()

    validate_compliance_bucket(data)
    print()

    validate_app_repo(data)
    print()

    validate_servicenow_crn(data)
    print()

    validate_slack_config(data)
    print()

    validate_mandatory_files(data)
    print()

    validate_optional_files(data)
    print()

    validate_deployment_targets(data)
    print()

    validate_repo_consistency(data)
    print()

    # ── Summary ───────────────────────────────────────────────────────────────
    print("=" * 55)
    print("  Validation Summary")
    print("=" * 55)

    if errors == 0 and warnings == 0:
        print_success("All validations passed! ✓")
        return 0
    elif errors == 0:
        print_warning(f"Validation completed with {warnings} warning(s)")
        return 0
    else:
        print_error(f"Validation failed with {errors} error(s) and {warnings} warning(s)")
        return 1


# ===========================================================================
# CLI entry point
# ===========================================================================

def main():
    global debug_mode

    parser = argparse.ArgumentParser(
        description='Validate CI/CD onboarding YAML file for completeness and correctness'
    )
    # yaml_file is optional when --check-commons is used
    parser.add_argument(
        'yaml_file', nargs='?', default='',
        help='Path to <service_name>-onboarding.yaml file to validate'
    )
    parser.add_argument('--debug',   action='store_true', help='Enable debug logging')
    parser.add_argument(
        '--commons',
        default='',
        help='Explicit path to commons.yaml (overrides auto-discovery)',
    )
    parser.add_argument(
        '--check-commons',
        metavar='SEARCH_DIR',
        default='',
        help=(
            'Run PR-level commons.yaml invariant checks against SEARCH_DIR '
            '(branch workspace root). Checks: commons not deleted, exists before '
            'new service files, no secrets in service files. '
            'Exits 0 on pass, 1 on failure. Cannot be combined with yaml_file.'
        ),
    )

    args = parser.parse_args()

    ctx = build_context(debug=args.debug, commons_path=args.commons)
    debug_mode = ctx.debug

    if args.check_commons:
        _reset_counters()
        print("=" * 55)
        print("  commons.yaml PR-Level Invariant Checks")
        print("=" * 55)
        print()
        n_errors = validate_commons_pr_invariants(args.check_commons, ctx)
        print()
        print("=" * 55)
        print("  Invariant Check Summary")
        print("=" * 55)
        if n_errors == 0:
            print_success("All commons.yaml PR-level invariant checks passed ✓")
        else:
            print_error(f"commons.yaml invariant checks failed with {n_errors} error(s)")
            show_documentation_hint()
        sys.exit(0 if n_errors == 0 else 1)

    if not args.yaml_file:
        parser.error("yaml_file is required unless --check-commons is used")

    rc = validate_file(args.yaml_file, ctx)
    sys.exit(rc)


def show_documentation_hint():
    """Print a brief pointer to the onboarding documentation."""
    print()
    print(f"{BLUE}[INFO]{NC} For onboarding documentation see:")
    print(f"{BLUE}[INFO]{NC}   https://github.ibm.com/genctl-cicd/uuc-service-cicd-onboarding/blob/main/README.md")


if __name__ == '__main__':
    main()