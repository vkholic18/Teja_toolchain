import sys
import unittest
from unittest.mock import patch, mock_open
from validate_schema import *

script_dir = os.path.dirname(os.path.abspath(__file__))  # Get script's directory
schema_path = os.path.join(script_dir, "schema.yaml")   # Construct full path

with open(schema_path, "r") as file:
    schema = yaml.safe_load(file)

class TestSchema(unittest.TestCase):

    def test_yaml_schema_validator_valid(self):
        valid_yaml_content = {
            "name": "global-test",
            "issue_link": "https://github.ibm.com/genctl/IMF",
            "apps": {
                "feature_flags": {
                    "vpc": [
                        {
                            "name": "is-zbaremetal-phase1",
                            "on": True,
                            "default": {
                                "variation_value": "us-south-1 us-south-2 us-south-3"
                            },
                            "off_variation": "us-east-1 us-east-2 us-east-3"
                        },
                        {
                            "name": "genctl-network-gc-startup-interval",
                            "on": True,
                            "rules": [
                                {
                                    "clauses": [{
                                        "attribute": "mzone",
                                        "op": "in",
                                        "values": [
                                            {
                                                "mzone7430"
                                            }
                                        ]
                                    }],
                                    "variation_value": "7200"
                                }
                            ],
                            "default": {
                                "variation_value": "3600"
                            },
                            "off_variation": "7200"
                        }
                    ]
                }
            }
        }
        with patch('builtins.print') as mocked_print:
            yaml_schema_validator(valid_yaml_content, "dummy_path", schema)
            mocked_print.assert_called_with("Schema validation successful for dummy_path.")

    def test_yaml_schema_validator_invalid(self):
        invalid_yaml_content = {
            "apps": {
                "feature_flags": {
                    "vpc": [
                        {
                            "name": "test-flag-one"
                        }
                    ]
                }
            }
        }

        with self.assertRaises(Exception):
            yaml_schema_validator(invalid_yaml_content, "dummy_path", schema)

    def test_yaml_schema_validator_unsupported_field(self):
        test_content = {
            "apps": {
                "feature_flags": {
                    "vpc": [
                        {
                            "name": "test-flag-one",
                            "on": True,
                            "off_variation": "default",
                            "default": "value",
                            "extra_field": "not supported"
                        }
                    ]
                }
            }
        }

        with self.assertRaisesRegex(jsonschema.exceptions.ValidationError, "Additional properties are not allowed"):
            yaml_schema_validator(test_content, "dummy_path", schema)

    def test_load_yaml_file_not_found(self):
        with patch('builtins.open', side_effect=FileNotFoundError):
            with patch.object(logger, 'error') as mock_logger_error:
                with patch('sys.exit') as mock_exit:
                    load_yaml_file("non_existent_file.yaml")
                    mock_exit.assert_called_with(1)
                    mock_logger_error.assert_called_with("File not found: non_existent_file.yaml")

    def test_check_unique_feature_flags_no_duplicates(self):
        yaml_content = {
            "apps": {
                "feature_flags": {
                    "vpc": [
                        {"name": "feature1", "on": True},
                        {"name": "feature2", "on": False}
                    ]
                }
            }
        }
        with patch('sys.exit') as mock_exit:
            check_unique_feature_flags(yaml_content)
            mock_exit.assert_not_called()

    def test_check_unique_feature_flags_with_duplicates(self):
        yaml_content = {
            "apps": {
                "feature_flags": {
                    "vpc": [
                        {"name": "feature1", "on": True},
                        {"name": "feature1", "on": False}
                    ]
                }
            }
        }
        with patch.object(logger, 'error') as mock_logger_error:
            with self.assertRaises(ValueError) as context:
                check_unique_feature_flags(yaml_content)

            self.assertIn("Duplicate feature flag names found: feature1", str(context.exception))
            mock_logger_error.assert_called_with("Duplicate feature flag names found: feature1")

    def test_validate_environment_yaml_with_api_spec_version(self):
        valid_yaml_content = {
            "name": "global-test",
            "apps": {
                "feature_flags": {
                    "api_spec_version": "version2",
                    "vpc": [
                        {
                            "name": "regional-health-skip-securitygroup",
                            "on": False,
                            "default": {
                                "variation_value": True
                            },
                            "off_variation": False
                        }
                    ]
                }
            }
        }
        with patch('builtins.print') as mocked_print:
            yaml_schema_validator(valid_yaml_content, "dummy_path", schema)
            mocked_print.assert_called_with("Schema validation successful for dummy_path.")


if __name__ == "__main__":
    unittest.main()
