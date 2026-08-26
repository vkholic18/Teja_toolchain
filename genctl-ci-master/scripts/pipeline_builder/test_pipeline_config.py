# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Unit tests for pipeline_config.py
#
# Use:
#    python3 test_pipeline_config.py
#

import config_validator
import os
import unittest
from unittest.mock import patch, Mock, mock_open

from pipeline_config import PipelineConfig


class TestPipelineConfig(unittest.TestCase):
    """
    This class contains tests for the PipelineConfig class
    """
    def setUp(self):
        """
        Sets up a mock raw pipeline configuration
        """
        self.config_path = 'workspace-repo'
        self.pipe_types = ['pr', 'merge']
        self.statuses = ['start', 'failure', 'success']
        self.raw_config = {
            "pr": {
                "notification": {
                    "success": {
                        "author": True
                    },
                    "failure": {
                        "w3ids": [
                            "test@ibm.com",
                            "test2@ibm.com",
                            "test3@us.ibm.com"
                        ]
                    }
                }
            },
            "merge": {
                "notification": {
                    "failure": {
                        "w3ids": [
                            "test3@ibm.com"
                        ]
                    }
                }
            }
        }
        self.str_config = str(self.raw_config)
        self.simple_config = self.raw_config['pr']

    def test_pipeline_config_init(self):
        """
        Tests each configuration combination in a subtest
        Tests whether self._parse_config is called properly during __init__
        """
        for status in self.statuses:
            with self.subTest(
                "type: {0}".format(status)):

                with patch.object(
                    PipelineConfig,
                    '_parse_config') as mock_p:
                    
                    PipelineConfig(
                        self.config_path
                    )

                mock_p.assert_called_once_with(
                        self.config_path
                )

    def test_parse_config(self):
        """
        Tests each configuration combination in a subtest
        Mocks built-in open function with mock config data
        Tests whether expected confiugration is loaded to "config" class var
        """
        with patch('builtins.open', mock_open(read_data=self.str_config)):
            for status in self.statuses:
                with self.subTest("type: {0}".format(status)):

                    pipe_config = PipelineConfig(
                        self.config_path
                    )

                try:
                    expect_config = self.raw_config[status]
                except KeyError:
                    expect_config = {}

                self.assertEqual(pipe_config.config, expect_config)

    def test_parse_file_not_exist(self):
        """
        Tests whether the parser returns an empty dict if the pipeline.yaml
        file doesn't exist
        """
        with patch('os.path.exists') as os_path:
            os_path.return_value = False
                
            pipe_config = PipelineConfig(
                self.config_path
            )

            self.assertEqual(pipe_config.config, dict())

    def test_parse_vaidator_called(self):
        """
        Tests whether the config_validator function is called properly
        in _parse_config
        """
        with patch('builtins.open', mock_open(read_data=self.str_config)):
            with patch('config_validator.validate') as mock_validator:
                with patch('os.path.exists') as os_path:
                    os_path.return_value = True
                
                    PipelineConfig(
                        self.config_path
                    )
                    
                    mock_validator.assert_called_once_with(
                        f"{self.config_path}/hack/ci/pipeline.yaml"
                    )

    def test_parse_bad_config(self):
        """
        Tests whether the exception is propigated from the config_validator
        if the config is not valid
        """
        with patch('builtins.open', mock_open(read_data=self.str_config)):
            with patch('config_validator.validate', 
                **{'return_value.raiseError.side_effect': SystemExit()}):

                PipelineConfig(
                    self.config_path
                )

                self.assertRaises(SystemExit)

    def test_notification_return_type(self):
        """
        Tests whether the notification property returns type dictionary
        """
        with patch('pipeline_config.PipelineConfig._parse_config'):
            for pipe_type in self.pipe_types:
                with self.subTest("type: {}".format(pipe_type)):
                    pipe_config = PipelineConfig(None, pipe_type)

                    with patch.dict(pipe_config.config, self.raw_config):
                        notif_config = pipe_config.notification

        self.assertTrue(isinstance(notif_config, dict))

    def test_notification_no_config(self):
        """
        Tests output when notification config is not defined
        """
        with patch('pipeline_config.PipelineConfig._parse_config'):
            pipe_config = PipelineConfig(None, None)

            with patch.dict(pipe_config.config, dict()):
                notif_config = pipe_config.notification

        self.assertFalse(notif_config)

    def test_notification_config(self):
        """
        Tests that notification config is properly parsed
        """
        with patch('pipeline_config.PipelineConfig._parse_config'):
            for pipe_type in self.pipe_types:
                with self.subTest("type: {}".format(pipe_type)):
                    pipe_config = PipelineConfig(None, pipe_type)

                    with patch.dict(pipe_config.config, self.raw_config):
                        self.assertEqual(
                            pipe_config.notification,
                            self.raw_config[pipe_type]['notification']
                        )

    def test_notification_return_no_pipe_type(self):
        """
        Tests whether the notification property returns type dictionary
        """
        with patch('pipeline_config.PipelineConfig._parse_config'):
            pipe_config = PipelineConfig(None)

            with patch.dict(pipe_config.config, self.raw_config):
                notif_config = pipe_config.notification

        self.assertFalse(notif_config)

if __name__ == "__main__":
    unittest.main()
