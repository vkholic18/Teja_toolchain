import unittest
import json, os
from unittest.mock import patch, MagicMock
import logging
import configure_features_api_data

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(os.path.basename(__file__))
class TestConfigureFeaturesApiData(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.test_str = json.dumps({"test_key": "test_value"}, indent=4)
    @patch('configure_featureflags.build_config', return_value='config')
    @patch('configure_featureflags.write_config', return_value=None)
    def test_export_features_api_configmap(self, mock_write_config, mock_merge_config):
        configure_features_api_data.export_configmap_data(self.test_str, "genctl-ci-repo")
        self.assertEqual(mock_merge_config.call_count, 1)
        pwd = "genctl-ci-repo/scripts/configure_featureflags/"
        mock_write_config.assert_any_call('config', pwd + configure_features_api_data.rias_base_yaml_for_features_api.replace("base-", ""))

    @patch('builtins.open',
           read_data='{"apps": {"feature_flags": {"api_spec_version": "1.0.0"}}}')
    @patch('yaml.load')
    def test_get_api_spec_release_version(self, mock_yaml_load, mock_open):
        mock_yaml_load.return_value = {
            'apps': {
                'feature_flags': {
                    'api_spec_version': '1.0.0'
                }
            }
        }
        result = configure_features_api_data.get_api_spec_release_version('dummy_file.yaml')
        self.assertEqual(result, '1.0.0')

    @patch.dict(os.environ, {'GHE_API_TOKEN': 'fake_token', 'GHE_API_URL': 'https://fake_url'})
    @patch('github.Github')
    def download_features_api_data_from_git(self, MockGithub):
        # Mocking the GitHub API
        mock_repo = MagicMock()
        mock_tag = MagicMock()
        mock_tag.name = 'v1.0.0'
        mock_tag.commit.sha = 'fake_sha'
        mock_repo.get_tags.return_value = [mock_tag]
        mock_content = MagicMock()
        mock_content.decoded_content = b"""
            $features:
              feature1: description1
              feature2: description2
            """
        mock_repo.get_contents.return_value = mock_content
        mock_github_instance = MockGithub.return_value
        mock_github_instance.get_repo.return_value = mock_repo

        result = configure_features_api_data.download_features_api_data_from_git('fake_repo', 'fake_file.yaml',  'v1.0.0')

        self.assertEqual(result, {'feature1': 'description1', 'feature2': 'description2'})
        mock_github_instance.get_repo.assert_called_once_with('fake_repo')
        mock_repo.get_tags.assert_called_once()
        mock_repo.get_contents.assert_called_once_with('fake_file.yaml', ref='fake_sha')


    @patch('sys.exit')
    @patch('configure_features_api_data.logger', logger)
    def test_maturity_missing_in_feature_flag_repository(self, mock_sys_exit):
        feature_list = [{"name": "test_feature", "maturity": "beta"}]
        enabled_flags = {
            "apps": {
                "feature_flags": {
                    "vpc": [
                        {
                            "name": "test_feature",
                            "default": {"variation_value": {}},
                            "off_variation": {}
                        }
                    ]
                }
            }
        }

        with self.assertLogs(logger, level='ERROR') as log:
            configure_features_api_data.validate_flags_spec_drift(feature_list, enabled_flags)
            self.assertIn(
                "'test_feature' is defined as Maturity flag in api-spec and is missing maturity in feature flag repository.",
                log.output[0]
            )
        mock_sys_exit.assert_called_once_with(1)

    @patch('sys.exit')
    @patch('configure_features_api_data.logger', logger)
    def test_boolean_flag_with_maturity_in_feature_flag_repository(self, mock_sys_exit):
        feature_list = [{"name": "test_feature", "maturity": None}]
        enabled_flags = {
            "apps": {
                "feature_flags": {
                    "vpc": [
                        {
                            "name": "test_feature",
                            "default": {"variation_value": {"maturity": "ga"}},
                            "off_variation": {"maturity": "development"}
                        }
                    ]
                }
            }
        }

        with patch.object(logger, 'error') as mock_log_error:
            configure_features_api_data.validate_flags_spec_drift(feature_list, enabled_flags)
            mock_log_error.assert_called_once_with(
                "'test_feature' is defined as Boolean flag in api-spec but it is configured with a maturity value in feature flag repository"
            )
        mock_sys_exit.assert_called_once_with(1)

if __name__ == "__main__":
    unittest.main()