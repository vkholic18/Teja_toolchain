#!/usr/bin/env python3
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
"""
zone_region_map_utils.py
------------------------
Utility module for mapping VPC physical zones to regions for secret provisioning.

Responsibilities:
  1. Parse zone/region data from two env-code YAML files:
       - dcms_environment_code.yaml        (DCMS team only)
       - undercloud_environment_code.yaml  (all other teams)
  2. Expose two public functions:
       get_secret_targets(env, deployment_targets_config, zone_map)
       build_secret_name(secret_group, secret_name, secret_type, region, zone,
                         cluster, unique_per_cluster)
  3. CLI entry-point for use from shell scripts — prints JSON to stdout.

Applicable secret types:
  - global   (default / not set) → provisioned once, NO zone-map expansion needed.
  - regional → provisioned once per REGION in the target env.
  - zonal    → provisioned once per ZONE in the target env.
  Only 'regional' and 'zonal' entries ever reach this utility.

unique_per_cluster behaviour:
  - false (default) → one secret per zone (zonal) or per region+deployment (regional).
                       Cluster name is NOT included in the secret name.
  - true            → one secret per zone+cluster (zonal) or per region+deployment+cluster
                       (regional).  Cluster name IS included in the secret name.

  Naming convention (secret_group = sg-uuc-<team>):
    global,   any:                              sg-uuc-<team>-<name>
    regional, unique_per_cluster=false:   sg-uuc-<team>-<short-region>-<deployment-id>-<name>
    regional, unique_per_cluster=true:    sg-uuc-<team>-<short-region>-<deployment-id>-<cluster>-<name>
    zonal,    unique_per_cluster=false:   sg-uuc-<team>-<environment-code>-<name>
    zonal,    unique_per_cluster=true:    sg-uuc-<team>-<environment-code>-<cluster>-<name>

  Where:
    <short-region>    = first two hyphen-segments of the env_code  (e.g. "eu-gb")
    <deployment-id>   = third hyphen-segment of the env_code       (e.g. "prod01", "int01", "dev01")
    <environment-code>= full environment_code value from the YAML  (e.g. "eu-gb-dev01-cloud-zone1")

Account boundary:
  - Development account  → integration environment only.
  - Production account   → staging + production environments.
  - Development tier     → NOT provisioned by default.  Pass include_development=True
                           (library) or --include-development (CLI) to opt in.
                           Intended for temporary use only.
  - development_deployments → When include_development=True, only the specified
                           deployment IDs are included in the development zone map.
                           Defaults to {"dev01", "dev02"} (OTC1 and OTC2 only).
                           Pass an explicit set (library) or --development-deployments
                           (CLI, comma-separated) to override.

Usage (as a library):
    from zone_region_map_utils import get_zone_map_from_env_yaml, get_secret_targets, build_secret_name

Usage (from shell):
    python3 zone_region_map_utils.py get-targets \\
        --env integration \\
        --env-yaml-source /path/to/undercloud_environment_code.yaml \\
        --deployment-targets-json '<json>'
    # → prints JSON list of {zone, region, cluster, size} dicts

    # Include OTC1+OTC2 development environments (default when --include-development):
    python3 zone_region_map_utils.py get-targets \\
        --env development \\
        --include-development \\
        --env-yaml-source /path/to/undercloud_environment_code.yaml \\
        --deployment-targets-json '<json>'

    # Include specific development deployments only:
    python3 zone_region_map_utils.py get-targets \\
        --env development \\
        --include-development \\
        --development-deployments dev01,dev02 \\
        --env-yaml-source /path/to/undercloud_environment_code.yaml \\
        --deployment-targets-json '<json>'
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.request
import urllib.error
from typing import Any

# ---------------------------------------------------------------------------
# Zone map type alias
# ---------------------------------------------------------------------------

# Zone map type: env → { env_code → [(compact_label, cluster), ...] }
ZoneMapT = dict[str, dict[str, list[tuple[str, str]]]]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# Default deployment IDs included when include_development=True.
# These correspond to OTC1 (dev01/eu-gb) and OTC2 (dev02/eu-gb) only.
_DEFAULT_DEVELOPMENT_DEPLOYMENTS: frozenset[str] = frozenset({"dev01", "dev02"})

# Default IBM Cloud region filter applied to the development tier.
# Both OTC1 and OTC2 live in the eu-gb region; us-south entries within these
# deployments are excluded by default.
_DEFAULT_DEVELOPMENT_REGIONS: frozenset[str] = frozenset({"eu-gb"})


def get_zone_map_from_env_yaml(
    source: str,
    github_token: str | None = None,
    include_development: bool = False,
    development_deployments: set[str] | None = None,
    development_regions: set[str] | None = None,
) -> ZoneMapT:
    """
    Build a zone_map dict from a dcms_environment_code.yaml or
    undercloud_environment_code.yaml file (local path or https:// URL).

    The returned structure mirrors what get_zone_map() returns:

        {
          "integration": {
            "<env_code>": [("<env_code>-<cluster>", "<cluster>"), ...],
            ...
          },
          "staging":     { ... },
          "production":  { ... },
          # "development": { ... }  — only present when include_development=True
        }

    Each value list contains (compact_label, cluster) tuples.

    For regional entries  env_code  is the region identifier
    (e.g. "us-east-int01-cloud-regional") and each tuple is
    ("us-east-int01-cloud-regional-roks-goal", "roks-goal").

    For zonal entries the env_code (e.g. "us-south-int01-dal10-zone1") acts
    as both region and zone in the secret naming convention.

    Args:
        source:                  Local file path or https:// URL (blob or raw).
        github_token:            Optional GHE token used when source is a URL.
        include_development:     When True, also parse the ``development`` tier and
                                 include it in the returned zone_map under the
                                 ``"development"`` key.  Defaults to False — dev
                                 environments are not provisioned by the automated
                                 pipeline under normal circumstances.
        development_deployments: When include_development=True, only the deployment
                                 IDs in this set are included from the development
                                 tier.  Defaults to {"dev01", "dev02"} (OTC1+OTC2).
                                 Pass an explicit set to override.
        development_regions:     When include_development=True, only regions whose
                                 YAML key matches an entry in this set are included
                                 from the development tier.  Defaults to {"eu-gb"}
                                 (OTC1 and OTC2 are both in eu-gb/cloud/zone1).
                                 The special key "cloud" is resolved to the IBM Cloud
                                 region prefix of the env_code before matching, so
                                 "eu-gb" correctly captures over-the-cloud entries.
                                 Pass an explicit set to override.

    Raises RuntimeError if the file cannot be loaded or parsed.
    """
    # Resolve which development deployment IDs to include.
    # Defaulting to OTC1 (dev01) and OTC2 (dev02) keeps the scope narrow — other
    # dev clusters (dev03, dev06, dev07, dev08) are not included unless explicitly
    # requested via an explicit set or the --development-deployments CLI flag.
    _dev_deployments: frozenset[str] = (
        frozenset(development_deployments)
        if development_deployments is not None
        else _DEFAULT_DEVELOPMENT_DEPLOYMENTS
    )
    # Resolve which IBM Cloud regions to include within the development tier.
    # Defaults to {"eu-gb"} — filters out us-south entries inside dev01/dev02.
    _dev_regions: frozenset[str] = (
        frozenset(development_regions)
        if development_regions is not None
        else _DEFAULT_DEVELOPMENT_REGIONS
    )
    token = github_token or os.environ.get("GITHUB_TOKEN") or os.environ.get("GHE_TOKEN")

    # ── Load raw YAML content ─────────────────────────────────────────────────
    if source.startswith("https://") or source.startswith("http://"):
        # Convert a GitHub blob/raw web URL to the GHE Contents API endpoint
        # so that the Authorization: token header is honoured.
        # Web /raw/ URLs on GHE redirect to a login page for unauthenticated
        # requests — the API endpoint accepts the token header correctly.
        #
        # Patterns handled:
        #   https://<ghe-host>/<owner>/<repo>/blob/<ref>/<path>
        #   https://<ghe-host>/<owner>/<repo>/raw/<ref>/<path>
        # Both are converted to:
        #   https://<ghe-host>/api/v3/repos/<owner>/<repo>/contents/<path>?ref=<ref>
        fetch_url = source
        _ghe_blob_re = re.compile(
            r'^(https?://[^/]+)/([^/]+)/([^/]+)/(?:blob|raw)/([^/]+)/(.+)$'
        )
        m = _ghe_blob_re.match(source)
        if m:
            ghe_host, owner, repo, ref, path = m.groups()
            fetch_url = (
                f"{ghe_host}/api/v3/repos/{owner}/{repo}"
                f"/contents/{path}?ref={ref}"
            )

        headers: dict[str, str] = {
            "User-Agent": "zone-region-map-utils/1.0",
            "Accept":     "application/vnd.github.v3.raw",
        }
        if token:
            headers["Authorization"] = f"token {token}"
        req = urllib.request.Request(fetch_url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                content = resp.read().decode("utf-8")
        except Exception as exc:
            raise RuntimeError(f"Failed to fetch env-code YAML from {fetch_url}: {exc}") from exc

        if not content.strip():
            raise RuntimeError(
                f"env-code YAML fetched from {fetch_url} is empty — "
                f"check that the file exists in the repository and the token has read access."
            )
    else:
        try:
            with open(source) as fh:
                content = fh.read()
        except OSError as exc:
            raise RuntimeError(f"Cannot open env-code YAML file {source}: {exc}") from exc

    try:
        import yaml as _yaml  # type: ignore[import]
        data = _yaml.safe_load(content)
    except Exception as exc:
        raise RuntimeError(f"YAML parse error in {source}: {exc}") from exc

    if not isinstance(data, dict):
        raise RuntimeError(f"env-code YAML root is not a dict: {source}")

    # ── Traverse the YAML and build zone_map ─────────────────────────────────
    # By default only the three account-boundary tiers are provisioned.
    # "development" is excluded unless include_development=True is passed —
    # development secrets are temporary / non-standard and must be opted in to
    # explicitly to avoid accidental provisioning.
    ACCOUNT_TIERS = {"production", "staging", "integration"}
    if include_development:
        ACCOUNT_TIERS = ACCOUNT_TIERS | {"development"}

    result: ZoneMapT = {
        "integration": {},
        "staging":     {},
        "production":  {},
    }
    if include_development:
        result["development"] = {}

    for tier_name, tier_data in (data.get("environment_type") or {}).items():
        if tier_name not in ACCOUNT_TIERS:
            continue
        bucket = tier_name

        for _dep_id, dep_data in (tier_data.get("deployments") or {}).items():
            # For the development tier, only include the explicitly allowed deployment IDs.
            # This restricts provisioning to OTC1 (dev01) and OTC2 (dev02) by default,
            # preventing accidental expansion to dev03/dev06/dev07/dev08 clusters.
            if tier_name == "development" and _dep_id not in _dev_deployments:
                continue
            for region_name, region_data in (dep_data.get("regions") or {}).items():
                # For the development tier, skip regions that are not in the
                # allowed set.  The YAML key "cloud" is a virtual region name used
                # for over-the-cloud environments; its real IBM Cloud region prefix
                # is embedded in the environment_code (e.g. "eu-gb-dev01-cloud-zone1"
                # → "eu-gb"), so we resolve the effective region name before matching.
                if tier_name == "development":
                    # The effective region is the YAML key unless it's the sentinel
                    # value "cloud", in which case we'll determine it per-zone when
                    # we read env_code.  To filter early, we check whether ANY
                    # env_code in this region block starts with an allowed prefix.
                    # For non-"cloud" keys this is a direct comparison.
                    if region_name != "cloud" and region_name not in _dev_regions:
                        continue
                    # For "cloud" keys the check is deferred to zone level below.
                for _loc_name, loc_data in (region_data.get("locations") or {}).items():
                    # ── Regional entries (DCMS-style: location has a "regional" key) ─
                    regional = (loc_data.get("regional") or {}) if isinstance(loc_data, dict) else {}
                    if regional:
                        env_code = (regional.get("environment_code") or "").strip()
                        clusters = regional.get("clusters") or []
                        if env_code and clusters:
                            if env_code not in result[bucket]:
                                result[bucket][env_code] = []
                            for cluster in clusters:
                                label = f"{env_code}-{cluster}"
                                if label not in result[bucket][env_code]:
                                    # Store as (compact_label, cluster_name) tuple
                                    result[bucket][env_code].append((label, cluster))

                    # ── Zonal entries (undercloud-style: location has "zones") ────
                    for zone_name, zone_data in ((loc_data.get("zones") or {}) if isinstance(loc_data, dict) else {}).items():
                        if not isinstance(zone_data, dict):
                            continue
                        env_code = (zone_data.get("environment_code") or "").strip()
                        clusters = zone_data.get("clusters") or []
                        if not env_code or not clusters:
                            continue
                        # Use the IBM Cloud region from the YAML path (region_name).
                        # For the special "cloud" region key (over-the-cloud envs)
                        # fall back to _region_prefix(env_code).
                        ibm_region = (
                            region_name
                            if region_name != "cloud"
                            else _region_prefix(env_code)
                        )
                        # For development "cloud" region keys, apply the deferred
                        # region filter now that ibm_region is resolved from env_code.
                        if tier_name == "development" and region_name == "cloud":
                            if ibm_region not in _dev_regions:
                                continue
                        if env_code not in result[bucket]:
                            result[bucket][env_code] = []
                        for cluster in clusters:
                            # Zone label: <region>-<zone_name>-<cluster>
                            # zone_name is the YAML key (e.g. "zone1", "zone2")
                            # producing names like: us-south-zone1-undercloud
                            label = f"{ibm_region}-{zone_name}-{cluster}"
                            if label not in [entry[0] for entry in result[bucket][env_code]]:
                                # Store as (compact_label, cluster_name) tuple so callers
                                # can access the cluster independently of the zone label.
                                result[bucket][env_code].append((label, cluster))

    return result


def get_secret_targets(
    env: str,
    deployment_targets_config: dict[str, Any],
    zone_map: ZoneMapT,
) -> list[dict[str, str | None]]:
    """
    Resolve the list of provisioning targets for a given environment, applying
    the ``targets``, ``type``, ``exclude``, and ``override_size`` rules from
    the deployment_targets config section.

    Args:
        env:                       "integration", "staging", or "production".
        deployment_targets_config: the dict under deployment_targets.CD.<env>
                                   from the onboarding.yaml.
        zone_map:                  the full zone map built by
                                   get_zone_map_from_env_yaml().

    Zone-map structure (keyed by env_code, values are (compact_label, cluster) tuples):
        {
          "<env_code>": [("<compact_label>", "<cluster>"), ...],
          ...
        }
        For DCMS  env_code = "us-east-int01-cloud-regional"
        For UC    env_code = "us-south-int01-dal10-zone1"

    Exclude semantics (depend on type):
        type=regional  → exclude values are SHORT region prefixes (e.g. "us-east",
                         "eu-gb").  All env_code keys whose _region_prefix matches
                         are dropped — effectively skipping the entire region.
        type=zonal     → exclude values are FULL zone labels (env_code-cluster,
                         e.g. "us-east-int01-wdc04-zone1-undercloud").  Only that
                         specific zone entry is skipped; other zones in the same
                         env_code key are kept.

    Returns:
        A list of dicts, one per provisioning target:
          {
            "region":  str,        # env_code key (full, e.g. "us-east-int01-cloud-regional")
            "zone":    str | None, # compact zone label; None for regional targets
            "cluster": str | None, # cluster name extracted from zone label; None for regional
            "size":    str,        # resolved size (override or default)
          }
    """
    env_zones = zone_map.get(env, {})
    if not env_zones:
        return []

    targets_cfg   = deployment_targets_config.get("targets", "all")
    secret_type   = deployment_targets_config.get("type", "zonal")
    default_size  = deployment_targets_config.get("default_size", "small")
    exclude_list  = [str(e).strip() for e in (deployment_targets_config.get("exclude") or [])]
    override_list = deployment_targets_config.get("override_size", []) or []

    import sys as _sys  # local import to avoid polluting module namespace

    # Build override lookup: target_name → size
    overrides: dict[str, str] = {}
    for entry in override_list:
        if isinstance(entry, dict) and "target" in entry and "size" in entry:
            overrides[entry["target"]] = entry["size"]

    # ── Determine which env_code keys (regions) to include ───────────────────
    if targets_cfg == "all":
        included_regions = list(env_zones.keys())
    elif isinstance(targets_cfg, list):
        if not targets_cfg:
            print(
                f"WARNING: deployment_targets.CD.{env}.targets is an empty list — "
                f"no secrets/triggers will be provisioned for {env}.",
                file=_sys.stderr,
            )
        included_regions = []
        for r in targets_cfg:
            if r in env_zones:
                included_regions.append(r)
            else:
                print(
                    f"WARNING: targets entry '{r}' for env={env} not found in "
                    f"env-code YAML — skipping.",
                    file=_sys.stderr,
                )
    else:
        if targets_cfg in env_zones:
            included_regions = [targets_cfg]
        else:
            print(
                f"WARNING: targets value '{targets_cfg}' for env={env} not found in "
                f"env-code YAML — no secrets/triggers will be provisioned.",
                file=_sys.stderr,
            )
            included_regions = []

    # ── Build helper sets for validation and exclude resolution ──────────────
    all_region_prefixes = {_region_prefix(r) for r in env_zones}

    # For zonal excludes: teams may write env_code-cluster (the "full" old-style
    # label, e.g. "us-south-int01-dal10-zone2-undercloud") or the compact label
    # (e.g. "us-south-zone2-undercloud").  Build a lookup from both to the compact
    # label stored in zone_map so either format is accepted.
    # zone_map values are now (compact_label, cluster) tuples.
    _env_code_cluster_to_compact: dict[str, str] = {}
    for ec, zone_tuples in env_zones.items():
        for compact, cluster in zone_tuples:
            # Map the compact label to itself (direct match)
            _env_code_cluster_to_compact[compact] = compact
            # Also accept the old-style env_code-cluster form.
            # ec convention: r1-r2-envname-dc-zonename  (always 5 segments for undercloud)
            # compact format: r1-r2-zonename-cluster
            ec_parts = ec.split("-")
            if len(ec_parts) >= 5:
                _env_code_cluster_to_compact[f"{ec}-{cluster}"] = compact

    # ── Apply excludes ────────────────────────────────────────────────────────
    excluded_zone_labels: set[str] = set()

    if secret_type == "regional":
        excluded_prefixes = set(exclude_list)
        # Validate: warn if any exclude prefix is not a known region prefix
        for excl in excluded_prefixes:
            if excl not in all_region_prefixes:
                print(
                    f"WARNING: exclude entry '{excl}' for env={env} (type=regional) "
                    f"does not match any known region prefix. "
                    f"Known prefixes: {sorted(all_region_prefixes)}",
                    file=_sys.stderr,
                )
        # Filter: drop env_code keys whose short prefix is excluded
        included_regions = [
            r for r in included_regions
            if _region_prefix(r) not in excluded_prefixes
        ]
    else:  # zonal
        for excl in exclude_list:
            resolved = _env_code_cluster_to_compact.get(excl)
            if resolved:
                excluded_zone_labels.add(resolved)
            else:
                print(
                    f"WARNING: exclude entry '{excl}' for env={env} (type=zonal) "
                    f"does not match any known zone — it will have no effect. "
                    f"Use env_code-cluster format (e.g. us-south-int01-dal10-zone1-undercloud) "
                    f"or the compact label (e.g. us-south-zone1-undercloud).",
                    file=_sys.stderr,
                )

    if not included_regions and exclude_list:
        print(
            f"WARNING: After applying excludes, no regions remain for env={env}. "
            f"Check your exclude list: {exclude_list}",
            file=_sys.stderr,
        )

    # ── Build result list ─────────────────────────────────────────────────────
    results: list[dict[str, str | None]] = []

    if secret_type == "regional":
        for region in included_regions:
            size = overrides.get(_region_prefix(region), overrides.get(region, default_size))
            # For regional, emit one entry per (region, cluster) tuple so the
            # caller can decide whether to include the cluster name based on
            # unique_per_cluster.
            for compact, cluster in env_zones.get(region, []):
                results.append({
                    "region":  region,
                    "zone":    None,
                    "cluster": cluster,
                    "size":    size,
                })

    else:  # zonal
        for region in included_regions:
            for compact, cluster in env_zones.get(region, []):
                if compact in excluded_zone_labels:
                    continue
                size = overrides.get(compact, overrides.get(region, default_size))
                results.append({
                    "region":  region,
                    "zone":    compact,
                    "cluster": cluster,
                    "size":    size,
                })

    return results


def _region_prefix(env_code: str) -> str:
    """
    Extract the short two-segment region prefix from an env_code.

        "us-east-int01-cloud-regional"           → "us-east"
        "us-east-int01-cloud-regional-roks-goal" → "us-east"
        "eu-de-prod01-cloud-regional"            → "eu-de"
    """
    parts = env_code.split("-")
    return "-".join(parts[:2]) if len(parts) >= 2 else env_code


def _deployment_id(env_code: str) -> str:
    """
    Extract the deployment ID (third hyphen-segment) from an env_code.

        "us-east-int01-cloud-regional"  → "int01"
        "eu-gb-prod01-cloud-regional"   → "prod01"
        "eu-gb-dev01-cloud-zone1"       → "dev01"
    """
    parts = env_code.split("-")
    return parts[2] if len(parts) >= 3 else env_code


def build_secret_name(
    secret_group: str,
    secret_name: str,
    secret_type: str,
    region: str | None = None,
    zone: str | None = None,
    cluster: str | None = None,
    unique_per_cluster: bool = False,
) -> str:
    """
    Build the full secret label according to the naming convention.

    unique_per_cluster=False (default):
        global:   <secret_group>-<name>
        regional: <secret_group>-<short_region>-<deployment_id>-<name>
        zonal:    <secret_group>-<environment_code>-<name>

    unique_per_cluster=True:
        global:   <secret_group>-<name>   (cluster has no meaning for global)
        regional: <secret_group>-<short_region>-<deployment_id>-<cluster>-<name>
        zonal:    <secret_group>-<environment_code>-<cluster>-<name>

    For regional secrets:
        <short_region>  = first two hyphen-segments of env_code
                          e.g. "us-east-int01-cloud-regional" → "us-east"
        <deployment_id> = third hyphen-segment of env_code
                          e.g. "us-east-int01-cloud-regional" → "int01"

    For zonal secrets:
        <environment_code> = the full ``region`` argument (env_code from YAML),
                             e.g. "eu-gb-dev01-cloud-zone1"
        The ``zone`` (compact label) is only used to carry the cluster name
        to this function via get_secret_targets(); it is not included in the
        secret name itself.

    Args:
        secret_group:       e.g. "sg-uuc-dcms"
        secret_name:        bare secret name without any prefix
        secret_type:        "global", "regional", or "zonal"
        region:             full env_code (required for regional/zonal)
        zone:               compact zone label (required for zonal; used to
                            extract cluster when cluster is not supplied)
        cluster:            cluster name, already split from the zone label
                            by get_secret_targets()
        unique_per_cluster: if True, include the cluster name in the secret label

    Examples (unique_per_cluster=False):
        regional: sg-uuc-dcms-us-east-int01-my-secret
        zonal:    sg-uuc-core-services-eu-gb-dev01-cloud-zone1-my-secret
        global:   sg-uuc-myteam-my-secret

    Examples (unique_per_cluster=True):
        regional: sg-uuc-dcms-us-east-int01-roks-goal-my-secret
        zonal:    sg-uuc-core-services-eu-gb-dev01-cloud-zone1-undercloud-my-secret
        global:   sg-uuc-myteam-my-secret
    """
    secret_type = (secret_type or "global").lower()

    if secret_type == "zonal":
        if not region:
            raise ValueError(f"region (environment_code) is required for zonal secret: {secret_name}")
        # Use the full environment_code directly as the prefix.
        # e.g. region="eu-gb-dev01-cloud-zone1", cluster="undercloud"
        #   → sg-uuc-team-eu-gb-dev01-cloud-zone1-undercloud-my-secret  (unique_per_cluster=True)
        #   → sg-uuc-team-eu-gb-dev01-cloud-zone1-my-secret              (unique_per_cluster=False)
        if unique_per_cluster and cluster:
            full_name = f"{secret_group}-{region}-{cluster}-{secret_name}"
        else:
            full_name = f"{secret_group}-{region}-{secret_name}"

    elif secret_type == "regional":
        if not region:
            raise ValueError(f"region is required for regional secret: {secret_name}")
        short_region = _region_prefix(region)
        deployment_id = _deployment_id(region)
        if unique_per_cluster and cluster:
            full_name = f"{secret_group}-{short_region}-{deployment_id}-{cluster}-{secret_name}"
        else:
            full_name = f"{secret_group}-{short_region}-{deployment_id}-{secret_name}"

    else:  # global
        full_name = f"{secret_group}-{secret_name}"

    return full_name


# ---------------------------------------------------------------------------
# CLI entry-point
# ---------------------------------------------------------------------------

def _cli() -> None:
    """
    Command-line interface for use from shell scripts.

    Modes:
      get-targets  → print JSON list of {region, zone, cluster, size} provisioning targets.
      build-name   → print a single secret label string.
    """
    parser = argparse.ArgumentParser(
        description="VPC Zone/Region Map Utilities for Secret Provisioning"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # ── get-targets ──────────────────────────────────────────────────────────
    p_targets = sub.add_parser(
        "get-targets",
        help="Resolve provisioning targets for an environment.",
    )
    p_targets.add_argument("--env", required=True,
                           choices=["integration", "staging", "production", "development"],
                           help="Target environment")
    p_targets.add_argument("--env-yaml-source", required=True,
                           help="Path or https:// URL to dcms_environment_code.yaml "
                                "or undercloud_environment_code.yaml")
    p_targets.add_argument("--deployment-targets-json", required=True,
                           help="JSON string of the deployment_targets.CD.<env> config block")
    p_targets.add_argument("--github-token",
                           default=os.environ.get("GITHUB_TOKEN") or os.environ.get("GHE_TOKEN"),
                           help="GitHub Enterprise token (needed when --env-yaml-source is a URL)")
    p_targets.add_argument("--include-development",
                           action="store_true", default=False,
                           help="Include the development tier when building the zone map. "
                                "Intended for temporary use only — development environments "
                                "are not provisioned by the automated pipeline by default.")
    p_targets.add_argument("--development-deployments",
                           default=None,
                           help="Comma-separated deployment IDs to include from the development "
                                "tier (e.g. 'dev01,dev02').  Defaults to 'dev01,dev02' (OTC1+OTC2) "
                                "when --include-development is set.  Has no effect unless "
                                "--include-development is also passed.")
    p_targets.add_argument("--development-regions",
                           default=None,
                           help="Comma-separated IBM Cloud region names to include from the "
                                "development tier (e.g. 'eu-gb').  Defaults to 'eu-gb' (OTC1+OTC2 "
                                "are both in eu-gb).  Has no effect unless --include-development "
                                "is also passed.")

    # ── build-name ───────────────────────────────────────────────────────────
    p_name = sub.add_parser(
        "build-name",
        help="Build a single secret label string.",
    )
    p_name.add_argument("--secret-group",        required=True)
    p_name.add_argument("--secret-name",         required=True)
    p_name.add_argument("--secret-type",         required=True, choices=["zonal", "regional", "global"])
    p_name.add_argument("--region",              default=None)
    p_name.add_argument("--zone",                default=None)
    p_name.add_argument("--cluster",             default=None,
                        help="Cluster name (required when --unique-per-cluster is set)")
    p_name.add_argument("--unique-per-cluster",  action="store_true", default=False,
                        help="Include cluster name in the secret label")

    args = parser.parse_args()

    # ── dispatch ─────────────────────────────────────────────────────────────
    if args.command == "build-name":
        try:
            label = build_secret_name(
                secret_group=args.secret_group,
                secret_name=args.secret_name,
                secret_type=args.secret_type,
                region=args.region,
                zone=args.zone,
                cluster=args.cluster,
                unique_per_cluster=args.unique_per_cluster,
            )
            print(label)
        except ValueError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            sys.exit(1)

    elif args.command == "get-targets":
        token = getattr(args, "github_token", None)
        include_dev = getattr(args, "include_development", False)
        if args.env == "development" and not include_dev:
            print(
                "ERROR: --env development requires --include-development to be set. "
                "Development environments are not provisioned by default.",
                file=sys.stderr,
            )
            sys.exit(1)
        # Parse --development-deployments (comma-separated string → set).
        # None means "use default" (dev01,dev02); an explicit value overrides.
        dev_deployments: set[str] | None = None
        raw_dev_deps = getattr(args, "development_deployments", None)
        if raw_dev_deps:
            dev_deployments = {d.strip() for d in raw_dev_deps.split(",") if d.strip()}
        # Parse --development-regions (comma-separated string → set).
        # None means "use default" (eu-gb); an explicit value overrides.
        dev_regions: set[str] | None = None
        raw_dev_regs = getattr(args, "development_regions", None)
        if raw_dev_regs:
            dev_regions = {r.strip() for r in raw_dev_regs.split(",") if r.strip()}
        try:
            zone_map = get_zone_map_from_env_yaml(
                args.env_yaml_source, token,
                include_development=include_dev,
                development_deployments=dev_deployments,
                development_regions=dev_regions,
            )
        except RuntimeError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            sys.exit(1)

        try:
            dt_config = json.loads(args.deployment_targets_json)
        except json.JSONDecodeError as exc:
            print(f"ERROR: Invalid JSON for --deployment-targets-json: {exc}", file=sys.stderr)
            sys.exit(1)

        targets = get_secret_targets(args.env, dt_config, zone_map)
        print(json.dumps(targets, indent=2))


if __name__ == "__main__":
    _cli()
