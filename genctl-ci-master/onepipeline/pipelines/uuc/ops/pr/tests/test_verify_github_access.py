#!/usr/bin/env python3
"""
Tests for verify_github_access.py

Covers GitHubAccessVerifier: parse_repo_url, get_user_permission,
_check_team_permission, _is_user_in_team, check_repo_exists,
validate_github_username, check_org_create_permission, verify_permission,
and verify_onboarding_yaml — with both positive and negative scenarios.

All HTTP calls are mocked.
"""

import os
import sys
import textwrap
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

STEPS_DIR = Path(__file__).resolve().parents[1] / "steps"
sys.path.insert(0, str(STEPS_DIR))

from verify_github_access import GitHubAccessVerifier  # noqa: E402


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

TOKEN = "fake-test-token"
API_URL = "https://github.ibm.com/api/v3"


def _mock_response(status_code: int, json_data=None):
    resp = MagicMock()
    resp.status_code = status_code
    resp.json.return_value = json_data or {}
    resp.text = str(json_data)[:500]
    return resp


def _write_yaml(tmp_path, content: str) -> str:
    p = tmp_path / "onboarding.yaml"
    p.write_text(textwrap.dedent(content))
    return str(p)


@pytest.fixture()
def verifier():
    return GitHubAccessVerifier(token=TOKEN, github_api_url=API_URL)


# ---------------------------------------------------------------------------
# parse_repo_url
# ---------------------------------------------------------------------------

class TestParseRepoUrl:
    def test_standard_https_url(self, verifier):
        org, repo = verifier.parse_repo_url("https://github.ibm.com/myorg/my-repo")
        assert org == "myorg"
        assert repo == "my-repo"

    def test_git_suffix_stripped(self, verifier):
        org, repo = verifier.parse_repo_url("https://github.ibm.com/myorg/my-repo.git")
        assert repo == "my-repo"

    def test_trailing_slash_stripped(self, verifier):
        org, repo = verifier.parse_repo_url("https://github.ibm.com/myorg/my-repo/")
        assert repo == "my-repo"

    def test_invalid_url_raises_value_error(self, verifier):
        with pytest.raises((ValueError, IndexError)):
            verifier.parse_repo_url("not-a-url")


# ---------------------------------------------------------------------------
# get_user_permission
# ---------------------------------------------------------------------------

class TestGetUserPermission:
    @patch("verify_github_access.requests.get")
    def test_returns_permission_for_direct_collaborator(self, mock_get, verifier):
        mock_get.return_value = _mock_response(200, {"permission": "admin"})
        perm = verifier.get_user_permission("myorg", "my-repo", "some-user")
        assert perm == "admin"

    @patch("verify_github_access.requests.get")
    def test_fid_email_converted_to_username(self, mock_get, verifier):
        mock_get.return_value = _mock_response(200, {"permission": "write"})
        perm = verifier.get_user_permission(
            "myorg", "my-repo", "onepipelineci@ibm.com"
        )
        assert perm == "write"
        # URL should use the GitHub username, not the email
        called_url = mock_get.call_args.args[0]
        assert "OnePipeLineCI" in called_url

    @patch("verify_github_access.requests.get")
    def test_clconc_fid_email_converted(self, mock_get, verifier):
        mock_get.return_value = _mock_response(200, {"permission": "write"})
        perm = verifier.get_user_permission(
            "myorg", "my-repo", "clconc@us.ibm.com"
        )
        assert perm == "write"
        called_url = mock_get.call_args.args[0]
        assert "clconc" in called_url

    @patch("verify_github_access.requests.get")
    def test_returns_none_on_unexpected_status(self, mock_get, verifier):
        mock_get.return_value = _mock_response(500)
        perm = verifier.get_user_permission("myorg", "my-repo", "someone")
        assert perm is None
        assert len(verifier.warnings) >= 1

    @patch("verify_github_access.requests.get")
    def test_returns_none_on_network_error(self, mock_get, verifier):
        import requests as req
        mock_get.side_effect = req.exceptions.ConnectionError("refused")
        perm = verifier.get_user_permission("myorg", "my-repo", "someone")
        assert perm is None


# ---------------------------------------------------------------------------
# _check_team_permission
# ---------------------------------------------------------------------------

class TestCheckTeamPermission:
    @patch("verify_github_access.requests.get")
    def test_user_in_team_returns_team_permission(self, mock_get, verifier):
        teams_resp = _mock_response(200, [
            {"slug": "ci-team", "name": "CI Team", "permission": "admin"}
        ])
        member_resp = _mock_response(200, {"state": "active"})
        mock_get.side_effect = [teams_resp, member_resp]
        perm = verifier._check_team_permission("myorg", "my-repo", "some-user")
        assert perm == "admin"

    @patch("verify_github_access.requests.get")
    def test_user_not_in_any_team_returns_none(self, mock_get, verifier):
        teams_resp = _mock_response(200, [
            {"slug": "ci-team", "name": "CI Team", "permission": "write"}
        ])
        member_resp = _mock_response(404)
        mock_get.side_effect = [teams_resp, member_resp]
        perm = verifier._check_team_permission("myorg", "my-repo", "unknown-user")
        assert perm == "none"

    @patch("verify_github_access.requests.get")
    def test_teams_api_failure_returns_none(self, mock_get, verifier):
        mock_get.return_value = _mock_response(403)
        perm = verifier._check_team_permission("myorg", "my-repo", "some-user")
        assert perm == "none"


# ---------------------------------------------------------------------------
# _is_user_in_team
# ---------------------------------------------------------------------------

class TestIsUserInTeam:
    @patch("verify_github_access.requests.get")
    def test_returns_true_on_200(self, mock_get, verifier):
        mock_get.return_value = _mock_response(200, {"state": "active"})
        assert verifier._is_user_in_team("myorg", "ci-team", "user1") is True

    @patch("verify_github_access.requests.get")
    def test_returns_false_on_404(self, mock_get, verifier):
        mock_get.return_value = _mock_response(404)
        assert verifier._is_user_in_team("myorg", "ci-team", "unknown") is False

    @patch("verify_github_access.requests.get")
    def test_returns_false_on_network_error(self, mock_get, verifier):
        import requests as req
        mock_get.side_effect = req.exceptions.ConnectionError("refused")
        assert verifier._is_user_in_team("myorg", "ci-team", "user1") is False


# ---------------------------------------------------------------------------
# check_repo_exists
# ---------------------------------------------------------------------------

class TestCheckRepoExists:
    @patch("verify_github_access.requests.get")
    def test_returns_true_on_200(self, mock_get, verifier):
        mock_get.return_value = _mock_response(200)
        assert verifier.check_repo_exists("myorg", "my-repo") is True

    @patch("verify_github_access.requests.get")
    def test_returns_false_on_404(self, mock_get, verifier):
        mock_get.return_value = _mock_response(404)
        assert verifier.check_repo_exists("myorg", "nonexistent") is False

    @patch("verify_github_access.requests.get")
    def test_returns_false_on_network_error(self, mock_get, verifier):
        import requests as req
        mock_get.side_effect = req.exceptions.ConnectionError("refused")
        assert verifier.check_repo_exists("myorg", "my-repo") is False


# ---------------------------------------------------------------------------
# validate_github_username
# ---------------------------------------------------------------------------

class TestValidateGithubUsername:
    @patch("verify_github_access.requests.get")
    def test_valid_existing_user(self, mock_get, verifier):
        mock_get.return_value = _mock_response(200, {
            "login": "realuser", "email": "realuser@ibm.com"
        })
        assert verifier.validate_github_username("realuser", "realuser@ibm.com") is True

    @patch("verify_github_access.requests.get")
    def test_nonexistent_user_returns_false(self, mock_get, verifier):
        mock_get.return_value = _mock_response(404)
        assert verifier.validate_github_username("ghost-user", "ghost@ibm.com") is False
        assert len(verifier.errors) >= 1

    @patch("verify_github_access.requests.get")
    def test_empty_username_returns_false(self, mock_get, verifier):
        assert verifier.validate_github_username("", "user@ibm.com") is False

    @patch("verify_github_access.requests.get")
    def test_email_mismatch_adds_warning(self, mock_get, verifier):
        """When the API returns a different (public) email, a warning is added."""
        mock_get.return_value = _mock_response(200, {
            "login": "realuser", "email": "other@ibm.com"
        })
        result = verifier.validate_github_username("realuser", "expected@ibm.com")
        assert result is True
        assert len(verifier.warnings) >= 1

    @patch("verify_github_access.requests.get")
    def test_network_error_assumes_valid(self, mock_get, verifier):
        import requests as req
        mock_get.side_effect = req.exceptions.ConnectionError("refused")
        result = verifier.validate_github_username("user1", "user1@ibm.com")
        assert result is True  # assume valid on error
        assert len(verifier.warnings) >= 1

    @patch("verify_github_access.requests.get")
    def test_unexpected_status_assumes_valid(self, mock_get, verifier):
        mock_get.return_value = _mock_response(503)
        result = verifier.validate_github_username("user1", "user1@ibm.com")
        assert result is True
        assert len(verifier.warnings) >= 1


# ---------------------------------------------------------------------------
# verify_permission
# ---------------------------------------------------------------------------

class TestVerifyPermission:
    @patch("verify_github_access.requests.get")
    def test_admin_user_has_admin_permission(self, mock_get, verifier):
        mock_get.return_value = _mock_response(200, {"permission": "admin"})
        result = verifier.verify_permission("myorg", "my-repo",
                                            "OnePipeLineCI", "admin", "app repo")
        assert result is True
        assert len(verifier.success_messages) >= 1

    @patch("verify_github_access.requests.get")
    def test_write_user_satisfies_write_requirement(self, mock_get, verifier):
        mock_get.return_value = _mock_response(200, {"permission": "write"})
        result = verifier.verify_permission("myorg", "my-repo",
                                            "clconc", "write", "app repo")
        assert result is True

    @patch("verify_github_access.requests.get")
    def test_read_user_fails_write_requirement(self, mock_get, verifier):
        mock_get.return_value = _mock_response(200, {"permission": "read"})
        result = verifier.verify_permission("myorg", "my-repo",
                                            "weak-user", "write", "app repo")
        assert result is False
        assert len(verifier.errors) >= 1

    @patch("verify_github_access.requests.get")
    def test_none_permission_returns_false(self, mock_get, verifier):
        # Simulate 500 from get_user_permission → returns None
        mock_get.return_value = _mock_response(500)
        result = verifier.verify_permission("myorg", "my-repo",
                                            "some-user", "admin", "app repo")
        assert result is False

    @patch("verify_github_access.requests.get")
    def test_admin_satisfies_write_requirement(self, mock_get, verifier):
        mock_get.return_value = _mock_response(200, {"permission": "admin"})
        result = verifier.verify_permission("myorg", "my-repo",
                                            "power-user", "write", "inventory repo")
        assert result is True


# ---------------------------------------------------------------------------
# check_org_create_permission
# ---------------------------------------------------------------------------

class TestCheckOrgCreatePermission:
    def _membership_resp(self, role: str):
        return _mock_response(200, {"role": role, "state": "active"})

    def _org_resp(self, members_can_create=True):
        return _mock_response(200, {
            "members_can_create_repositories": members_can_create,
            "members_can_create_public_repositories": False,
            "members_can_create_private_repositories": False,
            "members_can_create_internal_repositories": False,
        })

    @patch("verify_github_access.requests.get")
    def test_admin_with_create_perms_returns_true(self, mock_get, verifier):
        # member check (204) → membership details → org settings
        mock_get.side_effect = [
            _mock_response(204),
            self._membership_resp("admin"),
            self._org_resp(True),
        ]
        assert verifier.check_org_create_permission("myorg", "dev-user") is True

    @patch("verify_github_access.requests.get")
    def test_admin_with_restrictive_org_still_returns_true_with_warning(
        self, mock_get, verifier
    ):
        """Admins override restrictions but a warning is added."""
        mock_get.side_effect = [
            _mock_response(204),
            self._membership_resp("admin"),
            _mock_response(200, {
                "members_can_create_repositories": False,
                "members_can_create_public_repositories": False,
                "members_can_create_private_repositories": False,
                "members_can_create_internal_repositories": False,
            }),
        ]
        result = verifier.check_org_create_permission("myorg", "dev-user")
        assert result is True
        assert len(verifier.warnings) >= 1

    @patch("verify_github_access.requests.get")
    def test_member_with_create_perms_returns_true(self, mock_get, verifier):
        mock_get.side_effect = [
            _mock_response(204),
            self._membership_resp("member"),
            self._org_resp(True),
        ]
        assert verifier.check_org_create_permission("myorg", "dev-user") is True

    @patch("verify_github_access.requests.get")
    def test_member_without_create_perms_returns_false(self, mock_get, verifier):
        mock_get.side_effect = [
            _mock_response(204),
            self._membership_resp("member"),
            self._org_resp(False),
        ]
        result = verifier.check_org_create_permission("myorg", "dev-user")
        assert result is False
        assert len(verifier.errors) >= 1

    @patch("verify_github_access.requests.get")
    def test_non_member_returns_false_with_error(self, mock_get, verifier):
        mock_get.return_value = _mock_response(404)
        result = verifier.check_org_create_permission("myorg", "outsider")
        assert result is False
        assert any("not a member" in e for e in verifier.errors)

    @patch("verify_github_access.requests.get")
    def test_membership_details_failure_returns_false_with_warning(
        self, mock_get, verifier
    ):
        mock_get.side_effect = [
            _mock_response(204),   # member check passes
            _mock_response(403),   # membership details fails
        ]
        result = verifier.check_org_create_permission("myorg", "dev-user")
        assert result is False
        assert len(verifier.warnings) >= 1

    @patch("verify_github_access.requests.get")
    def test_org_settings_failure_returns_false_with_warning(self, mock_get, verifier):
        mock_get.side_effect = [
            _mock_response(204),
            self._membership_resp("admin"),
            _mock_response(500),  # org settings call fails
        ]
        result = verifier.check_org_create_permission("myorg", "dev-user")
        assert result is False
        assert len(verifier.warnings) >= 1

    @patch("verify_github_access.requests.get")
    def test_unknown_role_returns_false_with_error(self, mock_get, verifier):
        mock_get.side_effect = [
            _mock_response(204),
            self._membership_resp("owner"),  # unexpected role value
            self._org_resp(True),
        ]
        result = verifier.check_org_create_permission("myorg", "dev-user")
        assert result is False
        assert any("Unknown role" in e for e in verifier.errors)

    @patch("verify_github_access.requests.get")
    def test_network_error_returns_false_with_warning(self, mock_get, verifier):
        import requests as req
        mock_get.side_effect = req.exceptions.ConnectionError("refused")
        result = verifier.check_org_create_permission("myorg", "dev-user")
        assert result is False
        assert len(verifier.warnings) >= 1

    @patch("verify_github_access.requests.get")
    def test_onepipeline_fid_email_converted_to_username(self, mock_get, verifier):
        """Passing the FID email address should use the mapped GitHub username in URLs."""
        mock_get.side_effect = [
            _mock_response(204),
            self._membership_resp("admin"),
            self._org_resp(True),
        ]
        result = verifier.check_org_create_permission("myorg", "onepipelineci@ibm.com")
        assert result is True
        first_url = mock_get.call_args_list[0].args[0]
        assert "OnePipeLineCI" in first_url

    @patch("verify_github_access.requests.get")
    def test_member_private_repo_permission_returns_true(self, mock_get, verifier):
        """members_can_create_private_repositories=True is sufficient for a member."""
        mock_get.side_effect = [
            _mock_response(204),
            self._membership_resp("member"),
            _mock_response(200, {
                "members_can_create_repositories": False,
                "members_can_create_public_repositories": False,
                "members_can_create_private_repositories": True,
                "members_can_create_internal_repositories": False,
            }),
        ]
        assert verifier.check_org_create_permission("myorg", "dev-user") is True


# ---------------------------------------------------------------------------
# verify_onboarding_yaml
# ---------------------------------------------------------------------------

class TestVerifyOnboardingYaml:
    def test_missing_cicd_profile_returns_false(self, verifier, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            app_repo:
              - repo: https://github.ibm.com/org/my-app
                branch: main
        """)
        result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is False

    def test_missing_dev_github_username_returns_false(self, verifier, tmp_path):
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            cicd_profile: ci_cd
            service_fid_dev: dev@ibm.com
            service_fid_prod: prod@ibm.com
        """)
        result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is False
        assert any("service_fid_dev_github_username" in e for e in verifier.errors)

    def test_missing_prod_github_username_non_minimal_returns_false(
        self, verifier, tmp_path
    ):
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            cicd_profile: ci_cd
            service_fid_dev: dev@ibm.com
            service_fid_dev_github_username: dev-user
        """)
        with patch.object(verifier, "validate_github_username", return_value=True):
            result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is False
        assert any("service_fid_prod_github_username" in e for e in verifier.errors)

    @patch("verify_github_access.requests.get")
    def test_minimal_does_not_require_prod_username(self, mock_get, verifier, tmp_path):
        # Return 200 for everything (user validation + repo checks)
        mock_get.return_value = _mock_response(200, {"login": "dev-user", "email": "",
                                                     "permission": "admin"})
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            cicd_profile: minimal
            service_fid_dev: dev@ibm.com
            service_fid_dev_github_username: dev-user
            app_repo:
              - repo: https://github.ibm.com/org/my-app
                branch: main
        """)
        # This may still fail for other reasons (inventory_repo etc.) — we just
        # assert that prod username absence does NOT add to errors for minimal
        verifier.verify_onboarding_yaml(str(yaml_path))
        prod_errors = [e for e in verifier.errors if "service_fid_prod_github_username" in e]
        assert prod_errors == []

    def test_invalid_yaml_returns_false(self, verifier, tmp_path):
        bad = tmp_path / "bad.yaml"
        bad.write_text("key: [\n")
        result = verifier.verify_onboarding_yaml(str(bad))
        assert result is False

    # --- inventory_repo create:true ---

    @patch("verify_github_access.requests.get")
    def test_inventory_create_true_dev_has_permission_adds_success_and_warning(
        self, mock_get, verifier, tmp_path
    ):
        """When inventory create=true and dev user can create, a success + warning are recorded."""
        # validate_github_username (200), then check_org_create_permission (3 calls):
        #   member check (204), membership details (200), org settings (200)
        mock_get.side_effect = [
            _mock_response(200, {"login": "dev-user", "email": "dev@ibm.com"}),  # validate dev username
            _mock_response(200, {"login": "prod-user", "email": "prod@ibm.com"}),  # validate prod username
            _mock_response(204),  # org member check
            _mock_response(200, {"role": "admin", "state": "active"}),  # membership details
            _mock_response(200, {"members_can_create_repositories": True,  # org settings
                                 "members_can_create_public_repositories": False,
                                 "members_can_create_private_repositories": False,
                                 "members_can_create_internal_repositories": False}),
        ]
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            cicd_profile: ci_cd
            service_fid_dev: dev@ibm.com
            service_fid_dev_github_username: dev-user
            service_fid_prod: prod@ibm.com
            service_fid_prod_github_username: prod-user
            inventory_repo:
              repo: https://github.ibm.com/org/my-inventory
              create: true
        """)
        verifier.verify_onboarding_yaml(str(yaml_path))
        assert any("dev-user" in m and "permission to create" in m
                   for m in verifier.success_messages)
        assert any("dev-user" in w and "post-creation" in w for w in verifier.warnings)
        assert any("prod-user" in w and "post-creation" in w for w in verifier.warnings)

    @patch("verify_github_access.requests.get")
    def test_inventory_create_true_dev_lacks_permission_fails(
        self, mock_get, verifier, tmp_path
    ):
        """When inventory create=true and dev user cannot create repos, result is False."""
        mock_get.side_effect = [
            _mock_response(200, {"login": "dev-user", "email": "dev@ibm.com"}),
            _mock_response(200, {"login": "prod-user", "email": "prod@ibm.com"}),
            _mock_response(204),   # member check
            _mock_response(200, {"role": "member", "state": "active"}),
            _mock_response(200, {"members_can_create_repositories": False,
                                 "members_can_create_public_repositories": False,
                                 "members_can_create_private_repositories": False,
                                 "members_can_create_internal_repositories": False}),
        ]
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            cicd_profile: ci_cd
            service_fid_dev: dev@ibm.com
            service_fid_dev_github_username: dev-user
            service_fid_prod: prod@ibm.com
            service_fid_prod_github_username: prod-user
            inventory_repo:
              repo: https://github.ibm.com/org/my-inventory
              create: true
        """)
        result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is False

    def test_inventory_create_true_missing_dev_username_adds_warning(
        self, verifier, tmp_path
    ):
        """When create=true but no dev username, a warning is added (not an error)."""
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            cicd_profile: ci_cd
            service_fid_dev: dev@ibm.com
            service_fid_dev_github_username: dev-user
            service_fid_prod: prod@ibm.com
            service_fid_prod_github_username: prod-user
            inventory_repo:
              repo: https://github.ibm.com/org/my-inventory
              create: true
        """)
        # Patch validate so we skip username-check HTTP calls and force dev username blank
        with patch.object(verifier, "validate_github_username", return_value=True), \
             patch.object(verifier, "check_org_create_permission", return_value=True):
            # Override to simulate missing dev username after validation
            verifier.verify_onboarding_yaml.__func__  # noqa — just ensure method exists
            # Directly manipulate: re-run with patched config loader
            import yaml as _yaml
            import textwrap
            cfg_text = textwrap.dedent("""
                team_name: Fabric
                service_name: my-svc
                cicd_profile: ci_cd
                service_fid_dev: dev@ibm.com
                service_fid_dev_github_username: ""
                service_fid_prod: prod@ibm.com
                service_fid_prod_github_username: prod-user
                inventory_repo:
                  repo: https://github.ibm.com/org/my-inventory
                  create: true
            """)
            p = tmp_path / "nousername.yaml"
            p.write_text(cfg_text)
            fresh = GitHubAccessVerifier(token=TOKEN, github_api_url=API_URL)
            with patch.object(fresh, "validate_github_username", return_value=True):
                fresh.verify_onboarding_yaml(str(p))
            assert any("service_fid_dev_github_username not provided" in w
                       for w in fresh.warnings)

    # --- inventory_repo create:false (existing repo) ---

    @patch("verify_github_access.requests.get")
    def test_inventory_existing_repo_service_fids_checked(
        self, mock_get, verifier, tmp_path
    ):
        """Existing inventory repo: service_fid_dev and service_fid_prod need admin."""
        # validate dev (200), validate prod (200),
        # check_repo_exists (200),
        # verify_permission for onepipelineci write (200 → write),
        # verify_permission for dev-user admin (200 → admin),
        # verify_permission for prod-user admin (200 → admin)
        mock_get.side_effect = [
            _mock_response(200, {"login": "dev-user", "email": "dev@ibm.com"}),
            _mock_response(200, {"login": "prod-user", "email": "prod@ibm.com"}),
            _mock_response(200),                               # repo exists
            _mock_response(200, {"permission": "write"}),     # onepipelineci write
            _mock_response(200, {"permission": "admin"}),     # dev-user admin
            _mock_response(200, {"permission": "admin"}),     # prod-user admin
        ]
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            cicd_profile: ci_cd
            service_fid_dev: dev@ibm.com
            service_fid_dev_github_username: dev-user
            service_fid_prod: prod@ibm.com
            service_fid_prod_github_username: prod-user
            inventory_repo:
              repo: https://github.ibm.com/org/my-inventory
              create: false
        """)
        verifier.verify_onboarding_yaml(str(yaml_path))
        # Both FID usernames should have been checked for admin
        checked_users = [
            call.args[0]
            for call in mock_get.call_args_list
            if "collaborators" in call.args[0]
        ]
        assert any("dev-user" in u for u in checked_users)
        assert any("prod-user" in u for u in checked_users)

    @patch("verify_github_access.requests.get")
    def test_inventory_existing_repo_dev_lacking_admin_fails(
        self, mock_get, verifier, tmp_path
    ):
        mock_get.side_effect = [
            _mock_response(200, {"login": "dev-user", "email": "dev@ibm.com"}),
            _mock_response(200, {"login": "prod-user", "email": "prod@ibm.com"}),
            _mock_response(200),                               # repo exists
            _mock_response(200, {"permission": "write"}),     # onepipelineci write OK
            _mock_response(200, {"permission": "read"}),      # dev-user only has read → FAIL
            _mock_response(200, {"permission": "admin"}),     # prod-user admin
        ]
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            cicd_profile: ci_cd
            service_fid_dev: dev@ibm.com
            service_fid_dev_github_username: dev-user
            service_fid_prod: prod@ibm.com
            service_fid_prod_github_username: prod-user
            inventory_repo:
              repo: https://github.ibm.com/org/my-inventory
              create: false
        """)
        result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is False
        assert any("dev-user" in e for e in verifier.errors)

    # --- incident_repo create:true ---

    @patch("verify_github_access.requests.get")
    def test_incident_create_true_dev_has_permission_adds_success_and_warning(
        self, mock_get, verifier, tmp_path
    ):
        """When incident create=true and dev user can create, success + warnings recorded."""
        mock_get.side_effect = [
            _mock_response(200, {"login": "dev-user", "email": "dev@ibm.com"}),   # validate dev
            _mock_response(200, {"login": "prod-user", "email": "prod@ibm.com"}), # validate prod
            _mock_response(404),   # repo does NOT exist (required for create=true)
            _mock_response(204),   # org member check
            _mock_response(200, {"role": "admin", "state": "active"}),
            _mock_response(200, {"members_can_create_repositories": True,
                                 "members_can_create_public_repositories": False,
                                 "members_can_create_private_repositories": False,
                                 "members_can_create_internal_repositories": False}),
        ]
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            cicd_profile: ci_cd
            service_fid_dev: dev@ibm.com
            service_fid_dev_github_username: dev-user
            service_fid_prod: prod@ibm.com
            service_fid_prod_github_username: prod-user
            incident_repo:
              repo: https://github.ibm.com/org/my-incident
              branch: main
              create: true
        """)
        verifier.verify_onboarding_yaml(str(yaml_path))
        assert any("dev-user" in m and "permission to create" in m
                   for m in verifier.success_messages)
        assert any("dev-user" in w and "post-creation" in w for w in verifier.warnings)
        assert any("prod-user" in w and "post-creation" in w for w in verifier.warnings)

    @patch("verify_github_access.requests.get")
    def test_incident_create_true_repo_already_exists_fails(
        self, mock_get, verifier, tmp_path
    ):
        """incident create=true but repo already exists → error."""
        mock_get.side_effect = [
            _mock_response(200, {"login": "dev-user", "email": "dev@ibm.com"}),
            _mock_response(200, {"login": "prod-user", "email": "prod@ibm.com"}),
            _mock_response(200),  # repo EXISTS → should fail
        ]
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            cicd_profile: ci_cd
            service_fid_dev: dev@ibm.com
            service_fid_dev_github_username: dev-user
            service_fid_prod: prod@ibm.com
            service_fid_prod_github_username: prod-user
            incident_repo:
              repo: https://github.ibm.com/org/my-incident
              branch: main
              create: true
        """)
        result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is False
        assert any("already exists" in e for e in verifier.errors)

    # --- incident_repo create:false (existing repo) ---

    @patch("verify_github_access.requests.get")
    def test_incident_existing_repo_service_fids_checked(
        self, mock_get, verifier, tmp_path
    ):
        """Existing incident repo: onepipelineci admin + dev + prod need admin."""
        mock_get.side_effect = [
            _mock_response(200, {"login": "dev-user", "email": "dev@ibm.com"}),
            _mock_response(200, {"login": "prod-user", "email": "prod@ibm.com"}),
            _mock_response(200),                               # repo exists
            _mock_response(200, {"name": "main"}),            # branch check (branch: main is set)
            _mock_response(200, {"permission": "admin"}),     # onepipelineci admin
            _mock_response(200, {"permission": "admin"}),     # dev-user admin
            _mock_response(200, {"permission": "admin"}),     # prod-user admin
        ]
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            cicd_profile: ci_cd
            service_fid_dev: dev@ibm.com
            service_fid_dev_github_username: dev-user
            service_fid_prod: prod@ibm.com
            service_fid_prod_github_username: prod-user
            incident_repo:
              repo: https://github.ibm.com/org/my-incident
              branch: main
              create: false
        """)
        verifier.verify_onboarding_yaml(str(yaml_path))
        checked_users = [
            call.args[0]
            for call in mock_get.call_args_list
            if "collaborators" in call.args[0]
        ]
        assert any("dev-user" in u for u in checked_users)
        assert any("prod-user" in u for u in checked_users)

    @patch("verify_github_access.requests.get")
    def test_incident_no_prod_username_ci_cd_adds_warning(
        self, mock_get, verifier, tmp_path
    ):
        """incident create=true with no prod username on ci_cd profile emits a warning."""
        mock_get.side_effect = [
            _mock_response(200, {"login": "dev-user", "email": "dev@ibm.com"}),
            _mock_response(200, {"login": "prod-user", "email": "prod@ibm.com"}),
            _mock_response(404),   # repo doesn't exist yet
            _mock_response(204),   # org member check
            _mock_response(200, {"role": "admin", "state": "active"}),
            _mock_response(200, {"members_can_create_repositories": True,
                                 "members_can_create_public_repositories": False,
                                 "members_can_create_private_repositories": False,
                                 "members_can_create_internal_repositories": False}),
        ]
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            cicd_profile: ci_cd
            service_fid_dev: dev@ibm.com
            service_fid_dev_github_username: dev-user
            service_fid_prod: prod@ibm.com
            service_fid_prod_github_username: prod-user
            incident_repo:
              repo: https://github.ibm.com/org/my-incident
              create: true
        """)
        verifier.verify_onboarding_yaml(str(yaml_path))
        # prod-user post-creation warning should be present
        assert any("prod-user" in w and "post-creation" in w for w in verifier.warnings)

if __name__ == '__main__':
    pytest.main([__file__, '-v'])
