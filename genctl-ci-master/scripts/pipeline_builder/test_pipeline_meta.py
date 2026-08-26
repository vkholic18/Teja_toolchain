# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Unit tests for pipeline_meta.py
#
# Use:
#    python3 test_pipeline_meta.py
#

import unittest
from unittest.mock import patch

from pipeline_meta import PipelineMeta


class TestPipelineMeta(unittest.TestCase):
    """
    This class contains tests for the PipelineMeta class
    """
    def setUp(self):
        """
        Sets up mock workspace root
        """
        self.wsroot = "workspace"

    def test_pipeline_meta_init(self):
        """
        Tests whether __init__ properly sets wsroot class var & creates empty
        meta dict
        """
        meta = PipelineMeta(self.wsroot)

        self.assertEqual(meta.wsroot, self.wsroot)
        self.assertTrue(isinstance(meta.meta, dict))

    def test_author_email_not_cached(self):
        """
        Tests _parse_author_email called when author_email property accessed
        and email is not already cached in self.meta
        """
        meta = PipelineMeta(self.wsroot)

        with patch('pipeline_meta.PipelineMeta._parse_author_email')\
             as mock_parse:

            try:
                meta.author_email
            except KeyError:
                pass
        
        mock_parse.assert_called_once()

    def test_author_email_cached(self):
        """
        Tests _parse_author_email no when author_email property accessed
        and email is already in self.meta cache
        """
        meta = PipelineMeta(self.wsroot)

        mock_meta = { "author_email": "test@ibm.com" }
        meta.meta = mock_meta
        
        with patch('pipeline_meta.PipelineMeta._parse_author_email')\
            as mock_parse:

            email = meta.author_email

            mock_parse.assert_not_called()
        self.assertEqual(email, mock_meta['author_email'])

if __name__ == "__main__":
    unittest.main()
