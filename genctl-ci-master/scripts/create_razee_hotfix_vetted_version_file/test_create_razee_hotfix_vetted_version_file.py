#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#   Unit tests for create_razee_hotfix_vetted_version_file.py
#
# Use:
#   python3 test_create_razee_hotfix_vetted_version_file.py

import sys
import yaml
import unittest
from create_razee_hotfix_vetted_version_file import get_result_file_contents

test_data_path = f"{sys.path[0]}/test_data"


def get_test_data(td_number):
    """
        Gets a number (As string), opens the relevant files and returns the YAML contents

        Returns:

        contents: Dictionary with the content of each file
    """
    # Declare empty result
    contents = {}
    
    # Declare the list of the files
    type_of_test_data_files = ['base', 'pre_integration', 'expected_result']

    # Iterate
    for type_of_test_data_file in type_of_test_data_files:
        # Set the path to the file that will be loaded
        path_to_file = f"{test_data_path}/{td_number}/{type_of_test_data_file}.yaml"

        # Load the file
        with open(path_to_file) as f:
            content = yaml.safe_load(f)

        # Set content
        contents[type_of_test_data_file] = content

    return contents


class ValidateGetResultFileContents(unittest.TestCase):

    def test_validate_get_result_file_contents(self):
        """
        Tests the logic of the validate function (Used in hard mode)
        """

        # A dict where the key is a number identifying a test data file
        # and the value is the expected result for that test data file
        tests = ['1']

        # Iterate and test
        for t in tests:

            # Get contents
            contents = get_test_data(t)

            # Get actual result
            actual_result = get_result_file_contents(contents['base'], contents['pre_integration'])

            # Actual assertion of the scenario
            with self.subTest():
                self.assertEqual(contents['expected_result'], actual_result)

if __name__ == '__main__':
    unittest.main()
