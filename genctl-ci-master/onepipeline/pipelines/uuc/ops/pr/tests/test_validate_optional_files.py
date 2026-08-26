#!/usr/bin/env python3
"""
Tests for validate_optional_files.py

Covers OptionalFilesValidator: parse_github_url, check_file_executable,
check_file_empty, validate_file, and validate_optional_files — with both
positive (happy-path) and negative (error/edge-case) scenarios.

All GitHub / filesystem I/O is mocked so no network calls are made.
"""

import os
import sys
import tempfile
import textwrap
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

STEPS_DIR = Path(__file__).resolve().parents[1] / "steps"
sys.path.insert(0, str(STEPS_DIR))

# Provide a fake token before importing so the constructor does not sys.exit
os.environ.setdefault("GH_TOKEN", "fake-token-for-tests")

from validate_optional_files import OptionalFilesValidator  # noqa: E402


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture()
def validator():
    """Return a fresh OptionalFilesValidator with debug disabled."""
    with patch.dict(os.environ, {"GH_TOKEN": "fake-token"}):
        return OptionalFilesValidator(debug=False)


@pytest.fixture()
def validator_debug():
    """Return a fresh OptionalFilesValidator with debug enabled."""
    with patch.dict(os.environ, {"GH_TOKEN": "fake-token"}):
        return OptionalFilesValidator(debug=True)


def _write_yaml(tmp_path, content: str) -> str:
    p = tmp_path / "onboarding.yaml"
    p.write_text(textwrap.dedent(content))
    return str(p)


# ---------------------------------------------------------------------------
# parse_github_url
# ---------------------------------------------------------------------------

class TestParseGithubUrl:
    def test_https_url_parsed(self, validator):
        host, owner, repo = validator.parse_github_url(
            "https://github.ibm.com/myorg/my-repo"
        )
        assert host == "github.ibm.com"
        assert owner == "myorg"
        assert repo == "my-repo"

    def test_trailing_slash_stripped(self, validator):
        host, owner, repo = validator.parse_github_url(
            "https://github.ibm.com/myorg/my-repo/"
        )
        assert repo == "my-repo"

    def test_git_suffix_stripped(self, validator):
        _, _, repo = validator.parse_github_url(
            "https://github.ibm.com/myorg/my-repo.git"
        )
        assert repo == "my-repo"

    def test_invalid_url_returns_nones(self, validator):
        host, owner, repo = validator.parse_github_url("not-a-url")
        assert host is None
        assert owner is None
        assert repo is None

    def test_url_with_single_path_part_returns_nones(self, validator):
        host, owner, repo = validator.parse_github_url("https://github.ibm.com/onlyorg")
        assert owner is None


# ---------------------------------------------------------------------------
# check_file_executable
# ---------------------------------------------------------------------------

class TestCheckFileExecutable:
    def test_mode_100755_is_executable(self, validator):
        is_exec, info = validator.check_file_executable({"mode": "100755"})
        assert is_exec is True

    def test_mode_100644_not_executable(self, validator):
        is_exec, _ = validator.check_file_executable({"mode": "100644"})
        assert is_exec is False

    def test_mode_100750_is_executable(self, validator):
        is_exec, _ = validator.check_file_executable({"mode": "100750"})
        assert is_exec is True

    def test_no_mode_sh_extension_inferred_executable(self, validator):
        is_exec, info = validator.check_file_executable({"name": "build.sh"})
        assert is_exec is True
        assert "inferred" in info

    def test_no_mode_non_sh_not_executable(self, validator):
        is_exec, info = validator.check_file_executable({"name": "README.md"})
        assert is_exec is False

    def test_invalid_mode_format(self, validator):
        is_exec, info = validator.check_file_executable({"mode": "BADMODE"})
        assert is_exec is False


# ---------------------------------------------------------------------------
# check_file_empty
# ---------------------------------------------------------------------------

class TestCheckFileEmpty:
    def test_size_zero_is_empty(self, validator):
        assert validator.check_file_empty({"size": 0}) is True

    def test_nonzero_size_is_not_empty(self, validator):
        assert validator.check_file_empty({"size": 100}) is False

    def test_missing_size_defaults_zero(self, validator):
        assert validator.check_file_empty({}) is True


# ---------------------------------------------------------------------------
# validate_file
# ---------------------------------------------------------------------------

class TestValidateFile:
    def test_file_not_found_returns_false(self, validator):
        validator.get_file_from_github = MagicMock(return_value=None)
        result = validator.validate_file(
            "https://github.ibm.com/org/repo",
            "main",
            {"path": "missing.sh", "can_be_empty": False, "executable": True},
            "CI",
        )
        assert result is False
        assert len(validator.errors) >= 1

    def test_invalid_repo_url_returns_false(self, validator):
        result = validator.validate_file(
            "not-a-valid-url",
            "main",
            {"path": "build.sh", "can_be_empty": False, "executable": False},
            "CI",
        )
        assert result is False

    def test_file_exists_non_executable_passes(self, validator):
        validator.get_file_from_github = MagicMock(
            return_value={"name": "README.md", "size": 100, "mode": "100644"}
        )
        result = validator.validate_file(
            "https://github.ibm.com/org/repo",
            "main",
            {"path": "README.md", "can_be_empty": False, "executable": False},
            "docs",
        )
        assert result is True

    def test_file_exists_executable_check_passes(self, validator):
        validator.get_file_from_github = MagicMock(
            return_value={"name": "build.sh", "size": 200, "mode": "100755"}
        )
        result = validator.validate_file(
            "https://github.ibm.com/org/repo",
            "main",
            {"path": "hack/ci/build.sh", "can_be_empty": False, "executable": True},
            "CI",
        )
        assert result is True

    def test_file_not_executable_when_required_returns_false(self, validator):
        validator.get_file_from_github = MagicMock(
            return_value={"name": "build.sh", "size": 200, "mode": "100644"}
        )
        result = validator.validate_file(
            "https://github.ibm.com/org/repo",
            "main",
            {"path": "hack/ci/build.sh", "can_be_empty": False, "executable": True},
            "CI",
        )
        assert result is False

    def test_empty_file_when_not_allowed_returns_false(self, validator):
        validator.get_file_from_github = MagicMock(
            return_value={"name": "build.sh", "size": 0, "mode": "100755"}
        )
        result = validator.validate_file(
            "https://github.ibm.com/org/repo",
            "main",
            {"path": "hack/ci/build.sh", "can_be_empty": False, "executable": True},
            "CI",
        )
        assert result is False

    def test_empty_file_when_allowed_passes(self, validator):
        validator.get_file_from_github = MagicMock(
            return_value={"name": "notes.md", "size": 0, "mode": "100644"}
        )
        result = validator.validate_file(
            "https://github.ibm.com/org/repo",
            "main",
            {"path": "notes.md", "can_be_empty": True, "executable": False},
            "docs",
        )
        assert result is True

    def test_mode_fetched_from_tree_when_missing_in_contents(self, validator):
        validator.get_file_from_github = MagicMock(
            return_value={"name": "build.sh", "size": 200}  # no mode key
        )
        validator.get_file_mode_from_tree = MagicMock(return_value="100755")
        result = validator.validate_file(
            "https://github.ibm.com/org/repo",
            "main",
            {"path": "hack/ci/build.sh", "can_be_empty": False, "executable": True},
            "CI",
        )
        assert result is True


# ---------------------------------------------------------------------------
# validate_optional_files (full YAML flow)
# ---------------------------------------------------------------------------

class TestValidateOptionalFilesFlow:
    def test_no_optional_files_section_returns_true(self, validator, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            cicd_profile: ci_cd
        """)
        result = validator.validate_optional_files(yaml_path)
        assert result is True

    def test_missing_cicd_profile_returns_false(self, validator, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
        """)
        result = validator.validate_optional_files(yaml_path)
        assert result is False

    def test_minimal_skips_mend_group(self, validator, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            cicd_profile: minimal
            optional_files:
              - name: mend
                repo: https://github.ibm.com/org/app
                branch: main
                files:
                  - path: wss.config
                    can_be_empty: false
                    executable: false
        """)
        # No GitHub calls should happen — mend group is skipped for minimal
        result = validator.validate_optional_files(yaml_path)
        assert result is True

    def test_missing_repo_in_category_returns_false(self, validator, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            cicd_profile: ci_cd
            optional_files:
              - name: custom
                branch: main
                files:
                  - path: custom.sh
                    can_be_empty: false
                    executable: true
        """)
        result = validator.validate_optional_files(yaml_path)
        assert result is False

    def test_file_not_found_on_github_returns_false(self, validator, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            cicd_profile: ci_cd
            optional_files:
              - name: custom
                repo: https://github.ibm.com/org/app
                branch: main
                files:
                  - path: custom.sh
                    can_be_empty: false
                    executable: true
        """)
        validator.get_file_from_github = MagicMock(return_value=None)
        result = validator.validate_optional_files(yaml_path)
        assert result is False

    def test_valid_file_returns_true(self, validator, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            cicd_profile: ci_cd
            optional_files:
              - name: custom
                repo: https://github.ibm.com/org/app
                branch: main
                files:
                  - path: custom.sh
                    can_be_empty: false
                    executable: true
        """)
        validator.get_file_from_github = MagicMock(
            return_value={"name": "custom.sh", "size": 150, "mode": "100755"}
        )
        result = validator.validate_optional_files(yaml_path)
        assert result is True

    def test_invalid_yaml_file_returns_false(self, validator, tmp_path):
        bad_file = tmp_path / "bad.yaml"
        bad_file.write_text("key: [\n")  # broken YAML
        result = validator.validate_optional_files(str(bad_file))
        assert result is False

    def test_no_files_in_category_warns_continues(self, validator, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            cicd_profile: ci_cd
            optional_files:
              - name: custom
                repo: https://github.ibm.com/org/app
                branch: main
                files: []
        """)
        result = validator.validate_optional_files(yaml_path)
        assert result is True  # warns but does not fail
        assert len(validator.warnings) >= 1


# ---------------------------------------------------------------------------
# print_summary (smoke test — ensures no exceptions)
# ---------------------------------------------------------------------------

class TestPrintSummary:
    def test_print_summary_no_errors(self, validator, capsys):
        validator.total_files = 3
        validator.success_count = 3
        validator.print_summary()
        out = capsys.readouterr().out
        assert "3" in out

    def test_print_summary_with_errors(self, validator, capsys):
        validator.total_files = 2
        validator.success_count = 1
        validator.errors = ["Error 1"]
        validator.print_summary()
        out = capsys.readouterr().out
        assert "Error 1" in out

    def test_print_summary_with_warnings(self, validator, capsys):
        validator.total_files = 1
        validator.success_count = 1
        validator.warnings = ["Watch out"]
        validator.print_summary()
        out = capsys.readouterr().out
        assert "1" in out

if __name__ == '__main__':
    pytest.main([__file__, '-v'])
