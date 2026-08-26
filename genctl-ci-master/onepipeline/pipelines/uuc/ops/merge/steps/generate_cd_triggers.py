#!/usr/bin/env python3
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
"""
generate_cd_triggers.py
=======================
Reads a team-specific environment-code YAML (either a local file path or a
raw GitHub URL) and generates/patches Terraform HCL locals for CD pipeline
trigger data inside a team's <team-slug>-cd-pipeline_vars.tf file.

Supports two YAML topologies:
  regional — cloud > regional > clusters          (e.g. DCMS)
  zonal    — <datacenter> > zones > clusters      (e.g. undercloud / other teams)
Topology is auto-detected from the YAML structure; --topology overrides it.

Account-type → tier mapping:
  dev   → integration only
  prod  → staging + production

Trigger shape per target-environment  (<env_code>-<cluster>):
  promotion-pipeline:
    1. manual  / promotion-listener            / master-to-<target>-promotion-pr
    2. scm PR  / promotion-validation-listener / master-to-<target>-promotion-validation-pr
  cd-pipeline:
    1. scm push / cd-listener                  / master-to-<target>
       properties: target-environment, target-region (first 2 hyphen-segments of env_code)

Usage:
  python3 generate_cd_triggers.py \\
    --env-yaml      <path-or-url>           \\
    --team-slug     dcms                    \\
    --account-type  dev                     \\
    --tf-file       dcms-cd-pipeline_vars.tf \\
    [--topology     regional|zonal]         \\
    [--excludes     "target-env-1,target-env-2"] \\
    [--service-slug auth-service]

When --excludes + --service-slug are given the script writes a standalone
service-specific local (no merge — just the filtered list) in addition to
(or instead of updating) the tier-level default local.
"""

import argparse
import os
import re
import sys
import urllib.request
from textwrap import indent
from typing import NamedTuple

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install it with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------
class TargetEnv(NamedTuple):
    env_code: str      # e.g. us-east-int01-cloud-regional
    cluster:  str      # e.g. roks-goal
    tier:     str      # integration | staging | production

    @property
    def target_environment(self) -> str:
        return f"{self.env_code}-{self.cluster}"

    @property
    def target_region(self) -> str:
        """First two hyphen-delimited segments of env_code  (e.g. 'us-east')."""
        parts = self.env_code.split("-")
        return "-".join(parts[:2]) if len(parts) >= 2 else self.env_code


# ---------------------------------------------------------------------------
# Tier → account-type mapping
# ---------------------------------------------------------------------------
TIER_FOR_ACCOUNT = {
    "dev":  {"integration"},
    "prod": {"staging", "production"},
}


# ---------------------------------------------------------------------------
# YAML loading (local path or https:// URL)
# ---------------------------------------------------------------------------
_GHE_BLOB_RE = re.compile(
    r'^(https?://[^/]+)/([^/]+)/([^/]+)/(?:blob|raw)/([^/]+)/(.+)$'
)


def _to_ghe_contents_api(url: str) -> str:
    """Convert a GitHub blob/raw browser URL to the GHE Contents API endpoint.

    Web /blob/ and /raw/ URLs on GHE redirect to a login page for
    unauthenticated requests and return HTML instead of file content even
    when a token header is supplied.  The Contents API
    (GET /api/v3/repos/<owner>/<repo>/contents/<path>?ref=<ref>) honours
    the Authorization header and returns raw bytes when
    Accept: application/vnd.github.v3.raw is set.

    Patterns handled:
      https://<ghe-host>/<owner>/<repo>/blob/<ref>/<path>
      https://<ghe-host>/<owner>/<repo>/raw/<ref>/<path>
    Both become:
      https://<ghe-host>/api/v3/repos/<owner>/<repo>/contents/<path>?ref=<ref>
    """
    m = _GHE_BLOB_RE.match(url)
    if m:
        ghe_host, owner, repo, ref, path = m.groups()
        return f"{ghe_host}/api/v3/repos/{owner}/{repo}/contents/{path}?ref={ref}"
    return url  # already an API or raw URL — return as-is


def load_yaml(source: str) -> dict:
    if source.startswith("https://") or source.startswith("http://"):
        fetch_url = _to_ghe_contents_api(source)
        headers = {
            "User-Agent": "generate-cd-triggers/1.0",
            # Request raw file bytes directly — avoids JSON-wrapping the content.
            "Accept": "application/vnd.github.v3.raw",
        }
        token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GIT_TOKEN")
        if token:
            headers["Authorization"] = f"token {token}"
        req = urllib.request.Request(fetch_url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                content = resp.read().decode("utf-8")
        except Exception as exc:
            print(f"ERROR: Failed to fetch YAML from {fetch_url}: {exc}", file=sys.stderr)
            sys.exit(1)
        if not content.strip():
            print(
                f"ERROR: YAML fetched from {fetch_url} is empty — "
                f"check the file exists and the token has read access.",
                file=sys.stderr,
            )
            sys.exit(1)
    else:
        try:
            with open(source) as fh:
                content = fh.read()
        except OSError as exc:
            print(f"ERROR: Cannot open YAML file {source}: {exc}", file=sys.stderr)
            sys.exit(1)

    try:
        return yaml.safe_load(content)
    except yaml.YAMLError as exc:
        print(f"ERROR: YAML parse error in {source}: {exc}", file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Environment-code YAML traversal
# ---------------------------------------------------------------------------
def _iter_regional(region_data: dict, tier: str) -> list[TargetEnv]:
    """Traverse cloud > regional > clusters."""
    results = []
    loc = region_data.get("locations", {}) or {}
    cloud = loc.get("cloud", {}) or {}
    regional = cloud.get("regional") or {}
    env_code = (regional.get("environment_code") or "").strip()
    clusters = regional.get("clusters") or []
    for cluster in clusters:
        if env_code and cluster:
            results.append(TargetEnv(env_code=env_code, cluster=cluster, tier=tier))
    return results


def _iter_zonal(region_data: dict, tier: str) -> list[TargetEnv]:
    """Traverse <datacenter> > zones > clusters."""
    results = []
    for _dc, dc_data in (region_data.get("locations") or {}).items():
        if not isinstance(dc_data, dict):
            continue
        # regional sub-key (mixed YAML like dev01 cloud entries)
        regional = (dc_data.get("regional") or {})
        if regional:
            env_code = (regional.get("environment_code") or "").strip()
            clusters = regional.get("clusters") or []
            for cluster in clusters:
                if env_code and cluster:
                    results.append(TargetEnv(env_code=env_code, cluster=cluster, tier=tier))
            continue
        # zonal sub-key
        for _zone, zone_data in (dc_data.get("zones") or {}).items():
            if not isinstance(zone_data, dict):
                continue
            env_code = (zone_data.get("environment_code") or "").strip()
            clusters = zone_data.get("clusters") or []
            for cluster in clusters:
                if env_code and cluster:
                    results.append(TargetEnv(env_code=env_code, cluster=cluster, tier=tier))
    return results


def _detect_topology(env_yaml: dict) -> str:
    """
    Auto-detect whether the YAML uses regional or zonal topology by
    checking the first region entry we find for a 'regional' sub-key
    under 'cloud' location.  Falls back to 'zonal'.
    """
    et = env_yaml.get("environment_type") or {}
    for _tier, tier_data in et.items():
        for _dep, dep_data in (tier_data.get("deployments") or {}).items():
            for _region, region_data in (dep_data.get("regions") or {}).items():
                loc = (region_data.get("locations") or {}).get("cloud") or {}
                if "regional" in loc:
                    return "regional"
                # check any location for a 'zones' key → zonal
                for _lc, lc_data in (region_data.get("locations") or {}).items():
                    if isinstance(lc_data, dict) and "zones" in lc_data:
                        return "zonal"
    return "zonal"


def collect_target_envs(
    env_yaml: dict,
    account_type: str,
    topology: str,
) -> list[TargetEnv]:
    """Return all TargetEnv entries for the given account type."""
    allowed_tiers = TIER_FOR_ACCOUNT.get(account_type, {"integration"})
    et = env_yaml.get("environment_type") or {}
    results: list[TargetEnv] = []

    for tier, tier_data in et.items():
        if tier not in allowed_tiers:
            continue
        for _dep_id, dep_data in (tier_data.get("deployments") or {}).items():
            for _region, region_data in (dep_data.get("regions") or {}).items():
                if topology == "regional":
                    results.extend(_iter_regional(region_data, tier))
                else:
                    results.extend(_iter_zonal(region_data, tier))

    # Stable ordering: tier → env_code → cluster
    results.sort(key=lambda t: (t.tier, t.env_code, t.cluster))
    return results


# ---------------------------------------------------------------------------
# HCL generation
# ---------------------------------------------------------------------------
_INDENT = "  "   # 2-space indent inside the locals {} block


def _hcl_trigger_block(target: TargetEnv, trigger_type: str, listener: str) -> str:
    """
    Emit a single trigger object.
    trigger_type: 'promotion-manual' | 'promotion-validation' | 'cd'
    """
    te  = target.target_environment
    tr  = target.target_region

    if trigger_type == "promotion-manual":
        return (
            f"    {{\n"
            f'      trigger_type        = "manual"\n'
            f'      worker              = "IBM-INTERNAL-WORKER"\n'
            f'      event_listener      = "promotion-listener"\n'
            f'      trigger_name        = "master-to-{te}-promotion-pr"\n'
            f'      enabled             = true\n'
            f'      max_concurrent_runs = 1\n'
            f"      properties = {{\n"
            f'        "source-environment" = {{\n'
            f'          type         = "text"\n'
            f'          value        = "master"\n'
            f'          secret_group = var.secret_group\n'
            f"        }}\n"
            f'        "target-environment" = {{\n'
            f'          type         = "text"\n'
            f'          value        = "{te}"\n'
            f'          secret_group = var.secret_group\n'
            f"        }}\n"
            f"      }}\n"
            f"    }}"
        )
    elif trigger_type == "promotion-validation":
        return (
            f"    {{\n"
            f'      trigger_type   = "scm"\n'
            f'      trigger_branch = "{te}"\n'
            f'      events         = ["pull_request"]\n'
            f'      event_listener = "promotion-validation-listener"\n'
            f'      worker         = "IBM-INTERNAL-WORKER"\n'
            f'      trigger_name   = "master-to-{te}-promotion-validation-pr"\n'
            f'      enabled        = true\n'
            f"      properties = {{\n"
            f'        "source-environment" = {{\n'
            f'          type         = "text"\n'
            f'          value        = "master"\n'
            f'          secret_group = var.secret_group\n'
            f"        }}\n"
            f'        "target-environment" = {{\n'
            f'          type         = "text"\n'
            f'          value        = "{te}"\n'
            f'          secret_group = var.secret_group\n'
            f"        }}\n"
            f"      }}\n"
            f"    }}"
        )
    else:  # cd
        return (
            f"    {{\n"
            f'      trigger_type        = "scm"\n'
            f'      trigger_branch      = "{te}"\n'
            f'      events              = ["push"]\n'
            f'      event_listener      = "cd-listener"\n'
            f'      trigger_name        = "master-to-{te}"\n'
            f'      worker              = "IBM-INTERNAL-WORKER"\n'
            f'      enabled             = true\n'
            f'      max_concurrent_runs = 1\n'
            f"      properties = {{\n"
            f'        "target-environment" = {{\n'
            f'          type         = "text"\n'
            f'          value        = "{te}"\n'
            f'          secret_group = var.secret_group\n'
            f"        }}\n"
            f'        "target-region" = {{\n'
            f'          type         = "text"\n'
            f'          value        = "{tr}"\n'
            f'          secret_group = var.secret_group\n'
            f"        }}\n"
            f"      }}\n"
            f"    }}"
        )


def build_hcl_local(
    local_name: str,
    targets: list[TargetEnv],
    account_type: str,
    source_url: str,
) -> str:
    """
    Produce the full HCL locals block for one trigger-data local.

    Example output (truncated):
      # [AUTO-GENERATED] ...
      <local_name> = {
        "promotion-pipeline" = [
          { ... },
          ...
        ]
        "cd-pipeline" = [
          { ... },
          ...
        ]
      }
    """
    tier_label = "integration" if account_type == "dev" else "staging + production"

    header = (
        f"  # ---------------------------------------------------------------------------\n"
        f"  # [AUTO-GENERATED by generate_cd_triggers.py]\n"
        f"  # Source: {source_url}\n"
        f"  # Account type : {account_type}  →  tiers: {tier_label}\n"
        f"  # Target count : {len(targets)} target-environment(s)\n"
        f"  # DO NOT EDIT MANUALLY — re-run the provisioning pipeline to regenerate.\n"
        f"  # ---------------------------------------------------------------------------\n"
    )

    promotion_triggers = []
    cd_triggers = []
    for t in targets:
        promotion_triggers.append(_hcl_trigger_block(t, "promotion-manual",     "promotion-listener"))
        promotion_triggers.append(_hcl_trigger_block(t, "promotion-validation", "promotion-validation-listener"))
        cd_triggers.append(      _hcl_trigger_block(t, "cd",                   "cd-listener"))

    def _join(blocks):
        return ",\n".join(blocks)

    body = (
        f"  {local_name} = {{\n"
        f'    "promotion-pipeline" = [\n'
        f"{_join(promotion_triggers)}\n"
        f"    ]\n"
        f'    "cd-pipeline" = [\n'
        f"{_join(cd_triggers)}\n"
        f"    ]\n"
        f"  }}"
    )

    return header + body


# ---------------------------------------------------------------------------
# .tf file patching
# ---------------------------------------------------------------------------
# Sentinel comments that bracket the auto-generated block inside the locals {}
_BEGIN_SENTINEL = "# [AUTO-GENERATED-BEGIN:"
_END_SENTINEL   = "# [AUTO-GENERATED-END:"


def _sentinel_begin(local_name: str) -> str:
    return f"  {_BEGIN_SENTINEL} {local_name}]"


def _sentinel_end(local_name: str) -> str:
    return f"  {_END_SENTINEL} {local_name}]"


def patch_tf_file(tf_path: str, local_name: str, hcl_block: str) -> bool:
    """
    Insert or replace a named auto-generated locals block inside the
    outermost locals { } block in the given .tf file.

    The block is surrounded by sentinel comment lines so it can be found
    and replaced reliably on subsequent runs.

    Returns True if the file was modified, False if unchanged.
    """
    with open(tf_path) as fh:
        original = fh.read()

    begin = _sentinel_begin(local_name)
    end   = _sentinel_end(local_name)

    new_block = f"{begin}\n{hcl_block}\n{end}"

    # Case 1: block already exists — replace it entirely
    pattern = re.compile(
        re.escape(begin) + r".*?" + re.escape(end),
        re.DOTALL,
    )
    if pattern.search(original):
        updated = pattern.sub(new_block, original, count=1)
        if updated == original:
            print(f"INFO: '{local_name}' already up to date — no changes written.", file=sys.stderr)
            return False
        with open(tf_path, "w") as fh:
            fh.write(updated)
        print(f"INFO: Replaced existing '{local_name}' block in {tf_path}", file=sys.stderr)
        return True

    # Case 2: block is new — insert it before the closing } of the locals block.
    # We locate the last '}' that closes the outermost locals { ... }.
    locals_match = re.search(r'\blocals\s*\{', original)
    if not locals_match:
        print(f"ERROR: Could not find 'locals {{' block in {tf_path}", file=sys.stderr)
        sys.exit(1)

    # Walk from locals_match.end() tracking brace depth to find the closing }
    depth = 1
    pos   = locals_match.end()
    close_pos = None
    while pos < len(original) and depth > 0:
        ch = original[pos]
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                close_pos = pos
                break
        pos += 1

    if close_pos is None:
        print(f"ERROR: Could not locate closing '}}' of locals block in {tf_path}", file=sys.stderr)
        sys.exit(1)

    insert = f"\n{new_block}\n"
    updated = original[:close_pos] + insert + original[close_pos:]
    with open(tf_path, "w") as fh:
        fh.write(updated)
    print(f"INFO: Inserted new '{local_name}' block into {tf_path}", file=sys.stderr)
    return True


def patch_default_trigger_pointer(tf_path: str, team_underscore: str, new_local_name: str) -> bool:
    """
    Update the line:
      dcms_cd_pipeline_types_trigger_data = <anything>
    to point to the new tier-default local, but only when it currently points
    to the module default (common_cd_config.common_cd_pipeline_types_trigger_data).
    Does NOT overwrite if it already points to a generated local.
    """
    pointer_key = f"{team_underscore}_cd_pipeline_types_trigger_data"
    module_default = "module.common_cd_config.common_cd_pipeline_types_trigger_data"

    with open(tf_path) as fh:
        content = fh.read()

    pattern = re.compile(
        r'(' + re.escape(pointer_key) + r'\s*=\s*)' + re.escape(module_default)
    )
    if not pattern.search(content):
        # Either already updated or not present — skip silently
        return False

    updated = pattern.sub(r'\g<1>local.' + new_local_name, content, count=1)
    with open(tf_path, "w") as fh:
        fh.write(updated)
    print(
        f"INFO: Updated {pointer_key} → local.{new_local_name} in {tf_path}",
        file=sys.stderr,
    )
    return True


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------
def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Generate CD pipeline trigger HCL locals from an environment-code YAML.",
    )
    p.add_argument("--env-yaml",      required=True,
                   help="Path or https:// URL to the environment-code YAML")
    p.add_argument("--team-slug",     required=True,
                   help="Team slug (e.g. dcms, fabric). Determines local variable prefix.")
    p.add_argument("--account-type",  default="dev", choices=["dev", "prod"],
                   help="Account type: dev (integration) or prod (staging+production). Default: dev")
    p.add_argument("--tf-file",       required=True,
                   help="Absolute path to the team's <team-slug>-cd-pipeline_vars.tf to patch")
    p.add_argument("--topology",      choices=["regional", "zonal"],
                   help="Override topology auto-detection: regional | zonal")
    p.add_argument("--excludes",      default="",
                   help="Comma-separated list of target-environments to exclude (for service override)")
    p.add_argument("--service-slug",  default="",
                   help="Service slug (e.g. auth-service). Required when --excludes is set.")
    return p.parse_args()


def main() -> None:
    args = parse_args()

    # ── Validate args ──────────────────────────────────────────────────────────
    excludes: set[str] = set()
    if args.excludes:
        excludes = {e.strip() for e in args.excludes.split(",") if e.strip()}
    if excludes and not args.service_slug:
        print("ERROR: --service-slug is required when --excludes is specified.", file=sys.stderr)
        sys.exit(1)

    team_underscore = args.team_slug.replace("-", "_")

    # ── Load YAML ──────────────────────────────────────────────────────────────
    env_yaml = load_yaml(args.env_yaml)

    # ── Auto-detect topology ───────────────────────────────────────────────────
    topology = args.topology or _detect_topology(env_yaml)
    print(f"INFO: topology={topology}  account_type={args.account_type}", file=sys.stderr)

    # ── Collect all target environments for the given account type ─────────────
    all_targets = collect_target_envs(env_yaml, args.account_type, topology)
    if not all_targets:
        print(
            f"WARNING: No target environments found for account_type='{args.account_type}'. "
            f"Nothing to write.",
            file=sys.stderr,
        )
        sys.exit(0)

    # ── Determine tier suffix for the default local name ───────────────────────
    # dev  → _integration   |   prod → _production  (use the dominant tier name)
    tier_suffix = "integration" if args.account_type == "dev" else "production"
    default_local = f"{team_underscore}_cd_pipeline_types_trigger_data_{tier_suffix}"

    # ── 1. Write / update the tier-default local (all targets, no excludes) ────
    hcl_default = build_hcl_local(
        local_name=default_local,
        targets=all_targets,
        account_type=args.account_type,
        source_url=args.env_yaml,
    )
    patch_tf_file(args.tf_file, default_local, hcl_default)

    # Update the team-level pointer local to reference the tier default
    # (only if it still points to the module default)
    pointer_local = f"{team_underscore}_cd_pipeline_types_trigger_data"
    patch_default_trigger_pointer(args.tf_file, team_underscore, default_local)

    # ── 2. Write service-specific override local (when excludes given) ─────────
    if excludes:
        service_underscore = args.service_slug.replace("-", "_")
        svc_local = f"{team_underscore}_cd_pipeline_types_trigger_data_{service_underscore}"

        filtered = [t for t in all_targets if t.target_environment not in excludes]
        excluded_count = len(all_targets) - len(filtered)
        print(
            f"INFO: service override '{svc_local}': "
            f"{len(all_targets)} targets → {len(filtered)} after {excluded_count} exclude(s)",
            file=sys.stderr,
        )

        hcl_svc = build_hcl_local(
            local_name=svc_local,
            targets=filtered,
            account_type=args.account_type,
            source_url=args.env_yaml,
        )
        patch_tf_file(args.tf_file, svc_local, hcl_svc)

    print("INFO: generate_cd_triggers.py completed successfully.", file=sys.stderr)


if __name__ == "__main__":
    main()
