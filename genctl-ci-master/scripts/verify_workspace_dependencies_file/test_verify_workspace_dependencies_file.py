#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#   Unit tests for verify_workspace_dependencies_file.py
#
# Use:
#   python3 test_verify_workspace_dependencies_file.py

import sys
import yaml
import unittest
from verify_workspace_dependencies_file import verify_workspace_dependencies

test_data_path = f"{sys.path[0]}/test_data"


def get_workspace_dependencies_from_test_data(td_number):
    """
        Gets a number (As string), opens the relevant file and returns the YAML content

        Returns:

        workspace_dependencies: A YAML which is the content of a vetted versions file
    """

    # Set the path to the file that will be loaded
    path_to_file = f"{test_data_path}/{td_number}.yaml"

    # Load the file
    with open(path_to_file) as f:
        workspace_dependencies = yaml.safe_load(f)

    return workspace_dependencies


class VerifyWorkspaceDependenciesFile(unittest.TestCase):
    """
        Test the verify_workspace_dependencies
    """

    def test_verify_workspace_dependencies(self):
        """
        Tests the logic of the verify function
        """

        # A dict where the key is a number identifying a test data file
        # and the value is the expected result for that test data file
        expected = {
            '1': True, # Valid
            '2': True, # Valid
            '3': True, # Valid
            '4': True, # Valid
            '5': False, # Invalid since there version doesn't have value
            '6': False, # Invalid since there is no version field
            '7': False, # Invalid since both external_services and workspaces are empty
            '8': False, # Invalid; in line 4, apis is new object instead of field
            '9': False, # Invalid; external_workspaces key is not part of the schema
            '10': False, # Invalid; in line 6, grpc is not field of external_services
            '11': False, # Invalid; in line 8, apis is not field of workspaces
            '12': False,  # Invalid; missing version in first object of workspaces
            '13': True, # Valid
            '14': True, # Valid
            '15': False, # Invalid; in line 13, grpc should be a list
            '16': False, # Invalid; in line 14, grpc should be a list of strings
            '17': True # Valid
            }

        # Iterate and test
        for td in expected:

            # Get the vetted versions for this scenario
            workspace_dependencies = get_workspace_dependencies_from_test_data(td)

            # Here we convert to set in order not to be sensitive about the order
            expected_result = expected[td]
            actual_result = verify_workspace_dependencies(workspace_dependencies)[0]

            # Actual assertion of the scenario
            with self.subTest():
                self.assertEqual(expected_result, actual_result)


if __name__ == '__main__':
    unittest.main()
