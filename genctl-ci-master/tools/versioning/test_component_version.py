#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Unit tests for component_version.py
#
# Use:
#    python3 test_component_version.py
#

import component_version
import os
import unittest
from unittest.mock import patch

class TestComponentVersion(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.valid_version = {
            'name': 'My Component',
            'version': '1.2.3'
        }

        cls.invalid_empty_version = {
            'name': '',
            'version': ''
        }

        cls.invalid_format_version = {
            'name': '',
            'version': '1a,2'
        }

        cls.missing_name_version = {
            "version": "1.2.3"
        }

        cls.extra_field_version = {
            "name": "my component",
            "fakefield": "fake value"
        }

        cls.invalid_version_json = "'name':,  'version': '1.2.3'"

    def test_validate_file_exists(self):
        """
        Tests valid and invalid file path
        """
        with patch('os.path.exists') as m:
            m.return_value = False
            with self.assertRaises(SystemExit):
                component_version.validate_file_exists(None)

            m.return_value = True
            component_version.validate_file_exists(None)

    def test_validate_json(self):
        """
        Tests if SystemExit raised if invalid json inputted
        """
        with self.assertRaises(SystemExit):
            component_version.validate_json(self.invalid_version_json)
    
    def test_validate_required_fields(self):
        """
        Tests if SystemExit raised if required fields missing
        """
        with self.assertRaises(SystemExit):
            component_version.validate_required_fields(
                self.missing_name_version)
        
        component_version.validate_required_fields(self.valid_version)

    def test_validate_all_fields(self):
        """
        Tests if SystemExit raised if unexpected field exists
        """
        with self.assertRaises(SystemExit):
            component_version.validate_all_fields(self.extra_field_version)

        component_version.validate_all_fields(self.valid_version)

    def test_validate_fields_not_empty(self):
        """
        Tests if SystemExit raised if field is empty
        """
        with self.assertRaises(SystemExit):
            component_version.validate_fields_not_empty(
                self.invalid_empty_version)

        component_version.validate_fields_not_empty(self.valid_version)

    def test_validate_version_format(self):
        """
        Tests if SystemExit raised version in incorrect format
        """
        with self.assertRaises(SystemExit):
            component_version.validate_version_format(
                self.invalid_empty_version)
            component_version.validate_version_format(
                self.invalid_format_version)

        component_version.validate_version_format(self.valid_version)

if __name__ == '__main__':
    unittest.main()

