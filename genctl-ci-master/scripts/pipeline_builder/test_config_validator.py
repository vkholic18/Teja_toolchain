# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Unit tests for config_validator.py
#
# Use:
#    python3 test_config_validator.py
#

import sys
import unittest
from unittest.mock import patch, mock_open, Mock

from config_validator import main, validate, validate_funct_tests_conf, _cvERRORS
from config_validator import validate_notif_conf, validate_environment_conf

class TestValidateNotifConf(unittest.TestCase):
    """
    This class contains tests for the validate_notif_conf function
    """
    def test_valid_statuses(self):
        """
        Tests whether exception raised with valid statuses
        """
        test_statuses = [
            'start',
            'success',
            'failure'
        ]

        for status in test_statuses:
            with self.subTest(status):
                config = { status: {} }
                validate_notif_conf(config)

    def test_invalid_statuses(self):
        """
        Tests whether exception raised with invalid statuses
        """
        test_statuses = [
            'begin',
            'pass',
            'fail'
        ]

        for status in test_statuses:
            with self.subTest(status):
                config = { status: {} }

                with self.assertRaises(SystemExit) as context:
                    validate_notif_conf(config)

                expected_error = "ERROR: Unexpected status type: {}".\
                    format(status)
                self.assertTrue(expected_error in str(context.exception))

    def test_invalid_recipient_types(self):
        """
        Tests whether exception raised with invalid recipient_types
        """
        test_recipient_types = [
            "email",
            "text_message",
            "phone"
        ]

        for recipient_type in test_recipient_types:
            with self.subTest(recipient_type):
                config = { "success": { recipient_type: [] } }

                with self.assertRaises(SystemExit) as context:
                    validate_notif_conf(config)

                expected_error = "ERROR: Unexpected notification " +\
                    "recipient type: {}".format(recipient_type)
                self.assertTrue(expected_error in str(context.exception))

    def test_invalid_w3id_format(self):
        """
        Tests whether exception raised when w3ids property is not a list
        """
        test_w3id_configs = [
            { "success": { "w3ids": "test@ibm.com" } },
            { "success": { "w3ids": "test@ibm.com, test2@ibm.com" } }
        ]

        for config in test_w3id_configs:
            with self.subTest(config):
                with self.assertRaises(SystemExit) as context:
                    validate_notif_conf(config)

                expected_error = "ERROR: List value expected for w3ids key"
                self.assertTrue(expected_error in str(context.exception))

    def test_valid_w3ids(self):
        """
        Tests whether exception raised when w3id is valid
        """
        test_w3ids = [
            "test@ibm.com",
            "test.user@ibm.com",
            "test@us.ibm.com"
        ]

        for w3id in test_w3ids:
            with self.subTest(w3id):
                config = { "success": { "w3ids": [w3id] } }
                validate_notif_conf(config)

    def test_invalid_w3ids(self):
        """
        Tests whether exception raised when w3id is invalid
        """
        test_w3ids = [
            "test@gmail.com",
            "test@ibm.us.com",
            "testibm.com",
            "test@ibm"
        ]

        for w3id in test_w3ids:
            with self.subTest(w3id):
                config = { "success": { "w3ids": [w3id] } }

                with self.assertRaises(SystemExit) as context:
                    validate_notif_conf(config)

                expected_error = "ERROR: Invalid w3 id {}".format(w3id)
                self.assertTrue(expected_error in str(context.exception))

    def test_valid_author_values(self):
        """
        Tests whether exception raised when author value is a boolean
        """
        test_author_values = [
            True,
            False
        ]

        for author_value in test_author_values:
            with self.subTest(author_value):
                config = { "success": { "author": author_value } }
                validate_notif_conf(config)

    def test_invalid_author_values(self):
        """
        Tests whether exception raised when author value is not a boolean
        """
        test_author_values = [
            1,
            "yes",
            "test@ibm.com"
        ]

        for author_value in test_author_values:
            with self.subTest(author_value):
                config = { "success": { "author": author_value } }

                with self.assertRaises(SystemExit) as context:
                    validate_notif_conf(config)

                expected_error = "ERROR: Boolean value expected for author key"
                self.assertTrue(expected_error in str(context.exception))

class TestValidateBuildEnvConf(unittest.TestCase):
    """
    This class contains tests for the validate_build_enc_conf function
    """
    def test_valid_config(self):
        """
        Tests whether exception raised with a valid config
        """
        test_image = "test-image"
        test_tag = "test_tag"

        test_config = {
            "image": test_image,
            "tag": test_tag
        }

        validate_environment_conf(test_config)

    def test_missing_tag_param(self):
        """
        Tests whether exception raised with missing tag param
        """
        test_image = "test-image"
        test_tag = "test_tag"

        test_configs = [
            {
                "image": test_image
            },
            {
                "image": test_image,
                "docker-tag": test_tag
            }
        ]

        for config in test_configs:
            with self.subTest(config):
                with self.assertRaises(SystemExit) as context:
                    validate_environment_conf(config)

                    expected_error = "ERROR: tag required for build env config"
                    self.assertTrue(expected_error in str(context.exception))

    def test_missing_image_param(self):
        """
        Tests whether exception raised with missing image param
        """
        test_tag = "test_tag"
        test_config = {
            "tag": test_tag
        }

        validate_environment_conf(test_config)

class TestValidate(unittest.TestCase):
    """
    This class contains tests for the validate function
    """
    def test_pipeline_types(self):
        """
        Tests whether exception raised when pipeline type is valid/invalid
        """
        test_values = {
            "valid": [
                'pr',
                'merge'
            ],
            "invalid": [
                'pull_request',
                'master',
                'deploy'
            ]
        }

        for validity, types in test_values.items():
            for pipe_type in types:
                config = str({ pipe_type: {} })

                with patch('builtins.open', mock_open(read_data=config)):
                    if validity == "valid":
                        validate(None)

                    # Commented out due to changing the behavior from throwing system exist, to a print warning statement
                    # Needs to be uncommented when we finalize the pipeline.yaml scheme
                    
                    # else:
                    #     with self.assertRaises(SystemExit) as context:
                    #         validate(None)

                    #     expected_error = "ERROR: Unexpected " +\
                    #         "config type: {}".format(pipe_type)
                    #     self.assertTrue(
                    #         expected_error in str(context.exception)
                    #     )


    def test_pipeline_copyright(self):
        """
        Tests whether the copyright will cause issues on the yaml load
        """

        for test_file in ['test_data/pipeline_copyright.yaml', 'test_data/pipeline_copyright_unicode.yaml']:
            with self.assertRaises(SystemExit) as context:
                # add full path which is relative to script
                validate(f"{sys.path[0]}/{test_file}")

                self.assertTrue(_cvERRORS['invalid_yaml'] in str(context.exception))


    def test_top_level_config_types(self):
        """
        Tests whether exception raised when pipeline type is valid/invalid
        """
        test_values = {
            "valid": [
                'functional_tests',
                'environment'
            ],
            "invalid": [
                'tests',
                'unit_tests',
                'build_script'
            ]
        }

        for validity, types in test_values.items():
            for config_type in types:
                config = str({ config_type: {} })

                with patch('builtins.open', mock_open(read_data=config)),\
                    patch('config_validator.validate_environment_conf'),\
                    patch('config_validator.validate_funct_tests_conf'):
                    if validity == "valid":
                        validate(None)

                    # Commented out due to changing the behavior from throwing system exist, to a print warning statement
                    # Needs to be uncommented when we finalize the pipeline.yaml scheme
                    
                    # else:
                    #     with self.assertRaises(SystemExit) as context:
                    #         validate(None)

                    #     expected_error = "ERROR: Unexpected " +\
                    #         "config type: {}".format(config_type)
                    #     self.assertTrue(
                    #         expected_error in str(context.exception)
                    #     )

    def test_config_types(self):
        """
        Tests whether exception raised when config type is valid/invalid
        """
        test_values = {
            "valid": [
                'notification'
            ],
            "invalid": [
                'build',
                'do',
                'cron'
            ]
        }

        for validity, config_types in test_values.items():
            for config_type in config_types:
                config = str({ 'pr': { config_type: {} } })

                with patch('builtins.open', mock_open(read_data=config)):
                    if validity == "valid":
                        validate(None)

                    else:
                        with self.assertRaises(SystemExit) as context:
                            validate(None)

                        expected_error = "ERROR: Unexpected " +\
                            "config type: {}".format(config_type)
                        self.assertTrue(
                            expected_error in str(context.exception)
                        )

class TestMain(unittest.TestCase):
    """
    This class contains tests for the main function
    """
    def test_no_argument_passed(self):
        """
        Tests whether exception raised if no argument passed at command line
        """
        testargs = ['config_validator.py']

        with patch.object(sys, 'argv', testargs):
            with self.assertRaises(SystemExit) as context:
                main()

                expected_error = "ERROR: Path to config file not specified"
                self.assertTrue(expected_error in str(context.exception))

if __name__ == "__main__":
    unittest.main()
