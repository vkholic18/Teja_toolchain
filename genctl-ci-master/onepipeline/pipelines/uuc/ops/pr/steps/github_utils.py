#!/usr/bin/env python3

"""
Shared GitHub API utilities for the UUC onboarding validation scripts.

Provides two functions used by both validate_mandatory_files.py and
validate_optional_files.py:

  get_file_from_github()      — fetch file metadata + content via Contents API
  get_file_mode_from_tree()   — resolve Unix file mode via Git Trees API
                                (needed because the Contents API does not
                                 always return the mode field on GHE)

Both functions accept a callable `log_debug` so callers can plug in their own
debug logger without this module importing anything from those scripts.
"""

from typing import Callable, Dict, Optional
import requests


_GH_ACCEPT = "application/vnd.github.v3+json"


def get_file_mode_from_tree(
    token: str,
    host: str,
    owner: str,
    repo: str,
    branch: str,
    file_path: str,
    log_debug: Callable[[str], None] = lambda _: None,
) -> Optional[str]:
    """
    Return the Unix mode string (e.g. ``"100755"``) for *file_path* on
    *branch* by walking the Git Trees API.  Returns ``None`` when the file
    is not found or any API call fails.

    Three sequential API calls are required:
      1. GET /git/ref/heads/{branch}     → commit SHA
      2. GET /git/commits/{sha}          → tree SHA
      3. GET /git/trees/{sha}?recursive=1 → walk for the file entry
    """
    headers = {
        "Authorization": f"token {token}",
        "Accept": _GH_ACCEPT,
    }
    base = f"https://{host}/api/v3/repos/{owner}/{repo}"

    try:
        # Step 1 — branch ref → commit SHA
        ref_url = f"{base}/git/ref/heads/{branch}"
        log_debug(f"Fetching branch ref: {ref_url}")
        ref_resp = requests.get(ref_url, headers=headers, timeout=30)
        if ref_resp.status_code != 200:
            log_debug(f"Failed to get branch ref: {ref_resp.status_code}")
            return None
        commit_sha = ref_resp.json()["object"]["sha"]
        log_debug(f"Branch commit SHA: {commit_sha}")

        # Step 2 — commit → tree SHA
        commit_url = f"{base}/git/commits/{commit_sha}"
        log_debug(f"Fetching commit: {commit_url}")
        commit_resp = requests.get(commit_url, headers=headers, timeout=30)
        if commit_resp.status_code != 200:
            log_debug(f"Failed to get commit: {commit_resp.status_code}")
            return None
        tree_sha = commit_resp.json()["tree"]["sha"]
        log_debug(f"Tree SHA: {tree_sha}")

        # Step 3 — recursive tree walk
        tree_url = f"{base}/git/trees/{tree_sha}?recursive=1"
        log_debug(f"Fetching tree: {tree_url}")
        tree_resp = requests.get(tree_url, headers=headers, timeout=30)
        if tree_resp.status_code != 200:
            log_debug(f"Failed to get tree: {tree_resp.status_code}")
            return None

        for item in tree_resp.json().get("tree", []):
            if item["path"] == file_path:
                mode = item.get("mode", "")
                log_debug(f"Found file in tree with mode: {mode}")
                return mode

        log_debug(f"File not found in tree: {file_path}")
        return None

    except Exception as exc:
        log_debug(f"Error getting file mode from tree: {exc}")
        return None


def get_file_from_github(
    token: str,
    host: str,
    owner: str,
    repo: str,
    branch: str,
    file_path: str,
    log_debug: Callable[[str], None] = lambda _: None,
) -> Optional[Dict]:
    """
    Fetch file metadata (name, size, mode, content …) from the GitHub
    Contents API.  Returns the parsed JSON dict on HTTP 200, ``None`` on
    404 or any error.

    If the Contents API response omits the ``mode`` field (common on GHE),
    the function automatically falls back to :func:`get_file_mode_from_tree`
    and injects the result into the returned dict.
    """
    headers = {
        "Authorization": f"token {token}",
        "Accept": _GH_ACCEPT,
    }
    api_url = (
        f"https://{host}/api/v3/repos/{owner}/{repo}"
        f"/contents/{file_path}?ref={branch}"
    )
    log_debug(f"Fetching file from: {api_url}")

    try:
        response = requests.get(api_url, headers=headers, timeout=30)

        if response.status_code == 200:
            file_info = response.json()
            log_debug(f"GitHub API response keys: {list(file_info.keys())}")
            log_debug(f"File mode from contents API: {file_info.get('mode', 'not present')}")

            # GHE sometimes omits mode — fall back to the tree API
            if not file_info.get("mode"):
                log_debug("Mode not in contents API response, fetching from tree API...")
                mode = get_file_mode_from_tree(
                    token, host, owner, repo, branch, file_path, log_debug
                )
                if mode:
                    file_info["mode"] = mode
                    log_debug(f"File mode from tree API: {mode}")

            return file_info

        if response.status_code == 404:
            log_debug(f"File not found: {file_path}")
            return None

        log_debug(f"GitHub API returned status {response.status_code}: {response.text}")
        return None

    except requests.exceptions.RequestException as exc:
        log_debug(f"Request error: {exc}")
        return None
