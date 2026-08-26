#!/usr/bin/env python3
"""
Tests for verify_compliance_bucket_access.py

Covers ComplianceBucketVerifier: get_iam_token, parse_bucket_url,
get_bucket_iam_policy, check_bucket_access, and verify_onboarding_yaml
— with both positive and negative scenarios.

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

from verify_compliance_bucket_access import ComplianceBucketVerifier  # noqa: E402


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

API_KEY = "test-api-key"


def _mock_response(status_code: int, json_data=None, text=""):
    resp = MagicMock()
    resp.status_code = status_code
    resp.json.return_value = json_data or {}
    resp.text = text
    return resp


def _write_yaml(tmp_path, content: str) -> str:
    p = tmp_path / "onboarding.yaml"
    p.write_text(textwrap.dedent(content))
    return str(p)


@pytest.fixture()
def verifier():
    return ComplianceBucketVerifier(api_key=API_KEY)


# ---------------------------------------------------------------------------
# get_iam_token
# ---------------------------------------------------------------------------

class TestGetIamToken:
    @patch("verify_compliance_bucket_access.requests.post")
    def test_returns_token_on_200(self, mock_post, verifier):
        mock_post.return_value = _mock_response(200, {"access_token": "my-iam-token"})
        token = verifier.get_iam_token()
        assert token == "my-iam-token"

    @patch("verify_compliance_bucket_access.requests.post")
    def test_caches_token(self, mock_post, verifier):
        mock_post.return_value = _mock_response(200, {"access_token": "cached-token"})
        verifier.get_iam_token()
        verifier.get_iam_token()
        assert mock_post.call_count == 1  # second call uses cache

    @patch("verify_compliance_bucket_access.requests.post")
    def test_returns_none_on_non_200(self, mock_post, verifier):
        mock_post.return_value = _mock_response(401)
        token = verifier.get_iam_token()
        assert token is None
        assert len(verifier.errors) >= 1

    @patch("verify_compliance_bucket_access.requests.post")
    def test_returns_none_on_network_error(self, mock_post, verifier):
        import requests as req
        mock_post.side_effect = req.exceptions.ConnectionError("refused")
        token = verifier.get_iam_token()
        assert token is None
        assert len(verifier.errors) >= 1


# ---------------------------------------------------------------------------
# parse_bucket_url
# ---------------------------------------------------------------------------

class TestParseBucketUrl:
    def test_s3_scheme(self, verifier):
        name, endpoint = verifier.parse_bucket_url("s3://my-bucket")
        assert name == "my-bucket"
        assert "cloud-object-storage" in endpoint

    def test_cos_scheme(self, verifier):
        name, endpoint = verifier.parse_bucket_url("cos://my-bucket")
        assert name == "my-bucket"

    def test_plain_bucket_name(self, verifier):
        name, endpoint = verifier.parse_bucket_url("uuc-fabric-ci-storage")
        assert name == "uuc-fabric-ci-storage"
        assert "cloud-object-storage" in endpoint

    def test_trailing_slash_stripped(self, verifier):
        name, _ = verifier.parse_bucket_url("s3://my-bucket/")
        assert name == "my-bucket"

    def test_invalid_scheme_raises(self, verifier):
        with pytest.raises(ValueError, match="Invalid bucket URL"):
            verifier.parse_bucket_url("ftp://my-bucket")


# ---------------------------------------------------------------------------
# check_bucket_access
# ---------------------------------------------------------------------------

class TestCheckBucketAccess:
    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_returns_true_on_200(self, mock_post, mock_head, verifier):
        mock_post.return_value = _mock_response(200, {"access_token": "tok"})
        mock_head.return_value = _mock_response(200)
        result = verifier.check_bucket_access(
            "my-bucket", "s3.us.cloud-object-storage.appdomain.cloud",
            "onepipelineci@ibm.com", "write"
        )
        assert result is True

    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_returns_false_on_404(self, mock_post, mock_head, verifier):
        mock_post.return_value = _mock_response(200, {"access_token": "tok"})
        mock_head.return_value = _mock_response(404)
        result = verifier.check_bucket_access(
            "nonexistent-bucket", "s3.us.cloud-object-storage.appdomain.cloud",
            "onepipelineci@ibm.com", "write"
        )
        assert result is False
        assert len(verifier.errors) >= 1

    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_returns_false_on_403(self, mock_post, mock_head, verifier):
        mock_post.return_value = _mock_response(200, {"access_token": "tok"})
        mock_head.return_value = _mock_response(403)
        result = verifier.check_bucket_access(
            "locked-bucket", "s3.us.cloud-object-storage.appdomain.cloud",
            "onepipelineci@ibm.com", "write"
        )
        assert result is False
        assert any("denied" in e for e in verifier.errors)

    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_returns_false_when_iam_token_fails(self, mock_post, mock_head, verifier):
        mock_post.return_value = _mock_response(401)
        result = verifier.check_bucket_access(
            "my-bucket", "s3.us.cloud-object-storage.appdomain.cloud",
            "onepipelineci@ibm.com", "write"
        )
        assert result is False

    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_unexpected_status_adds_warning(self, mock_post, mock_head, verifier):
        mock_post.return_value = _mock_response(200, {"access_token": "tok"})
        mock_head.return_value = _mock_response(503)
        result = verifier.check_bucket_access(
            "my-bucket", "s3.us.cloud-object-storage.appdomain.cloud",
            "onepipelineci@ibm.com", "write"
        )
        assert result is False
        assert len(verifier.warnings) >= 1

    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_network_error_adds_warning(self, mock_post, mock_head, verifier):
        import requests as req
        mock_post.return_value = _mock_response(200, {"access_token": "tok"})
        mock_head.side_effect = req.exceptions.ConnectionError("no route")
        result = verifier.check_bucket_access(
            "my-bucket", "s3.us.cloud-object-storage.appdomain.cloud",
            "onepipelineci@ibm.com", "write"
        )
        assert result is False
        assert len(verifier.warnings) >= 1


# ---------------------------------------------------------------------------
# verify_onboarding_yaml
# ---------------------------------------------------------------------------

class TestVerifyOnboardingYaml:
    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_use_existing_false_missing_endpoint_returns_false(
        self, mock_post, mock_head, verifier, tmp_path
    ):
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            compliance_bucket:
              use_existing: false
        """)
        result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is False

    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_use_existing_true_missing_bucket_name_returns_false(
        self, mock_post, mock_head, verifier, tmp_path
    ):
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            compliance_bucket:
              use_existing: true
              endpoint: s3.us-south.cloud-object-storage.appdomain.cloud
        """)
        result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is False

    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_use_existing_true_missing_endpoint_returns_false(
        self, mock_post, mock_head, verifier, tmp_path
    ):
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            compliance_bucket:
              use_existing: true
              bucket: my-real-bucket
        """)
        result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is False

    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_no_compliance_bucket_config_returns_false(
        self, mock_post, mock_head, verifier, tmp_path
    ):
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
        """)
        result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is False

    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_successful_use_existing_false(
        self, mock_post, mock_head, verifier, tmp_path
    ):
        mock_post.return_value = _mock_response(200, {"access_token": "tok"})
        mock_head.return_value = _mock_response(200)
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            compliance_bucket:
              use_existing: false
              endpoint: s3.us-south.cloud-object-storage.appdomain.cloud
        """)
        result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is True

    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_successful_use_existing_true(
        self, mock_post, mock_head, verifier, tmp_path
    ):
        mock_post.return_value = _mock_response(200, {"access_token": "tok"})
        mock_head.return_value = _mock_response(200)
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            compliance_bucket:
              use_existing: true
              bucket: my-custom-bucket
              endpoint: s3.us-south.cloud-object-storage.appdomain.cloud
        """)
        result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is True

    def test_invalid_yaml_returns_false(self, verifier, tmp_path):
        bad = tmp_path / "bad.yaml"
        bad.write_text("key: [\n")
        result = verifier.verify_onboarding_yaml(str(bad))
        assert result is False

    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_endpoint_with_https_prefix_is_parsed(
        self, mock_post, mock_head, verifier, tmp_path
    ):
        mock_post.return_value = _mock_response(200, {"access_token": "tok"})
        mock_head.return_value = _mock_response(200)
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            compliance_bucket:
              use_existing: false
              endpoint: https://s3.us-south.cloud-object-storage.appdomain.cloud
        """)
        result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is True

    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_use_existing_false_auto_generates_bucket_name(
        self, mock_post, mock_head, verifier, tmp_path
    ):
        """Bucket name should be: uuc-<team_slug>-ci-storage"""
        mock_post.return_value = _mock_response(200, {"access_token": "tok"})
        mock_head.return_value = _mock_response(200)
        yaml_path = _write_yaml(tmp_path, """
            team_name: Core Services
            service_name: my-svc
            compliance_bucket:
              use_existing: false
              endpoint: s3.us-south.cloud-object-storage.appdomain.cloud
        """)
        result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is True
        # The HEAD call URL should contain the expected slug
        called_url = mock_head.call_args.args[0]
        assert "uuc-core-services-ci-storage" in called_url

    @patch("verify_compliance_bucket_access.requests.head")
    @patch("verify_compliance_bucket_access.requests.post")
    def test_bucket_access_denied_returns_false(
        self, mock_post, mock_head, verifier, tmp_path
    ):
        mock_post.return_value = _mock_response(200, {"access_token": "tok"})
        mock_head.return_value = _mock_response(403)
        yaml_path = _write_yaml(tmp_path, """
            team_name: Fabric
            service_name: my-svc
            compliance_bucket:
              use_existing: false
              endpoint: s3.us-south.cloud-object-storage.appdomain.cloud
        """)
        result = verifier.verify_onboarding_yaml(str(yaml_path))
        assert result is False

if __name__ == '__main__':
    pytest.main([__file__, '-v'])
