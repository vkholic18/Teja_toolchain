# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Unit tests for build_functional_tests.py
#
# Use:
#    python3 test_build_functional_tests.py
#

import builtins
import logging
import os
import sys
import unittest
from unittest.mock import patch, Mock, mock_open

from build_functional_tests import build_cpap_suite

class TestBuildCpapSuite(unittest.TestCase):
    """
    This class contains tests for the build cpap suite function
    """
    def setUp(self):
        self.def_cpap_test_file = 'ci_generated_tests.ini'
        self.def_cpap_test_dir = "path/to/dir"
        self.def_ws_path = "workspace-repo"
        self.path = os.path.join(self.def_ws_path, self.def_cpap_test_dir)

        self.start_message = "INFO: Building cpap test ini file\n"

    def test_no_cpap_test_dir_definied(self):
        """
        Tests that no config file generated if test dir not defined
        """
        cpap_test_dir = None

        with patch('builtins.open') as mock_open:
            build_cpap_suite(
                cpap_test_dir,
                self.def_ws_path
            )

            self.assertTrue(not mock_open.called)

    def test_defined_dir_doesnt_exist(self):
        """
        Tests that correct warning message displayed if test dir dne
        """
        with patch('os.path.exists') as mock_exists,\
        patch('logging.Logger.warning') as mock_warning:
            mock_exists.return_value = False

            build_cpap_suite(
                self.def_cpap_test_dir,
                self.def_ws_path
            )

            mock_warning.assert_called_once_with(
                f"The configured cpap_test_dir, {self.path} does not exist"
            )

    def test_defined_dir_empty(self):
        """
        Tests that correct warning message displayed if test dir is empty
        """
        with patch('os.path.exists') as mock_exists,\
            patch('os.listdir') as mock_listdir,\
            patch('logging.Logger.warning') as mock_warning:
            mock_exists.return_value = True
            mock_listdir.return_value = []

            build_cpap_suite(
                self.def_cpap_test_dir,
                self.def_ws_path
            )

            mock_warning.assert_called_once_with(
                f"No tests found in the configured cpap_test_dir, {self.path}"
            )

    def test_config_written(self):
        """
        Tests that test suite config is written if tests exist in specified dir
        """
        with patch('os.path.exists') as mock_exists,\
            patch('os.listdir') as mock_listdir,\
            patch('builtins.open') as mock_open:

            mock_exists.return_value = True
            mock_listdir.return_value = ['fake_test_1.py', 'fake_test_2.py']

            build_cpap_suite(
                self.def_cpap_test_dir,
                self.def_ws_path
            )

            file_path = os.path.join(self.def_ws_path, self.def_cpap_test_file)
            mock_open.assert_called_once_with(file_path, 'w+')

if __name__ == "__main__":
    unittest.main()
