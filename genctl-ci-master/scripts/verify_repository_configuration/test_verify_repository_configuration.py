#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#   Unit tests for verify_repository_configuration.py
#
# Use:
#   python3 test_verify_repository_configuration.py

import unittest
from verify_repository_configuration import compare_repo_config, CONFIG_MISMATCH_BASE_ERROR_MESSAGE


class CompareRepoConfig(unittest.TestCase):
    """
        Test verify_repository_configuration.py specifically the compare_repo_config logic.

        This is due to the fact that besides the compare_repo_config, the rest of the code is regular python code
        or call to GitHub API
    """

    def test_ok_comparison(self):
        """Test the case that the expected configuration and the actual configuration match"""

        expected_config = {"allow_rebase_merge": False, "allow_squash_merge": True, "allow_merge_commit": False}
        actual_config = {"allow_rebase_merge": False, "allow_squash_merge": True, "allow_merge_commit": False, "someOtherKey": "someOtherValue"}

        expected_test_result = []

        self.assertEqual(expected_test_result,compare_repo_config(expected_config,actual_config))

    def test_mismatch_one_field(self):
        """Test the case that the expected configuration and the actual configuration do not match in one field"""

        expected_config = {"allow_rebase_merge": False, "allow_squash_merge": True, "allow_merge_commit": False}
        actual_config = {"allow_rebase_merge": False, "allow_squash_merge": False, "allow_merge_commit": False, "someOtherKey": "someOtherValue"}

        expected_test_result = [
            CONFIG_MISMATCH_BASE_ERROR_MESSAGE.format("allow_squash_merge","True","False")
        ]

        self.assertEqual(expected_test_result, compare_repo_config(expected_config, actual_config))

    def test_mismatch_two_fields(self):
        """Test the case that the expected configuration and the actual configuration do not match in two fields"""

        expected_config = {"allow_rebase_merge": False, "allow_squash_merge": True, "allow_merge_commit": False}
        actual_config = {"allow_rebase_merge": True, "allow_squash_merge": False, "allow_merge_commit": False,  "someOtherKey": "someOtherValue"}

        expected_test_result = [
            CONFIG_MISMATCH_BASE_ERROR_MESSAGE.format("allow_rebase_merge", "False", "True"),
            CONFIG_MISMATCH_BASE_ERROR_MESSAGE.format("allow_squash_merge", "True", "False")
        ]

        self.assertEqual(expected_test_result, compare_repo_config(expected_config, actual_config))

    def test_expected_field_not_exists(self):
        """Test the case that the expected configuration includes a field that does not exist in the actual"""

        expected_config = {"allow_rebase_merge": False, "allow_squash_merge": True, "allow_merge_commit": False, "not_existing_field": True}
        actual_config = {"allow_rebase_merge": True, "allow_squash_merge": False, "allow_merge_commit": False,  "someOtherKey": "someOtherValue"}

        with self.assertRaises(SystemExit) as cm:
            compare_repo_config(expected_config,actual_config)

        self.assertEqual(cm.exception.code, 1)
    


if __name__ == '__main__':
    unittest.main()
