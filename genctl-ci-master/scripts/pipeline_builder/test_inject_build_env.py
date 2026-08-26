# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Unit tests for inject_build_env.py
#
# Use:
#    python3 test_inject_build_env.py
#

import config_validator
import os
import unittest
from io import StringIO
from unittest.mock import patch, Mock, mock_open

from inject_build_env import build_task_config

class TestBuildTaskConfig(unittest.TestCase):
    """
    This class contains tests for the build_task_config function
    """
    def setUp(self):
        self.task_path = "fake/path/to/file.yaml"
        self.arti_user_key = '((wcp-genctl-docker-local-artifactory-username))'
        self.arti_pass_key = '((wcp-genctl-docker-local-artifactory-token))'
        self.docker_url = "fake.artifactory.com"
        self.default_image_path = "fake/docker"
        self.default_image_tag = "1.0-abc-amd64"
        self.default_travis_image_path = "fake/travis/docker"
        self.default_travis_image_tag = "1.0-abc"
        self.config_dir_path = "fake/path/to/dir"
        self.fake_task = "platform: linux"

    def test_user_config_not_specified_with_travis(self):
        """
        Tests if default env is used if user config not specified w/ travis
        """
        user_config = None

        expected_task = {
            "platform": "linux",
            "image_resource": {
                "type": "docker-image",
                "source": {
                    "repository": "fake.artifactory.com/fake/docker",
                    "tag": self.default_image_tag,
                    "username": self.arti_user_key,
                    "password": self.arti_pass_key
                }
            },
            "params": {
                "CC_GO_IMAGE_PATH": self.default_travis_image_path,
                "CC_GO_IMAGE_TAG": self.default_travis_image_tag
            }
        }

        with patch('builtins.open', mock_open(read_data=self.fake_task)):
            with patch('yaml.safe_dump') as mock_dump:
                build_task_config(
                    user_config,
                    self.task_path,
                    self.config_dir_path,
                    self.docker_url,
                    self.default_image_path,
                    self.default_image_tag,
                    self.default_travis_image_path,
                    self.default_travis_image_tag,
                    ""
                )

                mock_dump.assert_called_once_with(
                    expected_task,
                    unittest.mock.ANY
                )

    def test_user_config_not_specified_no_travis(self):
        """
        Tests if default env is used if user config not specified w/o travis
        """
        user_config = None
        default_travis_image_path = None
        default_travis_image_tag = None

        expected_task = {
            "platform": "linux",
            "image_resource": {
                "type": "docker-image",
                "source": {
                    "repository": "fake.artifactory.com/fake/docker",
                    "tag": self.default_image_tag,
                    "username": self.arti_user_key,
                    "password": self.arti_pass_key
                }
            }
        }

        with patch('builtins.open', mock_open(read_data=self.fake_task)):
            with patch('yaml.safe_dump') as mock_dump:
                build_task_config(
                    user_config,
                    self.task_path,
                    self.config_dir_path,
                    self.docker_url,
                    self.default_image_path,
                    self.default_image_tag,
                    default_travis_image_path,
                    default_travis_image_tag,
                    ""
                )

                mock_dump.assert_called_once_with(
                    expected_task,
                    unittest.mock.ANY
                )

    def test_user_config_specified_no_travis(self):
        """
        Tests if correct config is created with user config w/o travis
        """
        user_config = {
            "image": "user/image",
            "tag": "user-tag"
        }
        default_travis_image_path = None
        default_travis_image_tag = None

        expected_task = {
            "platform": "linux",
            "image_resource": {
                "type": "docker-image",
                "source": {
                    "repository": "fake.artifactory.com/build-envs/user/image",
                    "tag": user_config['tag'] + "-amd64",
                    "username": self.arti_user_key,
                    "password": self.arti_pass_key
                }
            }
        }

        with patch('builtins.open', mock_open(read_data=self.fake_task)):
            with patch('yaml.safe_dump') as mock_dump:
                build_task_config(
                    user_config,
                    self.task_path,
                    self.config_dir_path,
                    self.docker_url,
                    self.default_image_path,
                    self.default_image_tag,
                    default_travis_image_path,
                    default_travis_image_tag,
                    ""
                )

                mock_dump.assert_called_once_with(
                    expected_task,
                    unittest.mock.ANY
                )

    def test_user_config_specified_with_travis(self):
        """
        Tests if correct config is created with user config w/ travis
        """
        user_config = {
            "image": "user/image",
            "tag": "user-tag"
        }

        expected_task = {
            "platform": "linux",
            "image_resource": {
                "type": "docker-image",
                "source": {
                    "repository": "fake.artifactory.com/build-envs/user/image",
                    "tag": user_config['tag'] + "-amd64",
                    "username": self.arti_user_key,
                    "password": self.arti_pass_key
                }
            },
            "params": {
                "CC_GO_IMAGE_PATH": "build-envs/" + user_config['image'],
                "CC_GO_IMAGE_TAG": user_config['tag']
            }
        }

        with patch('builtins.open', mock_open(read_data=self.fake_task)):
            with patch('yaml.safe_dump') as mock_dump:
                build_task_config(
                    user_config,
                    self.task_path,
                    self.config_dir_path,
                    self.docker_url,
                    self.default_image_path,
                    self.default_image_tag,
                    self.default_travis_image_path,
                    self.default_travis_image_tag,
                    ""
                )

                mock_dump.assert_called_once_with(
                    expected_task,
                    unittest.mock.ANY
                )

    def test_tag_only_user_config_specified_with_travis(self):
        """
        Tests if correct config is created with tag only user config
        """
        user_config = {
            "tag": "user-tag"
        }

        expected_task = {
            "platform": "linux",
            "image_resource": {
                "type": "docker-image",
                "source": {
                    "repository":
                        f"{self.docker_url}/{self.default_image_path}",
                    "tag": user_config['tag'] + "-amd64",
                    "username": self.arti_user_key,
                    "password": self.arti_pass_key
                }
            },
            "params": {
                "CC_GO_IMAGE_PATH": self.default_travis_image_path,
                "CC_GO_IMAGE_TAG": user_config['tag']
            }
        }

        with patch('builtins.open', mock_open(read_data=self.fake_task)):
            with patch('yaml.safe_dump') as mock_dump:
                build_task_config(
                    user_config,
                    self.task_path,
                    self.config_dir_path,
                    self.docker_url,
                    self.default_image_path,
                    self.default_image_tag,
                    self.default_travis_image_path,
                    self.default_travis_image_tag,
                    ""
                )

                mock_dump.assert_called_once_with(
                    expected_task,
                    unittest.mock.ANY
                )

if __name__ == "__main__":
    unittest.main()
