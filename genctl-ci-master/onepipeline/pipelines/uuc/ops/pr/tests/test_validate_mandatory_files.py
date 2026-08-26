#!/usr/bin/env python3
"""
Tests for validate_mandatory_files.py

Covers MandatoryFilesValidator: parse_github_url, check_file_executable,
check_file_empty, get_file_content, validate_build_meta_yaml_content,
validate_pipeline_yaml_content, validate_file, and validate_mandatory_files
— with positive (happy-path) and negative (error/edge-case) scenarios.

All GitHub / filesystem I/O is mocked so no network calls are made.
"""

import base64
import os
import sys
import textwrap
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

STEPS_DIR = Path(__file__).resolve().parents[1] / "steps"
sys.path.insert(0, str(STEPS_DIR))

os.environ.setdefault("GH_TOKEN", "fake-token-for-tests")

from validate_mandatory_files import MandatoryFilesValidator  # noqa: E402


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture()
def validator():
    with patch.dict(os.environ, {"GH_TOKEN": "fake-token"}):
        return MandatoryFilesValidator(debug=False)


def _encode(content: str) -> str:
    return base64.b64encode(content.encode()).decode()


def _write_yaml(tmp_path, content: str) -> str:
    p = tmp_path / "onboarding.yaml"
    p.write_text(textwrap.dedent(content))
    return str(p)


# ---------------------------------------------------------------------------
# parse_github_url
# ---------------------------------------------------------------------------

class TestParseGithubUrl:
    def test_valid_url(self, validator):
        host, owner, repo = validator.parse_github_url(
            "https://github.ibm.com/myorg/my-repo"
        )
        assert host == "github.ibm.com"
        assert owner == "myorg"
        assert repo == "my-repo"

    def test_git_suffix_stripped(self, validator):
        _, _, repo = validator.parse_github_url(
            "https://github.ibm.com/org/repo.git"
        )
        assert repo == "repo"

    def test_trailing_slash_stripped(self, validator):
        _, _, repo = validator.parse_github_url(
            "https://github.ibm.com/org/repo/"
        )
        assert repo == "repo"

    def test_invalid_url_returns_nones(self, validator):
        host, owner, repo = validator.parse_github_url("not-a-url")
        assert all(x is None for x in (host, owner, repo))


# ---------------------------------------------------------------------------
# check_file_executable
# ---------------------------------------------------------------------------

class TestCheckFileExecutable:
    def test_755_is_executable(self, validator):
        is_exec, _ = validator.check_file_executable({"mode": "100755"})
        assert is_exec is True

    def test_644_not_executable(self, validator):
        is_exec, _ = validator.check_file_executable({"mode": "100644"})
        assert is_exec is False

    def test_750_is_executable(self, validator):
        is_exec, _ = validator.check_file_executable({"mode": "100750"})
        assert is_exec is True

    def test_no_mode_sh_extension_inferred(self, validator):
        is_exec, info = validator.check_file_executable({"name": "deploy.sh"})
        assert is_exec is True
        assert "inferred" in info

    def test_no_mode_non_sh_not_executable(self, validator):
        is_exec, info = validator.check_file_executable({"name": "README.md"})
        assert is_exec is False

    def test_invalid_mode_string(self, validator):
        is_exec, _ = validator.check_file_executable({"mode": "INVALID"})
        assert is_exec is False


# ---------------------------------------------------------------------------
# check_file_empty
# ---------------------------------------------------------------------------

class TestCheckFileEmpty:
    def test_size_zero_is_empty(self, validator):
        assert validator.check_file_empty({"size": 0}) is True

    def test_real_content_not_empty(self, validator):
        content = "#!/bin/bash\necho hello"
        assert validator.check_file_empty({
            "size": len(content),
            "name": "build.sh",
            "content": _encode(content),
        }) is False

    def test_whitespace_only_is_empty(self, validator):
        content = "   \n   "
        assert validator.check_file_empty({
            "size": len(content),
            "name": "build.sh",
            "content": _encode(content),
        }) is True

    def test_yaml_comments_only_is_empty(self, validator):
        content = "# just a comment\n# another comment\n"
        assert validator.check_file_empty({
            "size": len(content),
            "name": "pipeline.yaml",
            "content": _encode(content),
        }) is True

    def test_yaml_with_content_not_empty(self, validator):
        content = "key: value\n"
        assert validator.check_file_empty({
            "size": len(content),
            "name": "build-meta.yaml",
            "content": _encode(content),
        }) is False

    def test_sh_shebang_only_is_empty(self, validator):
        content = "#!/bin/bash\n# only shebang and comment\n"
        assert validator.check_file_empty({
            "size": len(content),
            "name": "build.sh",
            "content": _encode(content),
        }) is True


# ---------------------------------------------------------------------------
# get_file_content
# ---------------------------------------------------------------------------

class TestGetFileContent:
    def test_valid_base64_content(self, validator):
        raw = "hello world"
        result = validator.get_file_content({"content": _encode(raw)})
        assert result == raw

    def test_empty_content_field(self, validator):
        assert validator.get_file_content({"content": ""}) is None

    def test_missing_content_field(self, validator):
        assert validator.get_file_content({}) is None

    def test_invalid_base64_returns_none(self, validator):
        result = validator.get_file_content({"content": "!!! not base64 !!!"})
        assert result is None


# ---------------------------------------------------------------------------
# validate_build_meta_yaml_content
# ---------------------------------------------------------------------------

class TestValidateBuildMetaYamlContent:
    def test_valid_images_section(self, validator):
        content = textwrap.dedent("""
            images:
              amd64: registry/image:1.0
        """)
        ok, errs = validator.validate_build_meta_yaml_content(content)
        assert ok is True
        assert errs == []

    def test_valid_packages_section(self, validator):
        content = textwrap.dedent("""
            packages:
              deb: my-package
        """)
        ok, errs = validator.validate_build_meta_yaml_content(content)
        assert ok is True

    def test_empty_content_invalid(self, validator):
        ok, errs = validator.validate_build_meta_yaml_content("")
        assert ok is False
        assert len(errs) >= 1

    def test_missing_both_sections_invalid(self, validator):
        ok, errs = validator.validate_build_meta_yaml_content("other_key: value\n")
        assert ok is False

    def test_images_not_a_dict_invalid(self, validator):
        content = "images: [item1, item2]\n"
        ok, errs = validator.validate_build_meta_yaml_content(content)
        assert ok is False

    def test_invalid_yaml_syntax(self, validator):
        ok, errs = validator.validate_build_meta_yaml_content("key: [\n")
        assert ok is False
        assert len(errs) >= 1


# ---------------------------------------------------------------------------
# validate_pipeline_yaml_content
# ---------------------------------------------------------------------------

class TestValidatePipelineYamlContent:
    TEAM = "Fabric"

    def _valid_content(self, psirt="PSIRT_PRD1234567"):
        return textwrap.dedent(f"""
            mend_sast_info:
              mend-product-name: {psirt}
              mend-user-email: psirt_prd1234567service_user@ibm.com
              mend-secret-group: sg-uuc-fabric
        """)

    def test_valid_pipeline_yaml(self, validator):
        ok, errs = validator.validate_pipeline_yaml_content(
            self._valid_content(), self.TEAM
        )
        assert ok is True
        assert errs == []

    def test_missing_mend_sast_info_section(self, validator):
        ok, errs = validator.validate_pipeline_yaml_content(
            "other_key: value\n", self.TEAM
        )
        assert ok is False
        assert any("mend_sast_info" in e for e in errs)

    def test_empty_mend_sast_info_section(self, validator):
        ok, errs = validator.validate_pipeline_yaml_content(
            "mend_sast_info:\n", self.TEAM
        )
        assert ok is False

    def test_missing_product_name_key(self, validator):
        content = textwrap.dedent("""
            mend_sast_info:
              mend-user-email: psirt_prd1234567service_user@ibm.com
              mend-secret-group: sg-uuc-fabric
        """)
        ok, errs = validator.validate_pipeline_yaml_content(content, self.TEAM)
        assert ok is False
        assert any("mend-product-name" in e for e in errs)

    def test_invalid_product_name_format(self, validator):
        content = textwrap.dedent("""
            mend_sast_info:
              mend-product-name: PSIRT-INVALID
              mend-user-email: psirt_prd1234567service_user@ibm.com
              mend-secret-group: sg-uuc-fabric
        """)
        ok, errs = validator.validate_pipeline_yaml_content(content, self.TEAM)
        assert ok is False

    def test_invalid_user_email_format(self, validator):
        content = textwrap.dedent("""
            mend_sast_info:
              mend-product-name: PSIRT_PRD1234567
              mend-user-email: not-valid@ibm.com
              mend-secret-group: sg-uuc-fabric
        """)
        ok, errs = validator.validate_pipeline_yaml_content(content, self.TEAM)
        assert ok is False

    def test_wrong_secret_group(self, validator):
        content = textwrap.dedent("""
            mend_sast_info:
              mend-product-name: PSIRT_PRD1234567
              mend-user-email: psirt_prd1234567service_user@ibm.com
              mend-secret-group: sg-uuc-wrong-team
        """)
        ok, errs = validator.validate_pipeline_yaml_content(content, self.TEAM)
        assert ok is False

    def test_mismatched_product_and_email_digits(self, validator):
        content = textwrap.dedent("""
            mend_sast_info:
              mend-product-name: PSIRT_PRD1234567
              mend-user-email: psirt_prd9999999service_user@ibm.com
              mend-secret-group: sg-uuc-fabric
        """)
        ok, errs = validator.validate_pipeline_yaml_content(content, self.TEAM)
        assert ok is False

    def test_non_breaking_space_in_content(self, validator):
        content = "mend_sast_info:\n\xa0 mend-product-name: PSIRT_PRD1234567\n"
        ok, errs = validator.validate_pipeline_yaml_content(content, self.TEAM)
        assert ok is False
        assert any("non-breaking" in e for e in errs)

    def test_invalid_yaml_syntax(self, validator):
        ok, errs = validator.validate_pipeline_yaml_content("key: [\n", self.TEAM)
        assert ok is False


# ---------------------------------------------------------------------------
# validate_file (integration with mocked GitHub)
# ---------------------------------------------------------------------------

class TestValidateFile:
    def test_missing_file_returns_false(self, validator):
        validator.get_file_from_github = MagicMock(return_value=None)
        assert validator.validate_file(
            "https://github.ibm.com/org/repo", "main",
            {"path": "hack/ci/build.sh", "can_be_empty": False, "executable": True},
            "CI",
        ) is False

    def test_invalid_url_returns_false(self, validator):
        assert validator.validate_file(
            "bad-url", "main",
            {"path": "build.sh", "can_be_empty": False, "executable": False},
            "CI",
        ) is False

    def test_executable_file_passes(self, validator):
        validator.get_file_from_github = MagicMock(
            return_value={"name": "build.sh", "size": 100, "mode": "100755",
                         "content": _encode("#!/bin/bash\necho hi")}
        )
        assert validator.validate_file(
            "https://github.ibm.com/org/repo", "main",
            {"path": "hack/ci/build.sh", "can_be_empty": False, "executable": True},
            "CI",
        ) is True

    def test_non_executable_when_required_returns_false(self, validator):
        validator.get_file_from_github = MagicMock(
            return_value={"name": "build.sh", "size": 100, "mode": "100644",
                         "content": _encode("#!/bin/bash\necho hi")}
        )
        assert validator.validate_file(
            "https://github.ibm.com/org/repo", "main",
            {"path": "hack/ci/build.sh", "can_be_empty": False, "executable": True},
            "CI",
        ) is False

    def test_empty_file_not_allowed_returns_false(self, validator):
        validator.get_file_from_github = MagicMock(
            return_value={"name": "build.sh", "size": 0, "mode": "100755", "content": ""}
        )
        assert validator.validate_file(
            "https://github.ibm.com/org/repo", "main",
            {"path": "hack/ci/build.sh", "can_be_empty": False, "executable": True},
            "CI",
        ) is False

    def test_empty_file_allowed_passes(self, validator):
        validator.get_file_from_github = MagicMock(
            return_value={"name": "notes.md", "size": 0, "mode": "100644", "content": ""}
        )
        assert validator.validate_file(
            "https://github.ibm.com/org/repo", "main",
            {"path": "notes.md", "can_be_empty": True, "executable": False},
            "docs",
        ) is True

    def test_valid_pipeline_yaml_content_passes(self, validator):
        pipeline_content = textwrap.dedent("""
            mend_sast_info:
              mend-product-name: PSIRT_PRD1234567
              mend-user-email: psirt_prd1234567service_user@ibm.com
              mend-secret-group: sg-uuc-fabric
        """)
        validator.get_file_from_github = MagicMock(
            return_value={"name": "pipeline.yaml", "size": 200, "mode": "100644",
                         "content": _encode(pipeline_content)}
        )
        assert validator.validate_file(
            "https://github.ibm.com/org/repo", "main",
            {"path": "hack/ci/pipeline.yaml", "can_be_empty": False, "executable": False},
            "CI",
            team_name="Fabric",
        ) is True

    def test_invalid_pipeline_yaml_content_returns_false(self, validator):
        validator.get_file_from_github = MagicMock(
            return_value={"name": "pipeline.yaml", "size": 50, "mode": "100644",
                         "content": _encode("other_key: value\n")}
        )
        assert validator.validate_file(
            "https://github.ibm.com/org/repo", "main",
            {"path": "hack/ci/pipeline.yaml", "can_be_empty": False, "executable": False,
             "validate_content": True},
            "CI",
            team_name="Fabric",
        ) is False

    def test_valid_build_meta_yaml_passes(self, validator):
        bm_content = "images:\n  amd64: registry/img:1.0\n"
        validator.get_file_from_github = MagicMock(
            return_value={"name": "build-meta.yaml", "size": len(bm_content),
                         "mode": "100644", "content": _encode(bm_content)}
        )
        assert validator.validate_file(
            "https://github.ibm.com/org/repo", "main",
            {"path": "hack/ci/build-meta.yaml", "can_be_empty": False, "executable": False},
            "CI",
        ) is True

    def test_invalid_build_meta_yaml_returns_false(self, validator):
        bm_content = "other_key: value\n"
        validator.get_file_from_github = MagicMock(
            return_value={"name": "build-meta.yaml", "size": len(bm_content),
                         "mode": "100644", "content": _encode(bm_content)}
        )
        assert validator.validate_file(
            "https://github.ibm.com/org/repo", "main",
            {"path": "hack/ci/build-meta.yaml", "can_be_empty": False, "executable": False},
            "CI",
        ) is False


# ---------------------------------------------------------------------------
# validate_mandatory_files (full YAML flow)
# ---------------------------------------------------------------------------

class TestValidateMandatoryFilesFlow:
    def _build_sh_info(self):
        return {"name": "build.sh", "size": 100, "mode": "100755",
                "content": _encode("#!/bin/bash\necho hi")}

    def _run_tests_info(self):
        return {"name": "run-unit-tests.sh", "size": 100, "mode": "100755",
                "content": _encode("#!/bin/bash\necho tests")}

    def _build_meta_info(self):
        return {"name": "build-meta.yaml", "size": 50, "mode": "100644",
                "content": _encode("images:\n  amd64: img:1.0\n")}

    def _pipeline_info(self, team="Fabric"):
        content = textwrap.dedent(f"""
            mend_sast_info:
              mend-product-name: PSIRT_PRD1234567
              mend-user-email: psirt_prd1234567service_user@ibm.com
              mend-secret-group: sg-uuc-{team.lower()}
        """)
        return {"name": "pipeline.yaml", "size": len(content), "mode": "100644",
                "content": _encode(content)}

    def test_no_mandatory_files_warns_returns_true(self, validator, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            cicd_profile: ci_cd
            team_name: Fabric
        """)
        result = validator.validate_mandatory_files(yaml_path)
        assert result is True
        assert len(validator.warnings) >= 1

    def test_missing_cicd_profile_returns_false(self, validator, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            mandatory_files: []
        """)
        result = validator.validate_mandatory_files(yaml_path)
        assert result is False

    def test_ci_only_skips_cd_group(self, validator, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            cicd_profile: ci_only
            team_name: Fabric
            mandatory_files:
              - name: CD
                repo: https://github.ibm.com/org/app
                branch: main
                files:
                  - path: hack/cd/deploy.sh
                    can_be_empty: false
                    executable: true
        """)
        # CD group should be skipped — no GitHub calls needed
        result = validator.validate_mandatory_files(yaml_path)
        assert result is True

    def test_minimal_skips_cd_group(self, validator, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            cicd_profile: minimal
            team_name: Fabric
            mandatory_files:
              - name: CD
                repo: https://github.ibm.com/org/app
                branch: main
                files:
                  - path: hack/cd/deploy.sh
                    can_be_empty: false
                    executable: true
        """)
        result = validator.validate_mandatory_files(yaml_path)
        assert result is True

    def test_missing_repo_in_category_returns_false(self, validator, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            cicd_profile: ci_cd
            team_name: Fabric
            mandatory_files:
              - name: CI
                branch: main
                files:
                  - path: hack/ci/build.sh
                    can_be_empty: false
                    executable: true
        """)
        result = validator.validate_mandatory_files(yaml_path)
        assert result is False

    def test_applies_to_filter_skips_file(self, validator, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            cicd_profile: minimal
            team_name: Fabric
            mandatory_files:
              - name: CI
                repo: https://github.ibm.com/org/app
                branch: main
                files:
                  - path: hack/ci/build.sh
                    can_be_empty: false
                    executable: true
                    applies_to: [ci_cd]
        """)
        # applies_to: [ci_cd] should skip the file for minimal
        result = validator.validate_mandatory_files(yaml_path)
        assert result is True

    def test_successful_ci_file_validation(self, validator, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            cicd_profile: ci_cd
            team_name: Fabric
            mandatory_files:
              - name: CI
                repo: https://github.ibm.com/org/app
                branch: main
                files:
                  - path: hack/ci/build.sh
                    can_be_empty: false
                    executable: true
                  - path: hack/ci/run-unit-tests.sh
                    can_be_empty: false
                    executable: true
                  - path: hack/ci/build-meta.yaml
                    can_be_empty: false
                    executable: false
                  - path: hack/ci/pipeline.yaml
                    can_be_empty: false
                    executable: false
        """)

        def _side_effect(host, owner, repo, branch, file_path, *args, **kwargs):
            m = {
                "hack/ci/build.sh": self._build_sh_info(),
                "hack/ci/run-unit-tests.sh": self._run_tests_info(),
                "hack/ci/build-meta.yaml": self._build_meta_info(),
                "hack/ci/pipeline.yaml": self._pipeline_info(),
            }
            return m.get(file_path)

        validator.get_file_from_github = MagicMock(side_effect=_side_effect)
        result = validator.validate_mandatory_files(yaml_path)
        assert result is True

    def test_invalid_yaml_file_returns_false(self, validator, tmp_path):
        bad = tmp_path / "bad.yaml"
        bad.write_text("key: [\n")
        result = validator.validate_mandatory_files(str(bad))
        assert result is False

if __name__ == '__main__':
    pytest.main([__file__, '-v'])
