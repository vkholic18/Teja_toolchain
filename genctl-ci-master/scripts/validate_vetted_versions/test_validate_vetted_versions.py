#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#   Unit tests for validate_vetted_versions.py
#
# Use:
#   python3 test_validate_vetted_versions.py

import sys
import yaml
import unittest
from validate_vetted_versions import validate_file, clean_file, INVALID_COMPONENT_BASE_ERROR_MESSAGE

test_data_path = f"{sys.path[0]}/test_data"


def get_vetted_versions_from_test_data(td_number):
    """
        Gets a number (As string), opens the relevant file and returns the YAML content

        Returns:

        vetted_versions: A YAML which is the content of a vetted versions file
    """

    # Set the path to the file that will be loaded
    path_to_file = f"{test_data_path}/{td_number}.yaml"

    # Load the file
    with open(path_to_file) as f:
        vetted_versions = yaml.safe_load(f)

    return vetted_versions


class ValidateVettedVersionsFile(unittest.TestCase):
    """
        Test the validate_file logic (hard mode)
    """

    def test_validate(self):
        """
        Tests the logic of the validate function (Used in hard mode)
        """

        # A dict where the key is a number identifying a test data file
        # and the value is the expected result for that test data file
        expected = {
            '1': [],
            '2': [INVALID_COMPONENT_BASE_ERROR_MESSAGE.format("genctl-release")],
            '3': [INVALID_COMPONENT_BASE_ERROR_MESSAGE.format("genctl-release")],
            '4': [],
            '5': [
                INVALID_COMPONENT_BASE_ERROR_MESSAGE.format(comp) for comp in
                [
                    "etcd-base-release", "genctl-release",
                    "hostos-kernel-patch-release",
                    "kube-addon-release", "kube-base-release", "kube-define-release",
                    "rias-etcd-release", "rias-release", "smotainer-release"
                ]
            ]
        }

        # Iterate and test
        for td in expected:

            # Get the vetted versions for this scenario
            vetted_versions = get_vetted_versions_from_test_data(td)

            # Here we convert to set in order not to be sensitive about the order
            expected_result = set(expected[td])
            actual_result = set(validate_file(vetted_versions))

            # Actual assertion of the scenario
            with self.subTest():
                self.assertEqual(expected_result, actual_result)

    def test_clean(self):
        """
        Tests the logic of the clean function (Used in soft mode)
        """

        # Load the vetted versions 1 since the expected is the versions
        vetted_versions_1 = get_vetted_versions_from_test_data("1")

        # Load the vetted versions 3 since the expected is the versions
        vetted_versions_4 = get_vetted_versions_from_test_data("4")

        expected = {
            '1': vetted_versions_1,
            '2':
                {
                    'version': {
                        'etcd-base-release': '4.1.0_20210926T175040Z_c3e5fd0'
                    }
                },
            '3':
                {
                    'version': {
                        'etcd-base-release': '4.1.0_20210926T175040Z_c3e5fd0'
                    }
                },
            '4': vetted_versions_4,
            '5':
                {
                    'version': {
                        'hostos-base-net-sw-release': '10.0.0-20210926T175801Z_b9f1dc1',
                        'hostos-base-os-sw-release': '10.0.0-20210926T181844Z_4828185',
                        'hostos-boot-release': '10.0.0-20210928T001947Z_492d044',
                        'hostos-config-release': '10.0.0-20211004T134344Z_b5d5930',
                        'hostos-nextgen-os-sw-release': '10.0.0-20211004T214906Z_2332bd3'
                    }
                }
        }

        # Iterate and test
        for td in expected:

            # Get the vetted versions for this scenario
            vetted_versions = get_vetted_versions_from_test_data(td)

            # Here we convert to set in order not to be sensitive about the order
            expected_result = expected[td]
            actual_result = clean_file(vetted_versions)

            # Actual assertion of the scenario
            with self.subTest():
                self.assertEqual(expected_result, actual_result)


if __name__ == '__main__':
    unittest.main()
