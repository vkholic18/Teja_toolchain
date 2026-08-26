#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
# Unit tests for scripts/check_pr_title.py.

import unittest
from io import StringIO
from unittest.mock import patch

from check_pr_title import check


class PRTitleTestCase(unittest.TestCase):
    """Test check_pr_title.py."""

    def test_correct(self):
        """Test for correct format."""
        self.assertEqual(check("feat!(auth): CIGC-123: Something"), (True, ""))

    def test_case_sensitivity(self):
        """Test for case sensitivity - verifies that lowercase letters are not allowed  """
        with patch('sys.stdout', new=StringIO()) as stdout_output:
            self.assertEqual(check("feat!(auth): ciGC-123: Something"), (False, "JIRA"))
            # A newline is at the end of the expected output because the output is done via print,
            # which adds a newline automatically
            self.assertEqual(stdout_output.getvalue(), "The JIRA Ticket contained lowercase characters in the project "
                                                       "field. JIRA ticket characters must be uppercase.\n")

    def test_incorrect_type(self):
        """Test for incorrect TYPE component."""
        self.assertEqual(check("freat: CIGC-123: Something"), (False, "TYPE"))

    def test_incorrect_scope(self):
        """Test for incorrect SCOPE component."""
        self.assertEqual(check("feat[asdf]: CIGC-123: Something"), (False, "SCOPE"))

    def test_incorrect_jira(self):
        """Test for incorrect JIRA component."""
        self.assertEqual(check("feat: 123-CIGC: Something"), (False, "JIRA"))

    def test_incorrect_subject(self):
        """Test for incorrect SUBJECT component."""
        self.assertEqual(check("feat: CIGC-123: "), (False, "SUBJECT"))


if __name__ == '__main__':
    unittest.main()
