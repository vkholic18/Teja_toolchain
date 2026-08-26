#
# =============================================================================================
# IBM Confidential
# Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
# Unit tests for post_status.py
#

import unittest
import os
import github
import argparse
import importlib.util
from unittest.mock import patch, Mock
from io import StringIO 
from post_status import parse_args, create_gh_object, get_pr_head_commit, post

class ParserTest(unittest.TestCase):
    def setUp(self):
        self.req_args = [
            'org', 'repo', 'pr', 'state', 'target_url', 'context'
        ]

    def test_returns_namespace_object(self):
        args = parse_args(self.req_args)

        self.assertTrue(isinstance(args, argparse.Namespace))

    def test_required_arguments(self):
        args = parse_args(self.req_args)

        for arg in self.req_args:
            with self.subTest(arg=arg):
                self.assertEqual(getattr(args, arg), arg)

    def test_missing_required_arguments(self):
        with self.assertRaises(SystemExit) as cm:
            parse_args(self.req_args[:-1])

        self.assertEqual(cm.exception.code, 2)

    def test_default_optional_argument(self):
        default_retries = 3
        args = parse_args(self.req_args)

        self.assertEqual(args.retries, default_retries)

    def test_specified_optional_argument(self):
        retries_list = [2, 5, 7]

        for retries in retries_list:
             with self.subTest(retries=retries):
                cl_args = self.req_args + ['--retries', str(retries)]
                args = parse_args(cl_args)

                self.assertEqual(args.retries, retries)
                self.assertTrue(isinstance(args.retries, int))

class GithubObjectTest(unittest.TestCase):
    def setUp(self):
        self.env = {
            'GITHUB_API_URL': 'https://github.com',
            'GITHUB_API_KEY': 'abc123'
        }

        self.num_retries = 2

    def test_returns_github_object(self):
        with patch.dict('os.environ', self.env):
            gh = create_gh_object(self.num_retries)

        self.assertTrue(isinstance(gh, github.MainClass.Github))

    def test_instantiated_object(self):
        with patch.dict('os.environ', self.env), \
            patch.object(github, 'Github', return_value=None) as gh_mock:

            gh = create_gh_object(self.num_retries)
            
        gh_mock.assert_called_once_with(
            base_url=self.env['GITHUB_API_URL'],
            login_or_token=self.env['GITHUB_API_KEY'],
            retry=self.num_retries
        )

class GetPrHeadCommitTest(unittest.TestCase):
    def setUp(self):
        self.repo_mock = Mock()
        self.pr_num = 5

    def test_get_pull_call(self):
        get_pr_head_commit(self.pr_num, self.repo_mock)

        self.repo_mock.get_pull.assert_called_once_with(self.pr_num)

    def test_get_commit_call(self):
        get_pr_head_commit(self.pr_num, self.repo_mock)

        self.repo_mock.get_commit.assert_called_once()

class PostTest(unittest.TestCase):
    def setUp(self):
        self.commit_mock = Mock()

        self.args = argparse.Namespace(
            state='pending',
            target_url='https://ibm.com',
            context='fake context'
        )

    def test_create_status_call(self):
        post(self.args, self.commit_mock)

        self.commit_mock.create_status.assert_called_once_with(
            state=self.args.state,
            target_url=self.args.target_url,
            context=self.args.context,
            description="build {0}".format(self.args.state)
        )

    def test_print_statement(self):
        with patch('sys.stdout', new = StringIO()) as fake_out:
            post(self.args, self.commit_mock)

        expected_output = "Posted {0} state\n".format(self.args.state)
        self.assertEqual(fake_out.getvalue(), expected_output)

if __name__ == "__main__":
    unittest.main()
