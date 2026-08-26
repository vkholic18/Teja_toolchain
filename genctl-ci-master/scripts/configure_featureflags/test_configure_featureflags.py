import unittest
from configure_featureflags import *
from unittest.mock import patch


class TestConfigureFeatureFlags(unittest.TestCase):
    test_yaml = "test_file.yaml"
    test_config_yaml = "test_config.yaml"

    @classmethod
    def setUpClass(cls) -> None:
        cls.test_str = json.dumps({"test_key": "test_value"}, indent=4)
        with open(cls.test_yaml, "w") as file:
            file.write("test content")

        with open(cls.test_config_yaml, 'wb') as f:
            f.write(b'o' * 850 * 1024)

    @classmethod
    def tearDownClass(cls) -> None:
        for file_path in [cls.test_yaml, cls.test_config_yaml]:
            if os.path.exists(file_path):
                os.remove(file_path)

    @patch('configure_featureflags.build_config', return_value='config')
    @patch('configure_featureflags.write_config', return_value=None)
    def test_export_configmap(self, mock_write_config, mock_merge_config):
        export_configmap(self.test_str, "genctl-ci-repo")
        self.assertEqual(mock_merge_config.call_count, 3)

        pwd = "genctl-ci-repo/scripts/configure_featureflags/"
        mock_write_config.assert_any_call('config' + "\n    {{/each}}", pwd + rias_base_yaml.replace("base-", ""))
        mock_write_config.assert_called_with('config', pwd + rias_base_ns_yaml.format("rias-etcd"))

    def test_write_config(self):
        test_file = "test_config.yaml"
        try:
            write_config("test config", test_file)
            self.assertTrue(os.path.exists(test_file))
        finally:
            if os.path.exists(test_file):
                os.remove(test_file)

    def test_adjust_indentation(self):
        test_indented = adjust_indentation(self.test_str, 2, 2)
        expected_result = "  {\n    \"test_key\": \"test_value\"\n  }"
        self.assertEqual(test_indented, expected_result)

    def test_spaces(self):
        space_str = spaces(3)
        self.assertEqual(space_str, "   ")

    def test_build_config(self):
        test_cofig = build_config(self.test_str, self.test_yaml, 2, 2)
        expect = "test content\n  {\n    \"test_key\": \"test_value\"\n  }"
        self.assertEqual(test_cofig, expect)

    def test_validate_configmap_size(self) -> None:
        with self.assertRaises(ValueError) as context:
            validate_configmap_size(self.test_config_yaml)
        self.assertIn("exceeds the maximum file size limit", str(context.exception))

    @patch('configure_featureflags.os.listdir')
    @patch('configure_featureflags.os.path.isdir')
    @patch('configure_featureflags.load_yaml_file')
    def test_combine_flags(self, mock_load_yaml, mock_isdir, mock_listdir):
        mock_isdir.return_value = True
        mock_listdir.return_value = ['service1_flags.yaml', 'service2_flags.yaml']
        mock_load_yaml.side_effect = [
            {'apps': {'feature_flags': {'vpc': ['env_yaml_data']}}},
            {'apps': {'feature_flags': {'vpc': ['service1_flags_data']}}},
            {'apps': {'feature_flags': {'vpc': ['service2_flags_data']}}}
        ]

        expected_result = {
            'apps': {
                'feature_flags': {
                    'vpc': ['env_yaml_data', 'service1_flags_data', 'service2_flags_data']
                }
            }
        }

        result = combine_flags('environment.yaml', 'service_flags_path/')

        self.assertEqual(result, expected_result)
        mock_load_yaml.assert_any_call('environment.yaml')
        mock_load_yaml.assert_any_call('service_flags_path/service1_flags.yaml')
        mock_load_yaml.assert_any_call('service_flags_path/service2_flags.yaml')

        mock_isdir.assert_called_once_with('service_flags_path/')
        self.assertEqual(mock_listdir.call_count, 2, "Expected 'listdir' to be called twice")


if __name__ == "__main__":
    unittest.main()
