#!/usr/bin/env python3
"""
Tests for github_utils.py

Covers get_file_from_github and get_file_mode_from_tree — both the happy
path (HTTP 200 at every step) and multiple failure modes (404, network
error, missing fields, etc.).

All HTTP calls are mocked via unittest.mock.patch so no real network
traffic is made.
"""

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch, call

import pytest

STEPS_DIR = Path(__file__).resolve().parents[1] / "steps"
sys.path.insert(0, str(STEPS_DIR))

from github_utils import get_file_from_github, get_file_mode_from_tree  # noqa: E402


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

TOKEN = "fake-test-token"
HOST = "github.ibm.com"
OWNER = "myorg"
REPO = "my-repo"
BRANCH = "main"
FILE_PATH = "hack/ci/build.sh"
NOOP_LOG = lambda _: None  # no-op logger


def _mock_response(status_code: int, json_data=None):
    resp = MagicMock()
    resp.status_code = status_code
    resp.json.return_value = json_data or {}
    resp.text = str(json_data)
    return resp


# ---------------------------------------------------------------------------
# get_file_mode_from_tree
# ---------------------------------------------------------------------------

class TestGetFileModeFromTree:
    BASE = f"https://{HOST}/api/v3/repos/{OWNER}/{REPO}"

    def _make_responses(self, mode="100755"):
        ref_resp = _mock_response(200, {"object": {"sha": "commit-sha-abc"}})
        commit_resp = _mock_response(200, {"tree": {"sha": "tree-sha-xyz"}})
        tree_resp = _mock_response(200, {
            "tree": [
                {"path": FILE_PATH, "mode": mode},
                {"path": "other/file.txt", "mode": "100644"},
            ]
        })
        return [ref_resp, commit_resp, tree_resp]

    @patch("github_utils.requests.get")
    def test_returns_mode_for_existing_file(self, mock_get):
        mock_get.side_effect = self._make_responses("100755")
        result = get_file_mode_from_tree(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        assert result == "100755"

    @patch("github_utils.requests.get")
    def test_returns_non_executable_mode(self, mock_get):
        mock_get.side_effect = self._make_responses("100644")
        result = get_file_mode_from_tree(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        assert result == "100644"

    @patch("github_utils.requests.get")
    def test_returns_none_when_branch_ref_fails(self, mock_get):
        mock_get.return_value = _mock_response(404)
        result = get_file_mode_from_tree(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        assert result is None

    @patch("github_utils.requests.get")
    def test_returns_none_when_commit_fetch_fails(self, mock_get):
        ref_resp = _mock_response(200, {"object": {"sha": "commit-sha"}})
        commit_resp = _mock_response(500)
        mock_get.side_effect = [ref_resp, commit_resp]
        result = get_file_mode_from_tree(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        assert result is None

    @patch("github_utils.requests.get")
    def test_returns_none_when_tree_fetch_fails(self, mock_get):
        ref_resp = _mock_response(200, {"object": {"sha": "commit-sha"}})
        commit_resp = _mock_response(200, {"tree": {"sha": "tree-sha"}})
        tree_resp = _mock_response(404)
        mock_get.side_effect = [ref_resp, commit_resp, tree_resp]
        result = get_file_mode_from_tree(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        assert result is None

    @patch("github_utils.requests.get")
    def test_returns_none_when_file_not_in_tree(self, mock_get):
        ref_resp = _mock_response(200, {"object": {"sha": "commit-sha"}})
        commit_resp = _mock_response(200, {"tree": {"sha": "tree-sha"}})
        tree_resp = _mock_response(200, {"tree": [{"path": "other/file.py", "mode": "100644"}]})
        mock_get.side_effect = [ref_resp, commit_resp, tree_resp]
        result = get_file_mode_from_tree(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        assert result is None

    @patch("github_utils.requests.get")
    def test_returns_none_on_network_error(self, mock_get):
        import requests as req
        mock_get.side_effect = req.exceptions.ConnectionError("connection refused")
        result = get_file_mode_from_tree(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        assert result is None

    @patch("github_utils.requests.get")
    def test_calls_correct_api_urls(self, mock_get):
        mock_get.side_effect = self._make_responses()
        get_file_mode_from_tree(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        called_urls = [c.args[0] for c in mock_get.call_args_list]
        assert any(f"/git/ref/heads/{BRANCH}" in url for url in called_urls)
        assert any("/git/commits/" in url for url in called_urls)
        assert any("/git/trees/" in url for url in called_urls)

    @patch("github_utils.requests.get")
    def test_uses_correct_auth_header(self, mock_get):
        mock_get.side_effect = self._make_responses()
        get_file_mode_from_tree(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        headers = mock_get.call_args_list[0].kwargs.get("headers", {})
        assert headers.get("Authorization") == f"token {TOKEN}"

    @patch("github_utils.requests.get")
    def test_debug_logger_is_called(self, mock_get):
        mock_get.side_effect = self._make_responses()
        log_calls = []
        get_file_mode_from_tree(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH,
                                 log_debug=lambda m: log_calls.append(m))
        assert len(log_calls) > 0


# ---------------------------------------------------------------------------
# get_file_from_github
# ---------------------------------------------------------------------------

class TestGetFileFromGithub:
    def _file_resp(self, mode="100755"):
        return _mock_response(200, {
            "name": "build.sh",
            "size": 150,
            "mode": mode,
            "content": "aGVsbG8=",  # base64 "hello"
        })

    @patch("github_utils.requests.get")
    def test_returns_file_info_on_200(self, mock_get):
        mock_get.return_value = self._file_resp()
        result = get_file_from_github(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        assert result is not None
        assert result["name"] == "build.sh"
        assert result["size"] == 150

    @patch("github_utils.requests.get")
    def test_returns_none_on_404(self, mock_get):
        mock_get.return_value = _mock_response(404)
        result = get_file_from_github(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        assert result is None

    @patch("github_utils.requests.get")
    def test_returns_none_on_500(self, mock_get):
        mock_get.return_value = _mock_response(500, {})
        result = get_file_from_github(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        assert result is None

    @patch("github_utils.requests.get")
    def test_returns_none_on_network_error(self, mock_get):
        import requests as req
        mock_get.side_effect = req.exceptions.Timeout("timed out")
        result = get_file_from_github(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        assert result is None

    @patch("github_utils.requests.get")
    def test_includes_mode_when_present(self, mock_get):
        mock_get.return_value = self._file_resp(mode="100755")
        result = get_file_from_github(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        assert result["mode"] == "100755"

    @patch("github_utils.get_file_mode_from_tree")
    @patch("github_utils.requests.get")
    def test_falls_back_to_tree_api_when_mode_missing(self, mock_get, mock_tree):
        """When the contents API omits mode, the tree fallback is invoked."""
        mock_get.return_value = _mock_response(200, {
            "name": "build.sh",
            "size": 100,
            # no 'mode' key
        })
        mock_tree.return_value = "100755"
        result = get_file_from_github(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        assert result["mode"] == "100755"
        mock_tree.assert_called_once()

    @patch("github_utils.get_file_mode_from_tree")
    @patch("github_utils.requests.get")
    def test_no_fallback_when_mode_present(self, mock_get, mock_tree):
        """When the contents API provides mode, tree API should NOT be called."""
        mock_get.return_value = self._file_resp(mode="100644")
        result = get_file_from_github(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        mock_tree.assert_not_called()
        assert result["mode"] == "100644"

    @patch("github_utils.requests.get")
    def test_api_url_includes_branch_ref(self, mock_get):
        mock_get.return_value = self._file_resp()
        get_file_from_github(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        called_url = mock_get.call_args.args[0]
        assert f"?ref={BRANCH}" in called_url

    @patch("github_utils.requests.get")
    def test_api_url_includes_file_path(self, mock_get):
        mock_get.return_value = self._file_resp()
        get_file_from_github(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        called_url = mock_get.call_args.args[0]
        assert FILE_PATH in called_url

    @patch("github_utils.requests.get")
    def test_uses_correct_auth_header(self, mock_get):
        mock_get.return_value = self._file_resp()
        get_file_from_github(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH, NOOP_LOG)
        headers = mock_get.call_args.kwargs.get("headers", {})
        assert headers.get("Authorization") == f"token {TOKEN}"

    @patch("github_utils.requests.get")
    def test_default_log_debug_does_not_raise(self, mock_get):
        """Calling without explicit log_debug (uses default no-op lambda) must not crash."""
        mock_get.return_value = self._file_resp()
        result = get_file_from_github(TOKEN, HOST, OWNER, REPO, BRANCH, FILE_PATH)
        assert result is not None

if __name__ == '__main__':
    pytest.main([__file__, '-v'])
