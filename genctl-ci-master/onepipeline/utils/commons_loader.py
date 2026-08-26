#!/usr/bin/env python3
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

"""
commons_loader.py — Shared utility for loading team commons.yaml

Every service onboarding file lives alongside a commons.yaml in the same
directory (team branch root).  This module provides:

  locate_commons(ref_path)         → Path | None
  load_commons(ref_path)           → dict  (raises CommonsNotFoundError if missing)
  get_commons_field(ref_path, key) → any   (raises CommonsNotFoundError / KeyError)

Import usage (Python):
    from commons_loader import load_commons, CommonsNotFoundError

CLI usage (bash inline):
    python3 commons_loader.py <service_yaml_path> <field>
    python3 commons_loader.py <service_yaml_path> service_fid_dev
    python3 commons_loader.py <service_yaml_path> --json        # dump full commons as JSON

Exit codes (CLI):
    0  — success, value printed to stdout
    1  — commons.yaml not found or field missing
    2  — YAML parse error
"""

import sys
import os
import json
from pathlib import Path
from typing import Any, Optional

try:
    import yaml
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyyaml", "--quiet"])
    import yaml


# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

class CommonsNotFoundError(FileNotFoundError):
    """Raised when commons.yaml cannot be found next to the service file."""

    def __init__(self, search_dir: str):
        self.search_dir = search_dir
        super().__init__(
            f"commons.yaml not found in '{search_dir}'. "
            f"Every team branch must contain a commons.yaml at its root. "
            f"See the reference template in the uuc-service-cicd-onboarding repository."
        )


class CommonsParseError(ValueError):
    """Raised when commons.yaml exists but cannot be parsed as YAML."""


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_COMMONS_NAMES = ("commons.yaml", "commons.yml")


def _resolve_search_dir(ref_path: str) -> Path:
    """Return the directory to search for commons.yaml.

    ref_path may be:
      - a path to a service onboarding YAML file  → use its parent directory
      - a path to a directory                      → use that directory
    """
    p = Path(ref_path).resolve()
    return p.parent if p.is_file() else p


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def locate_commons(ref_path: str) -> Optional[Path]:
    """Return the Path to commons.yaml if it exists, else None.

    Args:
        ref_path: Path to a service onboarding YAML file or to the branch
                  root directory.  commons.yaml is expected in the same
                  directory as the service file.
    """
    search_dir = _resolve_search_dir(ref_path)
    for name in _COMMONS_NAMES:
        candidate = search_dir / name
        if candidate.is_file():
            return candidate
    return None


def load_commons(ref_path: str) -> dict:
    """Load and return the commons.yaml as a dict.

    Args:
        ref_path: Path to a service onboarding YAML file or branch root.

    Raises:
        CommonsNotFoundError: commons.yaml is not present.
        CommonsParseError:    commons.yaml exists but is not valid YAML.
    """
    search_dir = _resolve_search_dir(ref_path)
    commons_path = locate_commons(ref_path)

    if commons_path is None:
        raise CommonsNotFoundError(str(search_dir))

    try:
        with open(commons_path, "r") as fh:
            data = yaml.safe_load(fh)
    except yaml.YAMLError as exc:
        raise CommonsParseError(
            f"Failed to parse '{commons_path}': {exc}"
        ) from exc

    if data is None:
        data = {}
    if not isinstance(data, dict):
        raise CommonsParseError(
            f"'{commons_path}' must contain a YAML mapping at the top level."
        )

    return data


def get_commons_field(ref_path: str, key: str, default: Any = None) -> Any:
    """Return the value of *key* from commons.yaml, or *default* if absent.

    Args:
        ref_path: Path to a service onboarding YAML file or branch root.
        key:      Top-level key in commons.yaml.
        default:  Returned when the key is not present (default: None).

    Raises:
        CommonsNotFoundError: commons.yaml is not present.
        CommonsParseError:    commons.yaml exists but is not valid YAML.
    """
    data = load_commons(ref_path)
    return data.get(key, default)


def merge_with_commons(service_data: dict, ref_path: str) -> dict:
    """Return a merged dict: commons fields + service fields.

    Service-specific fields take priority over commons fields when both
    define the same key — but by design the two sets are disjoint.
    commons.yaml is loaded from the directory of ref_path.

    This is the canonical way for merge scripts to obtain a complete
    view of a service's configuration without duplicating loading logic.

    Args:
        service_data: Already-loaded service onboarding dict.
        ref_path:     Path to the service onboarding YAML file (used to
                      locate commons.yaml).

    Raises:
        CommonsNotFoundError: commons.yaml is not present.
        CommonsParseError:    commons.yaml is not valid YAML.
    """
    commons_data = load_commons(ref_path)
    merged = dict(commons_data)
    merged.update(service_data)
    return merged


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def _cli():
    if len(sys.argv) < 2:
        print(
            "Usage: commons_loader.py <service_yaml_path> [<field>|--json]",
            file=sys.stderr,
        )
        sys.exit(1)

    ref_path = sys.argv[1]

    try:
        data = load_commons(ref_path)
    except CommonsNotFoundError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
    except CommonsParseError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(2)

    if len(sys.argv) == 2 or (len(sys.argv) == 3 and sys.argv[2] == "--json"):
        # Dump the full commons as JSON for easy shell consumption
        print(json.dumps(data, default=str))
        sys.exit(0)

    field = sys.argv[2]
    if field not in data:
        print(f"ERROR: field '{field}' not found in commons.yaml", file=sys.stderr)
        sys.exit(1)

    value = data[field]
    # For scalar values print directly; for complex types emit JSON
    if isinstance(value, (dict, list)):
        print(json.dumps(value, default=str))
    else:
        print(value)
    sys.exit(0)


if __name__ == "__main__":
    _cli()
