#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#   Unit tests for verify_protected_branches_configuration.py
#
# Use:
#   python3 test_verify_protected_branches_configuration.py

import unittest
from verify_protected_branches_configuration import compare_protected_branch_config, CONFIG_MISMATCH_BASE_ERROR_MESSAGE, CHECKS_TO_BE_REQUIRED_BASE_ERROR_MESSAGE, CHECKS_NOT_TO_BE_REQUIRED_BASE_ERROR_MESSAGE
from verify_protected_branches_configuration import format_raw_actual_protected_branch_config

BRANCH_NAME = "test_branch"


class CompareProtectedBranchConfig(unittest.TestCase):
    """
        Test the compare_protected_branch_config logic.
    """

    def test_ok_comparison(self):
        """
        Test the case that the expected configuration and the actual configuration match
        Having one
        """

        # Set empty set since for this test is not relevant
        available_status_checks = set()

        expected_config = {"required_linear_history": True, "enforce_admins": True}
        actual_config = {"required_linear_history": True, "enforce_admins": True}

        expected_test_result = []

        self.assertEqual(expected_test_result,
                         compare_protected_branch_config(BRANCH_NAME, expected_config,
                                                         actual_config,available_status_checks))

    def test_mismatch_one_field(self):
        """Test the case that the expected configuration and the actual configuration do not match in one field"""

        # Set empty set since for this test is not relevant
        available_status_checks = set()

        expected_config = {"required_linear_history": True, "enforce_admins": True}
        actual_config = {"required_linear_history": False, "enforce_admins": True}

        expected_test_result = [
            CONFIG_MISMATCH_BASE_ERROR_MESSAGE.format(BRANCH_NAME, "required_linear_history", "True", "False")
        ]

        self.assertEqual(expected_test_result,
                         compare_protected_branch_config(BRANCH_NAME, expected_config,
                                                         actual_config,available_status_checks))

    def test_mismatch_two_fields(self):
        """Test the case that the expected configuration and the actual configuration do not match in two fields"""

        # Set empty set since for this test is not relevant
        available_status_checks = set()

        expected_config = {"required_linear_history": False, "enforce_admins": True}
        actual_config = {"required_linear_history": True, "enforce_admins": False}

        expected_test_result = [
            CONFIG_MISMATCH_BASE_ERROR_MESSAGE.format(BRANCH_NAME, "required_linear_history", "False", "True"),
            CONFIG_MISMATCH_BASE_ERROR_MESSAGE.format(BRANCH_NAME, "enforce_admins", "True", "False")
        ]

        self.assertEqual(expected_test_result,
                         compare_protected_branch_config(BRANCH_NAME, expected_config, actual_config,available_status_checks))

    def test_expected_field_not_exists(self):
        """Test the case that the expected configuration includes a field that does not exist in the actual"""

        # Set empty set since for this test is not relevant
        available_status_checks = set()

        expected_config = {"required_linear_history": False, "enforce_admins": True, "not_existing_field": True}
        actual_config = {"required_linear_history": True, "enforce_admins": False}

        with self.assertRaises(SystemExit) as cm:
            compare_protected_branch_config(BRANCH_NAME, expected_config, actual_config,available_status_checks)

        self.assertEqual(cm.exception.code, 1)

    def test_actual_field_not_in_expected(self):
        """Test the case that the actual configuration includes a field that does not exist in the expected (Usual case) """

        # Set empty set since for this test is not relevant
        available_status_checks = set()

        expected_config = {"required_linear_history": False}
        actual_config = {"required_linear_history": False, "enforce_admins": False}

        expected_test_result = []

        self.assertEqual(expected_test_result,
                         compare_protected_branch_config(BRANCH_NAME, expected_config,
                                                         actual_config,available_status_checks))
    
    def test_check_that_should_be_required_ok_comparison(self):
        """Test the case of the expected includes a required check and actual has same check"""

        available_status_checks = {'SOMECHECK'}
        expected_config = {"required_status_checks_names": ['SOMECHECK']}
        actual_config = {"required_status_checks_names": ['SOMECHECK']}

        expected_test_result = []

        self.assertEqual(expected_test_result,
                         compare_protected_branch_config(BRANCH_NAME, expected_config,
                                                         actual_config,available_status_checks))
    
    def test_check_that_should_be_required_ok_comparison_subset(self):
        """Test the case of the expected includes a required check and actual has same check and another one"""

        available_status_checks = {'SOMECHECK'}
        expected_config = {"required_status_checks_names": ['SOMECHECK']}
        actual_config = {"required_status_checks_names": ['SOMECHECK','SOMEOTHERCHECK']}

        expected_test_result = []

        self.assertEqual(expected_test_result,
                         compare_protected_branch_config(BRANCH_NAME, expected_config,
                                                         actual_config,available_status_checks))
    
    def test_check_that_should_be_required_but_not_available(self):
        """Test the case of the expected includes two required check and actual has only one of them, but the missing expected is not in the available list"""

        available_status_checks = {'SOMECHECK'}
        expected_config = {"required_status_checks_names": ['SOMECHECK','CHECK_THAT_DIDNT_RUN_YET']}
        actual_config = {"required_status_checks_names": ['SOMECHECK',]}

        expected_test_result = []

        self.assertEqual(expected_test_result,
                         compare_protected_branch_config(BRANCH_NAME, expected_config,
                                                         actual_config,available_status_checks))
    
    def test_check_that_should_be_required_but_missing(self):
        """Test the case of the expected includes two checks and actual has only one of them (Missing one is available)"""

        available_status_checks = {'SOMECHECK','SOMEOTHERCHECK'}
        expected_config = {"required_status_checks_names": ['SOMECHECK','SOMEOTHERCHECK']}
        actual_config = {"required_status_checks_names": ['SOMECHECK','SOME_IRRELEVANT_CHECK']}

        expected_test_result = [
            CHECKS_TO_BE_REQUIRED_BASE_ERROR_MESSAGE.format(BRANCH_NAME, ['SOMEOTHERCHECK'])
        ]

        self.assertEqual(expected_test_result,
                         compare_protected_branch_config(BRANCH_NAME, expected_config,
                                                         actual_config,available_status_checks))
    
    def test_checks_that_should_not_be_required_ok_comparison(self):
        """Test the case of the expected includes checks that should not be required and the comparison is OK"""

        # Set empty set since for this test is not relevant
        available_status_checks = set()

        expected_config = {"checks_that_should_not_be_required": ['SOMECHECK']}
        actual_config = {"required_status_checks_names": ['SOMEOTHERCHECK'], "checks_that_should_not_be_required": []}

        expected_test_result = []

        self.assertEqual(expected_test_result,
                         compare_protected_branch_config(BRANCH_NAME, expected_config,
                                                         actual_config,available_status_checks))
    
    def test_checks_that_should_not_be_required_one_bad_check(self):
        """Test the case of the expected includes checks that should not be required and the comparison gives one bad check"""

        # Set empty set since for this test is not relevant
        available_status_checks = set()

        expected_config = {"checks_that_should_not_be_required": ['SOMECHECK']}
        actual_config = {"required_status_checks_names": ['SOMEOTHERCHECK','SOMECHECK'], "checks_that_should_not_be_required": []}

        expected_test_result = [
            CHECKS_NOT_TO_BE_REQUIRED_BASE_ERROR_MESSAGE.format(BRANCH_NAME, ['SOMECHECK'])
        ]

        self.assertEqual(expected_test_result,
                         compare_protected_branch_config(BRANCH_NAME, expected_config,
                                                         actual_config,available_status_checks))
    
    def test_checks_that_should_not_be_required_multiple_bad_checks(self):
        """Test the case of the expected includes checks that should not be required and the comparison gives multiple bad check"""

        # Set empty set since for this test is not relevant
        available_status_checks = set()
        
        expected_config = {"checks_that_should_not_be_required": ['CHECK_1','CHECK_2','CHECK_3']}
        actual_config = {"required_status_checks_names": ['CHECK_1','CHECK_3','CHECK_4'], "checks_that_should_not_be_required": []}

        expected_test_result = [
            CHECKS_NOT_TO_BE_REQUIRED_BASE_ERROR_MESSAGE.format(BRANCH_NAME, ['CHECK_1','CHECK_3'])
        ]

        self.assertEqual(expected_test_result,
                         compare_protected_branch_config(BRANCH_NAME, expected_config,
                                                         actual_config,available_status_checks))


class FormatRawActualProtectedBranchConfig(unittest.TestCase):
    """
        Test the format_raw_actual_protected_branch_config logic.
    """

    def test_format(self):
        """
        Test the case of formatting basic raw protected branch config
        """

        formatting_input = {
            'url': 'my_url',
            'enforce_admins': {
                'url': 'my_enforce_admins_url',
                'enabled': True},
            'required_linear_history': {'enabled': True}
            }

        expected_output = {
            'url': 'my_url',
            'enforce_admins': True,
            'required_linear_history': True
        }

        actual_output = format_raw_actual_protected_branch_config(formatting_input)

        self.assertEqual(expected_output,actual_output)


if __name__ == '__main__':
    unittest.main()