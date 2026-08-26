#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#   Unit tests for update_release_version.py
#
# Use:
#   python3 test_update_release_version.py

import unittest
from update_release_version import get_latest_version,get_workspaces_with_versions,last_version_only,clean_dict_workspaces_versions

class TestGetLatestVersion(unittest.TestCase):
    """
        Test the get_latest_version
    """

    def test_one_version(self):
        """ Test the case we have only one version """

        versions = ['1.0.0']

        expected_result = '1.0.0'
        actual_result = get_latest_version(versions)

        self.assertEqual(expected_result,actual_result)
    
    def test_multiple_same_versions(self):
        """ Test the case we have two versions and are the same """

        versions = ['1.0.0','1.0.0']

        expected_result = '1.0.0'
        actual_result = get_latest_version(versions)

        self.assertEqual(expected_result,actual_result)
    
    def test_multiple_versions(self):
        """ Test the case we have two different versions """

        versions = ['1.0.0','2.0.0']

        expected_result = '2.0.0'
        actual_result = get_latest_version(versions)

        self.assertEqual(expected_result,actual_result)
    
    def test_data(self):
        """ Test the case we have more 'real' data  """

        versions = ['1.0.0','2.0.0','1.2.3','2.0.4']

        expected_result = '2.0.4'
        actual_result = get_latest_version(versions)

        self.assertEqual(expected_result,actual_result)

class TestCleanDictWorkspacesVersions(unittest.TestCase):
    """
        Test the clean_dict_workspaces_versions
    """

    def test_one_workspace_one_version(self):
        """ Test the case we have only one workspace with one version """

        input = {'my-workspace': ['1.0.0']}

        expected_result = {'my-workspace': '1.0.0'}
        actual_result =  clean_dict_workspaces_versions(input)

        self.assertEqual(expected_result,actual_result)
    
    def test_one_workspace_multiple_same_versions(self):
        """ Test the case we have one workspace with two versions and are the same """

        input = {'my-workspace': ['1.0.0','1.0.0']}

        expected_result = {'my-workspace': '1.0.0'}
        actual_result = clean_dict_workspaces_versions(input)

        self.assertEqual(expected_result,actual_result)
    
    def test_one_workspace_multiple_versions(self):
        """ Test the case we have one workspace with two different versions """

        input = {'my-workspace': ['1.0.0','2.3.0']}

        expected_result = {'my-workspace': '2.3.0'}
        actual_result = clean_dict_workspaces_versions(input)

        self.assertEqual(expected_result,actual_result)
    
    def test_data(self):
        """ Test the case we have more 'real' data  """

        input = {
            'regional-redis': ['1.10.0','1.24.0'],
            'regional-group': ['1.18.0'],
            'regional-group-workspace': ['1.29.0'],
            'autoscale-processor': ['1.7.0']
        }

        expected_result = {
            'regional-redis': '1.24.0',
            'regional-group': '1.29.0',
            'autoscale-processor': '1.7.0'
        }
        actual_result = clean_dict_workspaces_versions(input)

        self.assertEqual(expected_result,actual_result)

class TestWorkspacesWithVersions(unittest.TestCase):
    """
        Test the workspaces_with_versions
    """

    def test_one_workspace_one_version(self):
        """ Test the case we have only one workspace with one version """

        input = "my-workspace: 1.0.0"

        expected_result = {'my-workspace': ['1.0.0']}
        actual_result = get_workspaces_with_versions(input)

        self.assertEqual(expected_result,actual_result)
    
    def test_one_workspace_multiple_same_versions(self):
        """ Test the case we have one workspace with two versions and are the same """

        input = "my-workspace: 1.0.0, my-workspace: 1.0.0"

        expected_result = {'my-workspace': ['1.0.0']}
        actual_result = get_workspaces_with_versions(input)

        self.assertEqual(expected_result,actual_result)
    
    def test_one_workspace_multiple_versions(self):
        """ Test the case we have one workspace with two different versions """

        input = "my-workspace: 1.0.0, my-workspace: 2.3.0"

        expected_result = {'my-workspace': ['1.0.0','2.3.0']}
        actual_result = get_workspaces_with_versions(input)

        self.assertEqual(expected_result,actual_result)
    
    def test_data(self):
        """ Test the case we have more 'real' data  """

        input = "regional-redis: 1.10.0, regional-group: 1.18.0, autoscale-processor: 1.7.0, regional-redis: 1.24.0"

        expected_result = {
            'regional-redis': ['1.10.0','1.24.0'],
            'regional-group': ['1.18.0'],
            'autoscale-processor': ['1.7.0']
        }
        actual_result = get_workspaces_with_versions(input)

        self.assertEqual(expected_result,actual_result)

class TestLastVersionOnly(unittest.TestCase):
    """
        Test the last_version_only
    """

    def test_one_workspace_one_version(self):
        """ Test the case we have only one workspace with one version """

        input = "my-workspace: 1.0.0"

        expected_result = "my-workspace: 1.0.0"
        actual_result = last_version_only(input)

        self.assertEqual(expected_result,actual_result)
    
    def test_one_workspace_multiple_same_versions(self):
        """ Test the case we have one workspace with two versions and are the same """

        input = "my-workspace: 1.0.0, my-workspace: 1.0.0"

        expected_result = "my-workspace: 1.0.0"
        actual_result = last_version_only(input)

        self.assertEqual(expected_result,actual_result)
    
    def test_one_workspace_multiple_versions(self):
        """ Test the case we have one workspace with two different versions """

        input = "my-workspace: 1.0.0, my-workspace: 2.3.0"

        expected_result = "my-workspace: 2.3.0"
        actual_result = last_version_only(input)

        self.assertEqual(expected_result,actual_result)
    
    def test_data(self):
        """ Test the case we have more 'real' data  """

        input = """
            regional-redis: 1.10.0, regional-group: 1.18.0, autoscale-processor: 1.7.0, regional-redis: 1.11.0, 
            autoscale-processor: 1.8.0, regional-redis: 1.12.0, regional-group: 1.19.0, regional-redis: 1.13.0, 
            regional-group: 1.20.0, regional-group: 1.21.0, regional-group: 1.35.0
            """

        expected_result = "regional-redis: 1.13.0, regional-group: 1.35.0, autoscale-processor: 1.8.0"
        actual_result = last_version_only(input)

        self.assertEqual(expected_result,actual_result)

if __name__ == '__main__':
    unittest.main()