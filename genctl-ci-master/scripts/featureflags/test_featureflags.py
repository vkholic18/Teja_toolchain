# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

import unittest
from unittest.mock import MagicMock
from unittest.mock import patch
from featureflags import *


def get_mock_res():
        mock_res = {
            "items": [
                {
                    "environments": {
                        "integration": {
                            "rules": [
                                {
                                    "_id": "eec3dc25-86e6-4f3d-9d62-5aec09ce8356",
                                    "clauses": [
                                        {
                                            "_id": "f0fe42c2-a449-44ef-950e-bc1a574345a0",
                                            "attribute": "name",
                                            "negate": "false",
                                            "op": "in",
                                            "values": [
                                                "mascd-1"
                                            ]
                                        }
                                    ],
                                    "trackEvents": "false",
                                    "variation": 0
                                }
                            ]
                        }
                    },
                    "key": "reference-flag",
                    "tags": [],
                }
            ]
        }   
        return mock_res

def get_mock_feature_flag_dict():
    mock_feature_flag_dict = {
        "environments": {
            "integration": {
                "rules": [
                    {
                        "clauses": [
                            {
                                "attribute": "name",
                                "negate": "false",
                                "op": "in",
                                "values": [
                                    "mascd-1"
                                ]
                            }
                        ],
                        "variation": 0
                    }
                ]
            }
        }
    }     
    return mock_feature_flag_dict 

class TestFeatureFlags(unittest.TestCase): 
    def setUp(self):
        file = open("sample_file.txt","w")
        sample_flags = ["ff1-image-version\n","ff2-image-version"]
        file.writelines(sample_flags)
        file.close()

    def tearDown(self):
        os.remove("sample_file.txt")

    def test_bulk_import_no_rule_tag(self):
        ld = LaunchDarkly("https:lol-url", "mock-flag", "mock-auth-token")
        ld.get_all = MagicMock(return_value=get_mock_feature_flag_dict())
        ld.get_feature_flags = MagicMock(return_value=get_mock_res())
        bulk_import_rules(ld,"integration","rias","sample_file.txt","false")
    
    def test_bulk_import_excluded_rule_tag_genctl(self):
        mock_res = get_mock_res()
        mock_res["items"][0]["tags"] = ["genctl"]
        ld = LaunchDarkly("https:lol-url", "mock-flag", "mock-auth-token")
        ld.get_all = MagicMock(return_value=get_mock_feature_flag_dict())
        ld.get_feature_flags = MagicMock(return_value=mock_res)
        ld.save_rules = MagicMock(return_value="")

        bulk_import_rules(ld,"integration","rias","sample_file.txt","false")

    def test_bulk_import_dry_run_true(self):
        mock_res = get_mock_res()
        mock_res["items"][0]["tags"] = ["rias"]
        ld = LaunchDarkly("https:lol-url", "mock-flag", "mock-auth-token")
        ld.get_all = MagicMock(return_value=get_mock_feature_flag_dict())
        ld.get_feature_flags = MagicMock(return_value=mock_res)
        ld.save_rules = MagicMock(return_value="")

        bulk_import_rules(ld,"integration","rias","sample_file.txt","true")

if __name__ == "__main__":
    unittest.main()