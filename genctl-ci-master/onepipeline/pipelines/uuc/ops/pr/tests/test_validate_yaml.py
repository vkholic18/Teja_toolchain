#!/usr/bin/env python3
"""
Tests for validate_yaml.py

Covers every public validator function with both positive (happy-path) and
negative (error/warning) cases.  The module uses global mutable counters
(errors, warnings) so each test resets them via the helper reset_counters().
"""

import importlib
import os
import sys
import tempfile
import textwrap
from pathlib import Path
from unittest.mock import patch

import pytest

# ---------------------------------------------------------------------------
# Path setup — make the steps package importable
# ---------------------------------------------------------------------------
STEPS_DIR = Path(__file__).resolve().parents[1] / "steps"
sys.path.insert(0, str(STEPS_DIR))

import validate_yaml as vy  # noqa: E402


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def reset_counters():
    """Reset the module-level error/warning counters before each test."""
    vy.errors = 0
    vy.warnings = 0


# ---------------------------------------------------------------------------
# _get_cicd_profile
# ---------------------------------------------------------------------------

class TestGetCicdProfile:
    def test_returns_profile_when_present(self):
        assert vy._get_cicd_profile({'cicd_profile': 'ci_cd'}) == 'ci_cd'

    def test_returns_none_when_missing(self):
        assert vy._get_cicd_profile({}) is None

    def test_returns_none_for_empty_string(self):
        # yaml may parse an empty value as None
        assert vy._get_cicd_profile({'cicd_profile': None}) is None


# ---------------------------------------------------------------------------
# validate_cicd_profile
# ---------------------------------------------------------------------------

class TestValidateCicdProfile:
    def setup_method(self):
        reset_counters()

    def test_valid_minimal(self):
        vy.validate_cicd_profile({'cicd_profile': 'minimal'})
        assert vy.errors == 0

    def test_valid_ci_only(self):
        vy.validate_cicd_profile({'cicd_profile': 'ci_only'})
        assert vy.errors == 0

    def test_valid_ci_cd(self):
        vy.validate_cicd_profile({'cicd_profile': 'ci_cd'})
        assert vy.errors == 0

    def test_missing_profile_raises_error(self):
        vy.validate_cicd_profile({})
        assert vy.errors == 1

    def test_invalid_profile_raises_error(self):
        vy.validate_cicd_profile({'cicd_profile': 'full_deployment'})
        assert vy.errors == 1

    def test_none_profile_raises_error(self):
        vy.validate_cicd_profile({'cicd_profile': None})
        assert vy.errors == 1


# ---------------------------------------------------------------------------
# validate_team_name
# ---------------------------------------------------------------------------

class TestValidateTeamName:
    def setup_method(self):
        reset_counters()

    def test_valid_exact_team_name(self):
        vy.validate_team_name({'team_name': 'Fabric'})
        assert vy.errors == 0

    def test_valid_case_insensitive(self):
        # lower-case accepted but triggers a warning
        vy.validate_team_name({'team_name': 'fabric'})
        assert vy.errors == 0
        assert vy.warnings == 1  # canonical form warning

    def test_missing_team_name(self):
        vy.validate_team_name({})
        assert vy.errors == 1

    def test_placeholder_myteamname(self):
        vy.validate_team_name({'team_name': 'myteamname'})
        assert vy.errors == 1

    def test_invalid_team_name(self):
        vy.validate_team_name({'team_name': 'InvalidTeam'})
        assert vy.errors == 1

    def test_empty_string_team_name(self):
        vy.validate_team_name({'team_name': ''})
        assert vy.errors == 1

    def test_all_valid_teams(self):
        for team in vy.VALID_TEAMS:
            reset_counters()
            vy.validate_team_name({'team_name': team})
            assert vy.errors == 0, f"Expected no errors for team '{team}'"


# ---------------------------------------------------------------------------
# validate_service_name
# ---------------------------------------------------------------------------

class TestValidateServiceName:
    def setup_method(self):
        reset_counters()

    def test_valid_service_name(self):
        vy.validate_service_name({'service_name': 'my-cool-service'})
        assert vy.errors == 0

    def test_valid_service_name_underscores(self):
        vy.validate_service_name({'service_name': 'cool_service_v2'})
        assert vy.errors == 0

    def test_missing_service_name(self):
        vy.validate_service_name({})
        assert vy.errors == 1

    def test_placeholder_myservicename(self):
        vy.validate_service_name({'service_name': 'myservicename'})
        assert vy.errors == 1

    def test_invalid_characters(self):
        vy.validate_service_name({'service_name': 'bad name!'})
        assert vy.errors == 1

    def test_placeholder_warning(self):
        vy.validate_service_name({'service_name': 'myservice-v1'})
        assert vy.warnings >= 1

    def test_empty_string(self):
        vy.validate_service_name({'service_name': ''})
        assert vy.errors == 1


# ---------------------------------------------------------------------------
# validate_functional_ids
# ---------------------------------------------------------------------------

class TestValidateFunctionalIds:
    def setup_method(self):
        reset_counters()

    def _base_data(self, profile='ci_cd'):
        return {
            'cicd_profile': profile,
            'service_fid_dev': 'dev-fid@ibm.com',
            'service_fid_prod': 'prod-fid@ibm.com',
        }

    def test_valid_ci_cd(self):
        vy.validate_functional_ids(self._base_data('ci_cd'))
        assert vy.errors == 0

    def test_valid_minimal_no_prod_fid(self):
        data = {'cicd_profile': 'minimal', 'service_fid_dev': 'dev-fid@ibm.com'}
        vy.validate_functional_ids(data)
        assert vy.errors == 0

    def test_missing_dev_fid(self):
        data = self._base_data()
        del data['service_fid_dev']
        vy.validate_functional_ids(data)
        assert vy.errors >= 1

    def test_missing_prod_fid_ci_cd(self):
        data = {'cicd_profile': 'ci_cd', 'service_fid_dev': 'dev@ibm.com'}
        vy.validate_functional_ids(data)
        assert vy.errors >= 1

    def test_placeholder_dev_fid(self):
        data = {'cicd_profile': 'ci_cd', 'service_fid_dev': 'my_fid@ibm.com',
                'service_fid_prod': 'prod@ibm.com'}
        vy.validate_functional_ids(data)
        assert vy.errors >= 1

    def test_placeholder_prod_fid(self):
        data = {'cicd_profile': 'ci_cd', 'service_fid_dev': 'dev@ibm.com',
                'service_fid_prod': 'my_fid_prod@ibm.com'}
        vy.validate_functional_ids(data)
        assert vy.errors >= 1

    def test_invalid_email_format(self):
        data = {'cicd_profile': 'ci_cd', 'service_fid_dev': 'notanemail',
                'service_fid_prod': 'prod@ibm.com'}
        vy.validate_functional_ids(data)
        assert vy.errors >= 1

    def test_same_dev_and_prod_fid_warns(self):
        data = {'cicd_profile': 'ci_cd', 'service_fid_dev': 'same@ibm.com',
                'service_fid_prod': 'same@ibm.com'}
        vy.validate_functional_ids(data)
        assert vy.warnings >= 1


# ---------------------------------------------------------------------------
# validate_inventory_repo
# ---------------------------------------------------------------------------

class TestValidateInventoryRepo:
    def setup_method(self):
        reset_counters()

    def _valid_data(self):
        return {
            'cicd_profile': 'ci_cd',
            'team_name': 'Fabric',
            'app_repo': [{'repo': 'https://github.ibm.com/fabric-org/myapp', 'branch': 'main'}],
            'inventory_repo': {
                'repo': 'https://github.ibm.com/fabric-org/uuc-fabric-myapp-compliance-inventory',
                'branch': 'main',
                'create': False,
            },
        }

    def test_minimal_skips_inventory(self):
        data = {'cicd_profile': 'minimal'}
        vy.validate_inventory_repo(data)
        assert vy.errors == 0

    def test_valid_inventory_repo(self):
        vy.validate_inventory_repo(self._valid_data())
        assert vy.errors == 0

    def test_missing_repo_url(self):
        data = self._valid_data()
        data['inventory_repo']['repo'] = None
        vy.validate_inventory_repo(data)
        assert vy.errors >= 1

    def test_placeholder_repo(self):
        data = self._valid_data()
        data['inventory_repo']['repo'] = 'https://github.ibm.com/myorg/myinventoryrepo'
        vy.validate_inventory_repo(data)
        assert vy.errors >= 1

    def test_missing_branch(self):
        data = self._valid_data()
        data['inventory_repo']['branch'] = None
        vy.validate_inventory_repo(data)
        assert vy.errors >= 1

    def test_wrong_naming_convention(self):
        data = self._valid_data()
        data['inventory_repo']['repo'] = 'https://github.ibm.com/myorg/wrong-name'
        vy.validate_inventory_repo(data)
        assert vy.errors >= 1


# ---------------------------------------------------------------------------
# validate_incident_repo
# ---------------------------------------------------------------------------

class TestValidateIncidentRepo:
    def setup_method(self):
        reset_counters()

    def test_minimal_skips_incident(self):
        vy.validate_incident_repo({'cicd_profile': 'minimal'})
        assert vy.errors == 0

    def test_valid_incident_repo(self):
        data = {
            'cicd_profile': 'ci_cd',
            'incident_repo': {
                'repo': 'https://github.ibm.com/fabric-team/my-incident-repo',
                'branch': 'main',
                'create': False,
            },
        }
        vy.validate_incident_repo(data)
        assert vy.errors == 0

    def test_missing_repo(self):
        data = {
            'cicd_profile': 'ci_cd',
            'incident_repo': {'branch': 'main'},
        }
        vy.validate_incident_repo(data)
        assert vy.errors >= 1

    def test_placeholder_repo(self):
        data = {
            'cicd_profile': 'ci_cd',
            'incident_repo': {
                'repo': 'https://github.ibm.com/myorg/myincidentrepo',
                'branch': 'main',
            },
        }
        vy.validate_incident_repo(data)
        assert vy.errors >= 1

    def test_missing_branch(self):
        data = {
            'cicd_profile': 'ci_cd',
            'incident_repo': {'repo': 'https://github.ibm.com/myorg/real-incident-repo'},
        }
        vy.validate_incident_repo(data)
        assert vy.errors >= 1


# ---------------------------------------------------------------------------
# validate_compliance_bucket
# ---------------------------------------------------------------------------

class TestValidateComplianceBucket:
    def setup_method(self):
        reset_counters()

    def test_use_existing_false_success(self):
        data = {'compliance_bucket': {'use_existing': False}}
        vy.validate_compliance_bucket(data)
        assert vy.errors == 0

    def test_use_existing_true_valid(self):
        data = {
            'compliance_bucket': {
                'use_existing': True,
                'endpoint': 's3.us-south.cloud-object-storage.appdomain.cloud',
                'name': 'my-real-bucket',
            }
        }
        vy.validate_compliance_bucket(data)
        assert vy.errors == 0
        assert vy.warnings >= 1  # FID write-access reminder

    def test_use_existing_true_missing_endpoint(self):
        data = {
            'compliance_bucket': {
                'use_existing': True,
                'name': 'my-bucket',
            }
        }
        vy.validate_compliance_bucket(data)
        assert vy.errors >= 1

    def test_use_existing_true_missing_name(self):
        data = {
            'compliance_bucket': {
                'use_existing': True,
                'endpoint': 's3.us-south.cloud-object-storage.appdomain.cloud',
            }
        }
        vy.validate_compliance_bucket(data)
        assert vy.errors >= 1

    def test_use_existing_true_placeholder_endpoint(self):
        data = {
            'compliance_bucket': {
                'use_existing': True,
                'endpoint': 's3.eu-gb.cloud-object-storage.appdomain.cloud',
                'name': 'my-bucket',
            }
        }
        vy.validate_compliance_bucket(data)
        assert vy.errors >= 1

    def test_use_existing_true_placeholder_name(self):
        data = {
            'compliance_bucket': {
                'use_existing': True,
                'endpoint': 's3.us-south.cloud-object-storage.appdomain.cloud',
                'name': 'my_bucket',
            }
        }
        vy.validate_compliance_bucket(data)
        assert vy.errors >= 1


# ---------------------------------------------------------------------------
# validate_app_repo
# ---------------------------------------------------------------------------

class TestValidateAppRepo:
    def setup_method(self):
        reset_counters()

    def test_valid_app_repo(self):
        data = {
            'app_repo': [
                {'repo': 'https://github.ibm.com/fabric-org/real-app', 'branch': 'main'}
            ]
        }
        vy.validate_app_repo(data)
        assert vy.errors == 0

    def test_no_app_repos(self):
        vy.validate_app_repo({'app_repo': []})
        assert vy.errors == 1

    def test_missing_app_repo_key(self):
        vy.validate_app_repo({})
        assert vy.errors == 1

    def test_placeholder_repo(self):
        data = {
            'app_repo': [
                {'repo': 'https://github.ibm.com/myorg/myrepo', 'branch': 'main'}
            ]
        }
        vy.validate_app_repo(data)
        assert vy.errors >= 1

    def test_missing_branch(self):
        data = {
            'app_repo': [
                {'repo': 'https://github.ibm.com/org/real-app'}
            ]
        }
        vy.validate_app_repo(data)
        assert vy.errors >= 1

    def test_multiple_repos_valid(self):
        data = {
            'app_repo': [
                {'repo': 'https://github.ibm.com/org/app-a', 'branch': 'main'},
                {'repo': 'https://github.ibm.com/org/app-b', 'branch': 'main'},
            ]
        }
        vy.validate_app_repo(data)
        assert vy.errors == 0


# ---------------------------------------------------------------------------
# validate_psirt_id
# ---------------------------------------------------------------------------

class TestValidatePsirtId:
    def setup_method(self):
        reset_counters()

    def test_minimal_skips_psirt(self):
        vy.validate_psirt_id({'cicd_profile': 'minimal'})
        assert vy.errors == 0

    def test_valid_psirt_id(self):
        vy.validate_psirt_id({'cicd_profile': 'ci_cd', 'psirt_id': 'PSIRT_PRD1234567'})
        assert vy.errors == 0

    def test_missing_psirt_id(self):
        vy.validate_psirt_id({'cicd_profile': 'ci_cd'})
        assert vy.errors >= 1

    def test_placeholder_psirt_id(self):
        vy.validate_psirt_id({'cicd_profile': 'ci_cd', 'psirt_id': 'PSIRT_PRD000XXXX'})
        assert vy.errors >= 1

    def test_all_zeros_psirt_id(self):
        vy.validate_psirt_id({'cicd_profile': 'ci_cd', 'psirt_id': 'PSIRT_PRD0000000'})
        assert vy.errors >= 1

    def test_wrong_format_psirt_id(self):
        vy.validate_psirt_id({'cicd_profile': 'ci_cd', 'psirt_id': 'PSIRT-1234567'})
        assert vy.errors >= 1

    def test_too_few_digits(self):
        vy.validate_psirt_id({'cicd_profile': 'ci_cd', 'psirt_id': 'PSIRT_PRD12345'})
        assert vy.errors >= 1

    def test_too_many_digits(self):
        vy.validate_psirt_id({'cicd_profile': 'ci_cd', 'psirt_id': 'PSIRT_PRD12345678'})
        assert vy.errors >= 1


# ---------------------------------------------------------------------------
# validate_servicenow_crn_mask
# ---------------------------------------------------------------------------

class TestValidateServicenowCrnMask:
    def setup_method(self):
        reset_counters()

    def test_valid_crn_mask(self):
        vy.validate_servicenow_crn_mask({'servicenow_crn_mask': 'crn:v1:bluemix:public:fabric-service:::::'})
        assert vy.errors == 0

    def test_valid_crn_mask_all_profiles(self):
        for profile in ['minimal', 'ci_only', 'ci_cd']:
            reset_counters()
            vy.validate_servicenow_crn_mask({
                'cicd_profile': profile,
                'servicenow_crn_mask': 'crn:v1:bluemix:public:my-service:::::',
            })
            assert vy.errors == 0, f"Expected no errors for profile '{profile}'"

    def test_missing_field_errors(self):
        vy.validate_servicenow_crn_mask({})
        assert vy.errors == 1

    def test_none_value_errors(self):
        vy.validate_servicenow_crn_mask({'servicenow_crn_mask': None})
        assert vy.errors == 1

    def test_empty_string_errors(self):
        vy.validate_servicenow_crn_mask({'servicenow_crn_mask': ''})
        assert vy.errors == 1

    def test_placeholder_value_errors(self):
        vy.validate_servicenow_crn_mask({'servicenow_crn_mask': '<your_servicenow_crn_mask>'})
        assert vy.errors == 1

    def test_placeholder_with_surrounding_whitespace_errors(self):
        vy.validate_servicenow_crn_mask({'servicenow_crn_mask': '  <your_servicenow_crn_mask>  '})
        assert vy.errors == 1


# ---------------------------------------------------------------------------
# validate_ibm_cloud_accounts
# ---------------------------------------------------------------------------

class TestValidateIbmCloudAccounts:
    def setup_method(self):
        reset_counters()

    def test_both_accounts_provided(self):
        data = {
            'ibm_cloud_account_dev': 'real-dev-account',
            'ibm_cloud_account_prod': 'real-prod-account',
        }
        vy.validate_ibm_cloud_accounts(data)
        assert vy.errors == 0
        assert vy.warnings == 0

    def test_no_accounts_warns(self):
        vy.validate_ibm_cloud_accounts({})
        assert vy.warnings == 2

    def test_placeholder_dev_account_warns(self):
        data = {'ibm_cloud_account_dev': 'my_dev_account', 'ibm_cloud_account_prod': 'real-prod'}
        vy.validate_ibm_cloud_accounts(data)
        assert vy.warnings >= 1

    def test_placeholder_prod_account_warns(self):
        data = {'ibm_cloud_account_dev': 'real-dev', 'ibm_cloud_account_prod': 'my_prod_account'}
        vy.validate_ibm_cloud_accounts(data)
        assert vy.warnings >= 1


# ---------------------------------------------------------------------------
# validate_slack_config
# ---------------------------------------------------------------------------

class TestValidateSlackConfig:
    def setup_method(self):
        reset_counters()

    def test_valid_slack_members(self):
        data = {'slack_member_ids': ['UABC123456', 'UXYZ789012']}
        vy.validate_slack_config(data)
        assert vy.errors == 0

    def test_missing_slack_member_ids(self):
        vy.validate_slack_config({})
        assert vy.errors >= 1

    def test_example_slack_ids(self):
        data = {'slack_member_ids': ['U01234ABCDE', 'UREAL789012']}
        vy.validate_slack_config(data)
        assert vy.errors >= 1

    def test_valid_slack_channel(self):
        data = {
            'slack_member_ids': ['UABC123456'],
            'slack_channel': 'fabric-ci-alerts',
        }
        vy.validate_slack_config(data)
        assert vy.errors == 0

    def test_placeholder_slack_channel(self):
        data = {
            'slack_member_ids': ['UABC123456'],
            'slack_channel': 'my-team-alerts',
        }
        vy.validate_slack_config(data)
        assert vy.errors >= 1


# ---------------------------------------------------------------------------
# validate_secrets
# ---------------------------------------------------------------------------

class TestValidateSecrets:
    def setup_method(self):
        reset_counters()

    def _common_secrets(self):
        return [
            {'name': 'service-functional-id-dev-cloud-apikey',
             'description': 'Service functional ID dev IBM Cloud API key (used for ICR, Secrets Manager, and cloud resources)',
             'mandatory': True},
            {'name': 'service-functional-id-prod-cloud-apikey',
             'description': 'Service functional ID production IBM Cloud API key (used for ICR, Secrets Manager, and cloud resources)',
             'mandatory': True},
            {'name': 'service-functional-id-dev-ghe-pat',
             'description': 'Service functional ID dev GitHub Enterprise personal access token (used for repository access)',
             'mandatory': True},
            {'name': 'service-functional-id-prod-ghe-pat',
             'description': 'Service functional ID production GitHub Enterprise personal access token (used for repository access)',
             'mandatory': True},
        ]

    def _ci_secrets(self):
        return [
            {'name': 'gara-signing-credentials', 'description': 'GARA code signing credentials', 'mandatory': True},
            {'name': 'gara-signing-key', 'description': 'GARA code signing key', 'mandatory': True},
            {'name': 'mend-org-token', 'description': 'Mend SAST organization token', 'mandatory': True},
            {'name': 'mend-user-key', 'description': 'Mend SAST user key', 'mandatory': True},
            {'name': 'mend-product-token', 'description': 'Mend SAST product token', 'mandatory': True},
        ]

    def test_no_secrets_defined(self):
        vy.validate_secrets({'cicd_profile': 'ci_cd', 'secrets': []})
        assert vy.errors >= 1

    def test_valid_minimal_common_secrets(self):
        data = {
            'cicd_profile': 'minimal',
            'team_name': 'Fabric',
            'secrets': [{'name': 'common', 'items': self._common_secrets()}],
        }
        vy.validate_secrets(data)
        assert vy.errors == 0

    def test_missing_mandatory_secret(self):
        common = self._common_secrets()[:-1]  # remove one mandatory
        data = {
            'cicd_profile': 'minimal',
            'team_name': 'Fabric',
            'secrets': [{'name': 'common', 'items': common}],
        }
        vy.validate_secrets(data)
        assert vy.errors >= 1

    def test_custom_secret_with_mandatory_true_errors(self):
        items = self._common_secrets() + [
            {'name': 'my-custom-secret', 'description': 'My custom secret', 'mandatory': True}
        ]
        data = {
            'cicd_profile': 'minimal',
            'team_name': 'Fabric',
            'secrets': [{'name': 'common', 'items': items}],
        }
        vy.validate_secrets(data)
        assert vy.errors >= 1

    def test_secret_with_placeholder_name_warns(self):
        items = self._common_secrets() + [
            {'name': '<your_secret_name>', 'description': 'desc', 'mandatory': False}
        ]
        data = {
            'cicd_profile': 'minimal',
            'team_name': 'Fabric',
            'secrets': [{'name': 'common', 'items': items}],
        }
        vy.validate_secrets(data)
        assert vy.warnings >= 1

    def test_secret_missing_name(self):
        items = self._common_secrets() + [
            {'description': 'desc', 'mandatory': False}
        ]
        data = {
            'cicd_profile': 'minimal',
            'team_name': 'Fabric',
            'secrets': [{'name': 'common', 'items': items}],
        }
        vy.validate_secrets(data)
        assert vy.errors >= 1

    def test_secret_missing_description(self):
        items = self._common_secrets() + [
            {'name': 'custom-secret', 'mandatory': False}
        ]
        data = {
            'cicd_profile': 'minimal',
            'team_name': 'Fabric',
            'secrets': [{'name': 'common', 'items': items}],
        }
        vy.validate_secrets(data)
        assert vy.errors >= 1

    def test_secret_missing_mandatory_flag(self):
        items = self._common_secrets() + [
            {'name': 'custom-secret', 'description': 'desc'}
        ]
        data = {
            'cicd_profile': 'minimal',
            'team_name': 'Fabric',
            'secrets': [{'name': 'common', 'items': items}],
        }
        vy.validate_secrets(data)
        assert vy.errors >= 1

    def test_custom_secret_with_group_prefix_errors(self):
        items = self._common_secrets() + [
            {'name': 'sg-uuc-fabric-my-custom', 'description': 'desc', 'mandatory': False}
        ]
        data = {
            'cicd_profile': 'minimal',
            'team_name': 'Fabric',
            'secrets': [{'name': 'common', 'items': items}],
        }
        vy.validate_secrets(data)
        assert vy.errors >= 1


# ---------------------------------------------------------------------------
# validate_mandatory_files (YAML structure validation, not GitHub fetching)
# ---------------------------------------------------------------------------

class TestValidateMandatoryFilesYamlStructure:
    def setup_method(self):
        reset_counters()

    def _valid_ci_files(self):
        return [
            {'path': 'hack/ci/build.sh', 'can_be_empty': False, 'executable': True,
             'applies_to': ['minimal', 'ci_only', 'ci_cd']},
            {'path': 'hack/ci/run-unit-tests.sh', 'can_be_empty': False, 'executable': True,
             'applies_to': ['ci_only', 'ci_cd']},
            {'path': 'hack/ci/build-meta.yaml', 'can_be_empty': False, 'executable': False,
             'applies_to': ['ci_only', 'ci_cd']},
            {'path': 'hack/ci/pipeline.yaml', 'can_be_empty': False, 'executable': False,
             'applies_to': ['ci_only', 'ci_cd']},
        ]

    def _valid_cd_files(self):
        return [
            {'path': 'hack/cd/pre-reqs.sh', 'can_be_empty': False, 'executable': True,
             'applies_to': ['ci_cd']},
            {'path': 'hack/cd/deploy.sh', 'can_be_empty': False, 'executable': True,
             'applies_to': ['ci_cd']},
            {'path': 'hack/cd/acceptance-tests.sh', 'can_be_empty': False, 'executable': True,
             'applies_to': ['ci_cd']},
        ]

    def test_no_mandatory_file_groups(self):
        vy.validate_mandatory_files({'cicd_profile': 'ci_cd', 'mandatory_files': []})
        assert vy.errors >= 1

    def test_valid_ci_cd_groups(self):
        data = {
            'cicd_profile': 'ci_cd',
            'mandatory_files': [
                {
                    'name': 'CI',
                    'repo': 'https://github.ibm.com/org/app',
                    'branch': 'main',
                    'files': self._valid_ci_files(),
                },
                {
                    'name': 'CD',
                    'repo': 'https://github.ibm.com/org/app',
                    'branch': 'main',
                    'files': self._valid_cd_files(),
                },
            ],
        }
        vy.validate_mandatory_files(data)
        assert vy.errors == 0

    def test_ci_only_skips_cd_group(self):
        data = {
            'cicd_profile': 'ci_only',
            'mandatory_files': [
                {
                    'name': 'CI',
                    'repo': 'https://github.ibm.com/org/app',
                    'branch': 'main',
                    'files': self._valid_ci_files(),
                },
                {
                    'name': 'CD',
                    'repo': 'https://github.ibm.com/org/app',
                    'branch': 'main',
                    'files': self._valid_cd_files(),
                },
            ],
        }
        vy.validate_mandatory_files(data)
        assert vy.errors == 0

    def test_minimal_profile_skips_cd(self):
        data = {
            'cicd_profile': 'minimal',
            'mandatory_files': [
                {
                    'name': 'CI',
                    'repo': 'https://github.ibm.com/org/app',
                    'branch': 'main',
                    'files': [{'path': 'hack/ci/build.sh', 'can_be_empty': False, 'executable': True,
                               'applies_to': ['minimal', 'ci_only', 'ci_cd']}],
                },
                {
                    'name': 'CD',
                    'repo': 'https://github.ibm.com/org/app',
                    'branch': 'main',
                    'files': self._valid_cd_files(),
                },
            ],
        }
        vy.validate_mandatory_files(data)
        assert vy.errors == 0

    def test_placeholder_repo_raises_error(self):
        data = {
            'cicd_profile': 'ci_cd',
            'mandatory_files': [
                {
                    'name': 'CI',
                    'repo': 'https://github.ibm.com/myorg/myrepo',
                    'branch': 'main',
                    'files': self._valid_ci_files(),
                },
            ],
        }
        vy.validate_mandatory_files(data)
        assert vy.errors >= 1

    def test_missing_branch_errors(self):
        data = {
            'cicd_profile': 'ci_cd',
            'mandatory_files': [
                {
                    'name': 'CI',
                    'repo': 'https://github.ibm.com/org/real-app',
                    'files': self._valid_ci_files(),
                },
            ],
        }
        vy.validate_mandatory_files(data)
        assert vy.errors >= 1

    def test_modified_executable_property_errors(self):
        files = self._valid_ci_files()
        files[0]['executable'] = False  # build.sh should be executable=True
        data = {
            'cicd_profile': 'ci_cd',
            'mandatory_files': [
                {
                    'name': 'CI',
                    'repo': 'https://github.ibm.com/org/app',
                    'branch': 'main',
                    'files': files,
                },
            ],
        }
        vy.validate_mandatory_files(data)
        assert vy.errors >= 1

    def test_custom_file_added_to_mandatory_errors(self):
        files = self._valid_ci_files() + [
            {'path': 'hack/ci/custom.sh', 'can_be_empty': False, 'executable': True}
        ]
        data = {
            'cicd_profile': 'ci_cd',
            'mandatory_files': [
                {
                    'name': 'CI',
                    'repo': 'https://github.ibm.com/org/app',
                    'branch': 'main',
                    'files': files,
                },
            ],
        }
        vy.validate_mandatory_files(data)
        assert vy.errors >= 1

    def test_missing_required_ci_file_errors(self):
        files = [f for f in self._valid_ci_files() if f['path'] != 'hack/ci/build.sh']
        data = {
            'cicd_profile': 'ci_cd',
            'mandatory_files': [
                {
                    'name': 'CI',
                    'repo': 'https://github.ibm.com/org/app',
                    'branch': 'main',
                    'files': files,
                },
            ],
        }
        vy.validate_mandatory_files(data)
        assert vy.errors >= 1


    def _ci_group_with_overridden_file(self, path, override):
        """Return a full valid CI group but with one file entry replaced by override dict."""
        files = [f.copy() for f in self._valid_ci_files()]
        for i, f in enumerate(files):
            if f['path'] == path:
                files[i] = override
                break
        return {
            'cicd_profile': 'ci_cd',
            'mandatory_files': [{
                'name': 'CI',
                'repo': 'https://github.ibm.com/org/app',
                'branch': 'main',
                'files': files,
            }],
        }

    # --- applies_to positive cases ---

    def test_applies_to_all_profiles_valid(self):
        # All 4 valid files with full applies_to — no errors
        vy.validate_mandatory_files({
            'cicd_profile': 'ci_cd',
            'mandatory_files': [{
                'name': 'CI',
                'repo': 'https://github.ibm.com/org/app',
                'branch': 'main',
                'files': self._valid_ci_files(),
            }],
        })
        assert vy.errors == 0

    def test_applies_to_single_profile_valid(self):
        data = self._ci_group_with_overridden_file(
            'hack/ci/build.sh',
            {'path': 'hack/ci/build.sh', 'can_be_empty': False, 'executable': True,
             'applies_to': ['ci_cd']},
        )
        vy.validate_mandatory_files(data)
        assert vy.errors == 0

    def test_applies_to_two_profiles_valid(self):
        data = self._ci_group_with_overridden_file(
            'hack/ci/build.sh',
            {'path': 'hack/ci/build.sh', 'can_be_empty': False, 'executable': True,
             'applies_to': ['ci_only', 'ci_cd']},
        )
        vy.validate_mandatory_files(data)
        assert vy.errors == 0

    def test_applies_to_empty_list_is_valid(self):
        # [] means the team is opting this file out — allowed, no error
        data = self._ci_group_with_overridden_file(
            'hack/ci/build.sh',
            {'path': 'hack/ci/build.sh', 'can_be_empty': False, 'executable': True,
             'applies_to': []},
        )
        vy.validate_mandatory_files(data)
        assert vy.errors == 0

    # --- applies_to negative cases ---

    def test_applies_to_missing_errors(self):
        # applies_to key absent on one file — must error
        data = self._ci_group_with_overridden_file(
            'hack/ci/build.sh',
            {'path': 'hack/ci/build.sh', 'can_be_empty': False, 'executable': True},
        )
        vy.validate_mandatory_files(data)
        assert vy.errors >= 1

    def test_applies_to_not_a_list_errors(self):
        # applies_to is a plain string instead of a list
        data = self._ci_group_with_overridden_file(
            'hack/ci/build.sh',
            {'path': 'hack/ci/build.sh', 'can_be_empty': False, 'executable': True,
             'applies_to': 'ci_cd'},
        )
        vy.validate_mandatory_files(data)
        assert vy.errors >= 1

    def test_applies_to_invalid_value_errors(self):
        # one valid + one invalid value
        data = self._ci_group_with_overridden_file(
            'hack/ci/build.sh',
            {'path': 'hack/ci/build.sh', 'can_be_empty': False, 'executable': True,
             'applies_to': ['ci_cd', 'full_deploy']},
        )
        vy.validate_mandatory_files(data)
        assert vy.errors >= 1

    def test_applies_to_all_invalid_values_errors(self):
        # all values unrecognised
        data = self._ci_group_with_overridden_file(
            'hack/ci/build.sh',
            {'path': 'hack/ci/build.sh', 'can_be_empty': False, 'executable': True,
             'applies_to': ['unknown', 'invalid']},
        )
        vy.validate_mandatory_files(data)
        assert vy.errors >= 1


# ---------------------------------------------------------------------------
# validate_optional_files (YAML structure validation)
# ---------------------------------------------------------------------------

class TestValidateOptionalFilesYamlStructure:
    def setup_method(self):
        reset_counters()

    def test_no_optional_files_is_ok(self):
        vy.validate_optional_files({'cicd_profile': 'ci_cd', 'optional_files': []})
        assert vy.errors == 0

    def test_valid_optional_file_group(self):
        data = {
            'cicd_profile': 'ci_cd',
            'optional_files': [
                {
                    'name': 'mend',
                    'repo': 'https://github.ibm.com/org/app',
                    'branch': 'main',
                    'files': [{'path': 'wss-unified-agent.config', 'can_be_empty': False, 'executable': False}],
                }
            ],
        }
        vy.validate_optional_files(data)
        assert vy.errors == 0

    def test_minimal_skips_mend_group(self):
        data = {
            'cicd_profile': 'minimal',
            'optional_files': [
                {
                    'name': 'mend',
                    'repo': 'https://github.ibm.com/org/app',
                    'branch': 'main',
                    'files': [{'path': 'wss.config', 'can_be_empty': False, 'executable': False}],
                }
            ],
        }
        vy.validate_optional_files(data)
        assert vy.errors == 0

    def test_missing_repo_errors(self):
        data = {
            'cicd_profile': 'ci_cd',
            'optional_files': [
                {
                    'name': 'mend',
                    'branch': 'main',
                    'files': [{'path': 'wss.config', 'can_be_empty': False, 'executable': False}],
                }
            ],
        }
        vy.validate_optional_files(data)
        assert vy.errors >= 1

    def test_placeholder_repo_errors(self):
        data = {
            'cicd_profile': 'ci_cd',
            'optional_files': [
                {
                    'name': 'mend',
                    'repo': 'https://github.ibm.com/myorg/myrepo',
                    'branch': 'main',
                    'files': [{'path': 'wss.config', 'can_be_empty': False, 'executable': False}],
                }
            ],
        }
        vy.validate_optional_files(data)
        assert vy.errors >= 1

    def test_placeholder_branch_warns(self):
        data = {
            'cicd_profile': 'ci_cd',
            'optional_files': [
                {
                    'name': 'mend',
                    'repo': 'https://github.ibm.com/org/app',
                    'branch': 'default',
                    'files': [{'path': 'wss.config', 'can_be_empty': False, 'executable': False}],
                }
            ],
        }
        vy.validate_optional_files(data)
        assert vy.warnings >= 1

    def test_file_missing_can_be_empty_errors(self):
        data = {
            'cicd_profile': 'ci_cd',
            'optional_files': [
                {
                    'name': 'mend',
                    'repo': 'https://github.ibm.com/org/app',
                    'branch': 'main',
                    'files': [{'path': 'wss.config', 'executable': False}],
                }
            ],
        }
        vy.validate_optional_files(data)
        assert vy.errors >= 1

    def test_file_missing_executable_errors(self):
        data = {
            'cicd_profile': 'ci_cd',
            'optional_files': [
                {
                    'name': 'mend',
                    'repo': 'https://github.ibm.com/org/app',
                    'branch': 'main',
                    'files': [{'path': 'wss.config', 'can_be_empty': False}],
                }
            ],
        }
        vy.validate_optional_files(data)
        assert vy.errors >= 1


# ---------------------------------------------------------------------------
# validate_deployment_targets
# ---------------------------------------------------------------------------

class TestValidateDeploymentTargets:
    def setup_method(self):
        reset_counters()

    def _valid_data(self):
        return {
            'cicd_profile': 'ci_cd',
            'deployment_targets': {
                'CI': {
                    'vpc_ng': [
                        {'name': 'us-south-1', 'default_size': 'cx2.2x4'}
                    ]
                },
                'CD': {
                    'integration': {
                        'targets': 'all',
                        'type': 'zonal',
                        'default_size': 'cx2.2x4',
                    },
                    'staging': {
                        'targets': ['us-south'],
                        'type': 'regional',
                        'default_size': 'cx2.4x8',
                    },
                    'production': {
                        'targets': 'all',
                        'type': 'zonal',
                        'default_size': 'cx2.2x4',
                    },
                },
            },
        }

    def test_minimal_skips_deployment_targets(self):
        vy.validate_deployment_targets({'cicd_profile': 'minimal'})
        assert vy.errors == 0

    def test_ci_only_skips_deployment_targets(self):
        vy.validate_deployment_targets({'cicd_profile': 'ci_only'})
        assert vy.errors == 0

    def test_valid_ci_cd_targets(self):
        vy.validate_deployment_targets(self._valid_data())
        assert vy.errors == 0

    def test_missing_ci_targets(self):
        data = self._valid_data()
        del data['deployment_targets']['CI']
        vy.validate_deployment_targets(data)
        assert vy.errors >= 1

    def test_missing_vpc_ng_errors(self):
        data = self._valid_data()
        data['deployment_targets']['CI'] = {}
        vy.validate_deployment_targets(data)
        assert vy.errors >= 1

    def test_invalid_datacenter_type_errors(self):
        data = self._valid_data()
        data['deployment_targets']['CI']['custom_dc'] = [{'name': 'zone1', 'default_size': 'cx2.2x4'}]
        vy.validate_deployment_targets(data)
        assert vy.errors >= 1

    def test_missing_cd_environment_errors(self):
        data = self._valid_data()
        del data['deployment_targets']['CD']['production']
        vy.validate_deployment_targets(data)
        assert vy.errors >= 1

    def test_invalid_cd_environment_errors(self):
        data = self._valid_data()
        data['deployment_targets']['CD']['dev'] = {'targets': 'all', 'type': 'zonal', 'default_size': 'cx2.2x4'}
        vy.validate_deployment_targets(data)
        assert vy.errors >= 1

    def test_cd_environment_invalid_type(self):
        data = self._valid_data()
        data['deployment_targets']['CD']['integration']['type'] = 'multi'
        vy.validate_deployment_targets(data)
        assert vy.errors >= 1

    def test_cd_environment_missing_type(self):
        data = self._valid_data()
        del data['deployment_targets']['CD']['integration']['type']
        vy.validate_deployment_targets(data)
        assert vy.errors >= 1

    def test_cd_environment_missing_default_size(self):
        data = self._valid_data()
        del data['deployment_targets']['CD']['integration']['default_size']
        vy.validate_deployment_targets(data)
        assert vy.errors >= 1

    def test_ci_placeholder_zone_warns(self):
        data = self._valid_data()
        data['deployment_targets']['CI']['vpc_ng'] = [{'name': 'zone1', 'default_size': 'cx2.2x4'}]
        vy.validate_deployment_targets(data)
        assert vy.warnings >= 1


# ---------------------------------------------------------------------------
# validate_external_services
# ---------------------------------------------------------------------------

class TestValidateExternalServices:
    def setup_method(self):
        reset_counters()

    def test_no_external_services_is_ok(self):
        vy.validate_external_services({'external_services': []})
        assert vy.errors == 0

    def test_valid_external_service(self):
        data = {
            'external_services': [
                {'name': 'kafka', 'endpoint': 'https://kafka.example.com', 'type': 'regional'}
            ]
        }
        vy.validate_external_services(data)
        assert vy.errors == 0

    def test_missing_endpoint_errors(self):
        data = {
            'external_services': [
                {'name': 'kafka', 'type': 'regional'}
            ]
        }
        vy.validate_external_services(data)
        assert vy.errors >= 1

    def test_placeholder_endpoint_errors(self):
        data = {
            'external_services': [
                {'name': 'kafka', 'endpoint': '<url>', 'type': 'regional'}
            ]
        }
        vy.validate_external_services(data)
        assert vy.errors >= 1

    def test_missing_type_errors(self):
        data = {
            'external_services': [
                {'name': 'kafka', 'endpoint': 'https://kafka.example.com'}
            ]
        }
        vy.validate_external_services(data)
        assert vy.errors >= 1

    def test_invalid_type_errors(self):
        data = {
            'external_services': [
                {'name': 'kafka', 'endpoint': 'https://kafka.example.com', 'type': 'custom'}
            ]
        }
        vy.validate_external_services(data)
        assert vy.errors >= 1

    def test_type_with_pipe_placeholder_errors(self):
        data = {
            'external_services': [
                {'name': 'kafka', 'endpoint': 'https://kafka.example.com',
                 'type': 'zonal | regional | global'}
            ]
        }
        vy.validate_external_services(data)
        assert vy.errors >= 1

    def test_placeholder_service_name_warns(self):
        data = {
            'external_services': [
                {'name': 'event_stream', 'endpoint': 'https://real.com', 'type': 'zonal'}
            ]
        }
        vy.validate_external_services(data)
        assert vy.warnings >= 1


# ---------------------------------------------------------------------------
# validate_repo_consistency
# ---------------------------------------------------------------------------

class TestValidateRepoConsistency:
    def setup_method(self):
        reset_counters()

    def test_consistent_repos(self):
        data = {
            'app_repo': [{'repo': 'https://github.ibm.com/org/app', 'branch': 'main'}],
            'mandatory_files': [
                {'name': 'CI', 'repo': 'https://github.ibm.com/org/app', 'branch': 'main', 'files': []}
            ],
            'optional_files': [],
        }
        vy.validate_repo_consistency(data)
        assert vy.errors == 0

    def test_inconsistent_mandatory_repo(self):
        data = {
            'app_repo': [{'repo': 'https://github.ibm.com/org/app', 'branch': 'main'}],
            'mandatory_files': [
                {'name': 'CI', 'repo': 'https://github.ibm.com/org/other-app', 'branch': 'main', 'files': []}
            ],
            'optional_files': [],
        }
        vy.validate_repo_consistency(data)
        assert vy.errors >= 1

    def test_inconsistent_optional_branch(self):
        data = {
            'app_repo': [{'repo': 'https://github.ibm.com/org/app', 'branch': 'main'}],
            'mandatory_files': [],
            'optional_files': [
                {'name': 'mend', 'repo': 'https://github.ibm.com/org/app', 'branch': 'develop', 'files': []}
            ],
        }
        vy.validate_repo_consistency(data)
        assert vy.errors >= 1

    def test_no_app_repo_warns(self):
        data = {'app_repo': [], 'mandatory_files': [], 'optional_files': []}
        vy.validate_repo_consistency(data)
        assert vy.warnings >= 1


# ---------------------------------------------------------------------------
# validate_filename
# ---------------------------------------------------------------------------

class TestValidateFilename:
    def setup_method(self):
        reset_counters()

    def test_valid_service_filename(self):
        vy.validate_filename('/path/to/cool-app-onboarding.yaml', {'service_name': 'cool-app'})
        assert vy.errors == 0

    def test_wrong_filename(self):
        vy.validate_filename('/path/to/wrong-name.yaml', {'service_name': 'cool-app'})
        assert vy.errors >= 1

    def test_missing_service_name_warns(self):
        vy.validate_filename('/path/to/some.yaml', {})
        assert vy.warnings >= 1

    def test_placeholder_service_name_warns(self):
        vy.validate_filename('/path/to/myservicename-onboarding.yaml', {'service_name': 'myservicename'})
        assert vy.warnings >= 1

    def test_onboarding_yaml_template_accepted(self):
        # onboarding.yaml (template name) is acceptable when no PR context
        with patch.dict(os.environ, {}, clear=True):
            # no CHANGED_FILES, no PR_BASE_REF set
            vy.validate_filename('/path/to/onboarding.yaml', {'service_name': 'my-svc'})
        assert vy.errors == 0

    def test_onboarding_yaml_changed_in_pr_without_label_errors(self):
        with patch.dict(os.environ, {'CHANGED_FILES': 'M\tonboarding.yaml', 'PR_LABELS': ''}, clear=False):
            vy.validate_filename('/path/to/onboarding.yaml', {'service_name': 'my-svc'})
        assert vy.errors >= 1

    def test_onboarding_yaml_changed_in_pr_with_uuc_devops_label_warns(self):
        with patch.dict(os.environ, {
            'CHANGED_FILES': 'M\tonboarding.yaml',
            'PR_LABELS': 'uuc-devops',
        }, clear=False):
            reset_counters()
            vy.validate_filename('/path/to/onboarding.yaml', {'service_name': 'my-svc'})
        assert vy.errors == 0
        assert vy.warnings >= 1


# ---------------------------------------------------------------------------
# validate_branch_slug
# ---------------------------------------------------------------------------

class TestValidateBranchSlug:
    def setup_method(self):
        reset_counters()

    def test_matching_slug(self):
        with patch.dict(os.environ, {'PR_BASEBRANCH': 'fabric-onboarding'}):
            vy.validate_branch_slug({'team_name': 'Fabric'})
        assert vy.errors == 0

    def test_mismatched_slug_errors(self):
        with patch.dict(os.environ, {'PR_BASEBRANCH': 'fabric-onboarding'}):
            vy.validate_branch_slug({'team_name': 'VPC'})
        assert vy.errors >= 1

    def test_non_onboarding_branch_skips(self):
        with patch.dict(os.environ, {'PR_BASEBRANCH': 'main'}):
            vy.validate_branch_slug({'team_name': 'Fabric'})
        assert vy.errors == 0

    def test_no_pr_basebranch_warns(self):
        env = {k: v for k, v in os.environ.items() if k != 'PR_BASEBRANCH'}
        with patch.dict(os.environ, env, clear=True):
            vy.validate_branch_slug({'team_name': 'Fabric'})
        assert vy.warnings >= 1

    def test_placeholder_team_name_warns(self):
        with patch.dict(os.environ, {'PR_BASEBRANCH': 'fabric-onboarding'}):
            vy.validate_branch_slug({'team_name': 'myteamname'})
        assert vy.warnings >= 1

    def test_multi_word_team_slug(self):
        with patch.dict(os.environ, {'PR_BASEBRANCH': 'core-services-onboarding'}):
            vy.validate_branch_slug({'team_name': 'Core Services'})
        assert vy.errors == 0


# ---------------------------------------------------------------------------
# validate_pr_head_branch
# ---------------------------------------------------------------------------

class TestValidatePrHeadBranch:
    def setup_method(self):
        reset_counters()

    def test_valid_feature_branch(self):
        with patch.dict(os.environ, {'PR_BRANCH': 'feat/add-my-service'}):
            vy.validate_pr_head_branch()
        assert vy.errors == 0

    def test_onboarding_suffix_errors(self):
        with patch.dict(os.environ, {'PR_BRANCH': 'fabric-onboarding'}):
            vy.validate_pr_head_branch()
        assert vy.errors >= 1

    def test_any_prefix_with_onboarding_suffix_errors(self):
        with patch.dict(os.environ, {'PR_BRANCH': 'my-feature-onboarding'}):
            vy.validate_pr_head_branch()
        assert vy.errors >= 1

    def test_no_pr_branch_warns(self):
        env = {k: v for k, v in os.environ.items() if k != 'PR_BRANCH'}
        with patch.dict(os.environ, env, clear=True):
            vy.validate_pr_head_branch()
        assert vy.warnings >= 1

    def test_ticket_id_branch_valid(self):
        with patch.dict(os.environ, {'PR_BRANCH': 'CD-1234-add-fabric-service'}):
            vy.validate_pr_head_branch()
        assert vy.errors == 0


# ---------------------------------------------------------------------------
# load_yaml
# ---------------------------------------------------------------------------

class TestLoadYaml:
    def test_loads_valid_yaml(self, tmp_path):
        f = tmp_path / "test.yaml"
        f.write_text("key: value\n")
        result = vy.load_yaml(str(f))
        assert result == {'key': 'value'}

    def test_exits_on_missing_file(self):
        with pytest.raises(SystemExit):
            vy.load_yaml('/nonexistent/path/onboarding.yaml')

    def test_exits_on_invalid_yaml(self, tmp_path):
        f = tmp_path / "bad.yaml"
        f.write_text("key: [\n")  # invalid YAML
        with pytest.raises(SystemExit):
            vy.load_yaml(str(f))

if __name__ == '__main__':
    pytest.main([__file__, '-v'])
