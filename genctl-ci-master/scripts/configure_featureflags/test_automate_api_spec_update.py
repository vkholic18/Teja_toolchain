import unittest
from unittest.mock import patch, mock_open, call, MagicMock
from automate_api_spec_update import *

class TestAutomateApiSpecUpdate(unittest.TestCase):

    ### 1. UNIT TESTS FOR get_last_merged_pr_with_label ###
    @patch('automate_api_spec_update.requests.get')
    @patch('automate_api_spec_update.os.environ', {'NEXTGEN_ENVIRONMENTS_GITHUB_PAT': 'fake-token'})
    @patch('automate_api_spec_update.ghe_api_url', 'https://fake-ghe')
    @patch('automate_api_spec_update.repo_owner', 'fake-owner')
    @patch('automate_api_spec_update.label_name', 'fake-label')
    def test_get_last_merged_pr_with_label(self, mock_requests_get):
        pr_data = [{
            "title": "Fake PR",
            "number": 123,
            "html_url": "https://fake-pr-url",
            "merged_at": "2024-07-03T12:00:00Z",
            "_links": {"issue": {"href": "https://fake-ghe/repos/fake-owner/repo/issues/123"}}
        }]
        mock_prs_response = MagicMock()
        mock_prs_response.json.return_value = pr_data
        mock_prs_response.raise_for_status.return_value = None

        labels_data = [{"name": "fake-label"}]
        mock_labels_response = MagicMock()
        mock_labels_response.json.return_value = labels_data
        mock_labels_response.raise_for_status.return_value = None

        mock_requests_get.side_effect = [mock_prs_response, mock_labels_response]

        result = get_last_merged_pr_with_label("repo")
        self.assertEqual(result, {
            "title": "Fake PR",
            "number": 123,
            "url": "https://fake-pr-url"
        })

    @patch('automate_api_spec_update.requests.get')
    @patch('automate_api_spec_update.os.environ', {'NEXTGEN_ENVIRONMENTS_GITHUB_PAT': 'fake-token'})
    @patch('automate_api_spec_update.ghe_api_url', 'https://fake-ghe')
    @patch('automate_api_spec_update.repo_owner', 'fake-owner')
    @patch('automate_api_spec_update.label_name', 'fake-label')
    def test_get_last_merged_pr_with_label_none_case(self, mock_requests_get):
        pr_data = [{
            "title": "Fake PR",
            "number": 123,
            "html_url": "https://fake-pr-url",
            "merged_at": "2024-07-03T12:00:00Z",
            "_links": {"issue": {"href": "https://fake-ghe/repos/fake-owner/repo/issues/123"}}
        }]
        mock_prs_response = MagicMock()
        mock_prs_response.json.return_value = pr_data
        mock_prs_response.raise_for_status.return_value = None

        labels_data = [{"name": "label1"}]
        mock_labels_response = MagicMock()
        mock_labels_response.json.return_value = labels_data
        mock_labels_response.raise_for_status.return_value = None

        mock_requests_get.side_effect = [mock_prs_response, mock_labels_response]

        result = get_last_merged_pr_with_label("repo")
        self.assertIsNone(result)


    ### 2. UNIT TESTS FOR generate_pr_descritption ###
    @patch('automate_api_spec_update.Path')
    def test_generate_pr_description(self, mock_temp_path):
        mock_path = MagicMock()
        mock_temp_path.return_value = mock_path
        mock_temp_path.exists.return_value = True

        mock_pr_url = "https://github.com/repo-name/pull/123"

        mock_path.read_text.return_value = (
            "- [ ] All Regions\n"
            "Is the code in the regions you are enabling this in?\n- [ ] Yes\n"
            "Is there a dependency?\nSelect Yes or No\n- [ ] No\n"
            "- [x] feature change\n"
            "- [ ] configuration change\n"
            "- [ ] Previous Change Information\n"
            "- [ ] Previous Test Evidence\n"
            "[Please provide previous change info]\n"
            """[Please provide previous test evidence link as well as a
      screenshot with 100% of tests passing]"""
        )

        result = generate_pr_description(mock_pr_url, mock_path)

        self.assertIn("- [x] All Regions", result)
        self.assertIn("- [x] Yes", result)
        self.assertIn("- [x] No", result)
        self.assertIn("- [ ] feature change", result)  
        self.assertIn("- [x] configuration change", result)
        self.assertIn("- [x]  Previous Change Information", result)
        self.assertIn("- [x]  Previous Test Evidence", result)
        self.assertIn(mock_pr_url, result)
        self.assertEqual(result.count(mock_pr_url), 2)

    @patch('automate_api_spec_update.Path')
    def test_generate_pr_description_file_not_found(self, mock_temp_path):
        mock_path = MagicMock()
        mock_temp_path.return_value = mock_path
        mock_temp_path.exists.return_value = False

        mock_pr_url = "https://github.com/repo-name/pull/123"

        with self.assertRaises(FileNotFoundError):
            generate_pr_description(mock_pr_url, mock_temp_path)

    @patch('automate_api_spec_update.Path')
    def test_generate_pr_description_read_error(self, mock_temp_path):
        mock_path = MagicMock()
        mock_temp_path.return_value = mock_path
        mock_temp_path.exists.return_value = True
        mock_temp_path.read_text.side_effect = IOError("File can't be read")

        mock_pr_url = "https://github.com/repo-name/pull/123"

        with self.assertRaises(IOError):
            generate_pr_description(mock_pr_url, mock_temp_path)


    ### 3. UNIT TESTS FOR update_env_yaml ###
    @patch('automate_api_spec_update.Path')
    @patch('automate_api_spec_update.Repo')
    def test_update_env_yaml(self, mock_Repo, mock_Path):
        mock_env_path = MagicMock()
        mock_Path.return_value = mock_env_path
        mock_env_path.read_text.return_value = "api_spec_version: r10001"
        mock_env_path.write_text.return_value = None

        mock_repo_path = MagicMock()
        mock_Path.cwd.return_value.__truediv__.return_value = mock_repo_path

        mock_repo = MagicMock()
        mock_Repo.return_value = mock_repo
        mock_repo.git.add.return_value = None
        mock_commit = MagicMock()
        mock_commit.hexsha = 'commit-hash'
        mock_repo.index.commit.return_value = mock_commit

        result = update_env_yaml('fake-path.yaml', 'r10002', 'fake-file.yaml', 'fake-repo')
        self.assertEqual(result, 'commit-hash')
        mock_env_path.write_text.assert_called_once()  
        mock_repo.git.add.assert_called_with('fake-file.yaml')
        mock_repo.index.commit.assert_called()

    @patch('automate_api_spec_update.Path')
    @patch('automate_api_spec_update.Repo')
    def test_update_env_yaml_commit_msg(self, mock_Repo, mock_Path):
        mock_env_path = MagicMock()
        mock_Path.return_value = mock_env_path
        mock_env_path.read_text.return_value = "api_spec_version: r10001"
        mock_env_path.write_text.return_value = None

        mock_repo_path = MagicMock()
        mock_Path.cwd.return_value.__truediv__.return_value = mock_repo_path

        mock_repo = MagicMock()
        mock_Repo.return_value = mock_repo
        mock_repo.git.add.return_value = None

        mock_commit = MagicMock()
        mock_commit.hexsha = 'commit-hash'
        mock_repo.index.commit.return_value = mock_commit

        update_env_yaml('fake-path.yaml', 'r10002', 'fake-file.yaml', 'fake-repo')

        mock_repo.index.commit.assert_called_once()
        commit_msg = mock_repo.index.commit.call_args[0][0]

        self.assertEqual("chore: IMF-000: New Commit with Updated api spec version - r10002", commit_msg)
    
    @patch('automate_api_spec_update.Path')
    @patch('automate_api_spec_update.Repo')
    def test_update_env_yaml_file_read_error(self, mock_Repo, mock_Path):
        mock_env_path = MagicMock()
        mock_Path.return_value = mock_env_path
        mock_env_path.read_text.side_effect = IOError("File not found")

        with self.assertRaises(RuntimeError):
            update_env_yaml('fake-path.yaml', 'r10002', 'fake-file.yaml', 'fake-repo')


    ### 4. UNIT TESTS FOR get_api_spec_bump_pr ###
    @patch('automate_api_spec_update.logger')
    @patch.dict('os.environ', {'NEXTGEN_ENVIRONMENTS_GITHUB_PAT': 'fake-token', 'GHE_API_URL': 'fake-ghe-url'})
    @patch('automate_api_spec_update.Github')
    def test_get_api_spec_bump_pr(self, mock_Github, mock_logger):
        mock_gh = MagicMock()
        mock_Github.return_value = mock_gh
        mock_gh_repo = MagicMock()
        mock_gh.get_repo.return_value = mock_gh_repo

        mock_label = MagicMock()
        mock_label.name = "fake-label"
        mock_labels = MagicMock()
        mock_labels.totalCount = 1
        mock_labels.__getitem__.side_effect = lambda idx: [mock_label][idx]
        mock_labels.__iter__.return_value = iter([mock_label])
        mock_pr1 = MagicMock()
        mock_pr1.get_labels.return_value = mock_labels
        mock_pr1.number = 101
        mock_pr1.head.ref = "feature-branch"
        mock_pr2 = MagicMock()
        mock_pr2.get_labels.return_value = []
        mock_gh_repo.get_pulls.return_value = [mock_pr1, mock_pr2]

        pr_number, pr_branch = get_api_spec_bump_pr("fake-repo-owner", "fake-repo-name", "fake-label", "open")

        self.assertEqual(pr_number, 101)
        self.assertEqual(pr_branch, "feature-branch")
        mock_gh.get_repo.assert_called_with("fake-repo-owner/fake-repo-name")
        mock_gh_repo.get_pulls.assert_called_with(state="open")


    ### 5. UNIT TESTS FOR get_current_release_version ###
    @patch("builtins.open", new_callable=mock_open, read_data="api_spec_version: r10001")
    def test_get_current_release_version(self, mock_file):
        result = get_current_release_version('fake-env-file-path.yaml')
        self.assertEqual("api_spec_version: r10001", result)
        mock_file.assert_called_once_with('fake-env-file-path.yaml', 'r', encoding='utf-8')

    @patch("builtins.open", new_callable=mock_open, read_data="wrong_version: r10001")
    def test_get_current_release_version_not_found(self, mock_file):
        with self.assertRaises(RuntimeError):
            get_current_release_version('fake-env-file-path.yaml')
        mock_file.assert_called_once_with('fake-env-file-path.yaml', 'r', encoding='utf-8')


    ### 6. UNIT TESTS FOR create_or_update_api_spec_bump_pr ###
    @patch('automate_api_spec_update.logger')
    @patch('automate_api_spec_update.generate_pr_description', return_value="PR body")
    @patch('automate_api_spec_update.update_env_yaml', return_value="commit-sha")
    @patch('automate_api_spec_update.get_current_release_version', return_value="api_spec_version: r10002")
    @patch('automate_api_spec_update.GitConfigParser')
    @patch('automate_api_spec_update.Path')
    @patch('automate_api_spec_update.Repo')
    @patch('automate_api_spec_update.Github')
    @patch('automate_api_spec_update.get_api_spec_bump_pr')
    @patch('automate_api_spec_update.staging_template_hash_value', 'dummyhash')
    @patch('automate_api_spec_update.prod_template_hash_value', 'dummyhash')
    @patch('automate_api_spec_update.compute_file_hash')
    @patch('automate_api_spec_update.github_token', "fake-token")
    @patch('automate_api_spec_update.ghe_api_url', "https://fake-ghe")
    @patch('automate_api_spec_update.repo_owner', "fake-owner")
    @patch('automate_api_spec_update.label_name', "my-label")
    def test_create_or_update_api_spec_bump_pr_update_existing_pr(
        self, mock_compute_file_hash, mock_get_api_pr, mock_Github, mock_Repo, mock_Path,
        mock_GitConfigParser, mock_get_current_release_version, mock_update_env_yaml, mock_generate_pr_description, mock_logger
    ):
        mock_get_api_pr.return_value = (123, "r10001")
        mock_gh = MagicMock()
        mock_Github.return_value = mock_gh
        mock_gh_repo = MagicMock()
        mock_gh.get_repo.return_value = mock_gh_repo
        mock_pr = MagicMock()
        mock_gh_repo.get_pull.return_value = mock_pr

        mock_repo = MagicMock()
        mock_Repo.clone_from.return_value = mock_repo
        mock_Repo.return_value = mock_repo
        mock_repo.git_dir = "/fake/dir/.git"
        mock_git = MagicMock()
        mock_repo.git = mock_git
        mock_git.checkout.return_value = None
        mock_git.reset.return_value = None
        mock_git.push.return_value = None

        mock_gitconfig = MagicMock()
        mock_GitConfigParser.return_value.__enter__.return_value = mock_gitconfig

        mock_template_path = MagicMock()
        mock_template_path.exists.return_value = True
        mock_template_path.read_text.return_value = "template_content"
        mock_Path.return_value = mock_template_path

        mock_compute_file_hash.return_value = 'dummyhash'
        
        create_or_update_api_spec_bump_pr("r10003", "http://pr-url", "repo", "main")

        mock_Repo.clone_from.assert_called_with(
            'https://fake-token@github.ibm.com/fake-owner/repo.git',
            mock_Path.cwd().__truediv__(),
            branch="r10001"
        )
        mock_repo.git.checkout.assert_called()
        mock_update_env_yaml.assert_called()
        mock_repo.git.push.assert_called_with('origin', 'r10001')
        mock_gh_repo.get_pull.assert_called_with(123)
        mock_pr.edit.assert_called()
        mock_pr.create_issue_comment.assert_called_with("Automated PR - Updated api spec version to r10003")

    @patch('automate_api_spec_update.logger')
    @patch('automate_api_spec_update.generate_pr_description', return_value="PR body")
    @patch('automate_api_spec_update.update_env_yaml', return_value="commit-sha")
    @patch('automate_api_spec_update.GitConfigParser')
    @patch('automate_api_spec_update.Path')
    @patch('automate_api_spec_update.Repo')
    @patch('automate_api_spec_update.Github')
    @patch('automate_api_spec_update.get_api_spec_bump_pr')
    @patch('automate_api_spec_update.staging_template_hash_value', 'dummyhash')
    @patch('automate_api_spec_update.prod_template_hash_value', 'dummyhash')
    @patch('automate_api_spec_update.compute_file_hash')
    @patch('automate_api_spec_update.github_token', "fake-token")
    @patch('automate_api_spec_update.ghe_api_url', "https://fake-ghe")
    @patch('automate_api_spec_update.repo_owner', "fake-owner")
    @patch('automate_api_spec_update.label_name', "my-label")
    def test_create_or_update_api_spec_bump_pr_create_new_pr(
        self, mock_compute_file_hash, mock_get_api_pr, mock_Github, mock_Repo, mock_Path,
        mock_GitConfigParser, mock_update_env_yaml, mock_generate_pr_description, mock_logger
    ):
        mock_get_api_pr.return_value = (None, None)
        mock_gh = MagicMock()
        mock_Github.return_value = mock_gh
        mock_gh_repo = MagicMock()
        mock_gh.get_repo.return_value = mock_gh_repo
        mock_pr = MagicMock()
        mock_gh_repo.create_pull.return_value = mock_pr

        mock_repo = MagicMock()
        mock_Repo.clone_from.return_value = mock_repo
        mock_Repo.return_value = mock_repo
        mock_repo.git_dir = "/fake/dir/.git"
        mock_git = MagicMock()
        mock_repo.git = mock_git
        mock_git.checkout.return_value = None
        mock_git.reset.return_value = None
        mock_git.push.return_value = None

        mock_gitconfig = MagicMock()
        mock_GitConfigParser.return_value.__enter__.return_value = mock_gitconfig

        mock_template_path = MagicMock()
        mock_template_path.exists.return_value = True
        mock_template_path.read_text.return_value = "template_content"
        mock_Path.return_value = mock_template_path

        mock_compute_file_hash.return_value = 'dummyhash'

        create_or_update_api_spec_bump_pr("r10002", "http://pr-url", "repo", "main")

        mock_Repo.clone_from.assert_called_with(
            'https://fake-token@github.ibm.com/fake-owner/repo.git',
            mock_Path.cwd().__truediv__()
        )
        mock_repo.git.checkout.assert_called_with("-b", "r10002")
        mock_update_env_yaml.assert_called()
        mock_repo.git.push.assert_called_with("--set-upstream", "origin", "r10002")
        mock_gh_repo.create_pull.assert_called()
        mock_pr.add_to_labels.assert_called_with("my-label")

    @patch('automate_api_spec_update.logger')
    @patch('automate_api_spec_update.github_token', None)
    @patch('automate_api_spec_update.ghe_api_url', None)
    def test_create_or_update_api_spec_bump_pr_env_vars_missing(self, mock_logger):
        with self.assertRaises(EnvironmentError):
            create_or_update_api_spec_bump_pr("r10001", "http://pr-url", "repo", "main")


    ### 7. UNIT TEST CASES FOR 'read_global_api_spec_version' ###
    @patch('automate_api_spec_update.yaml.safe_load')
    @patch('automate_api_spec_update.Repo')
    @patch('automate_api_spec_update.shutil.rmtree')
    @patch('automate_api_spec_update.os.path.exists')
    def test_read_global_api_spec_version_returns_api_spec_version(self, mock_exists, mock_rmtree, mock_repo_cls, mock_yaml_load):
        mock_exists.return_value = True
        mock_repo = MagicMock()
        mock_repo.head.is_detached = True
        mock_repo_cls.clone_from.return_value = mock_repo
        mock_repo.remotes.origin.fetch.return_value = None
        mock_repo.git.pull.return_value = None

        mock_blob = MagicMock()
        mock_blob.data_stream.read.return_value = b"fake_yaml_content"
        mock_repo.tree.return_value = {"environment.yaml": mock_blob}

        mock_yaml_load.return_value = {
            "apps": {
                "feature_flags": {
                    "api_spec_version": "r10001"
                }
            }
        }

        result = read_global_api_spec_version("global-staging")
        self.assertEqual(result, "r10001")

    @patch('automate_api_spec_update.yaml.safe_load')
    @patch('automate_api_spec_update.Repo')
    @patch('automate_api_spec_update.shutil.rmtree')
    @patch('automate_api_spec_update.os.path.exists')
    def test_read_global_api_spec_version_no_api_spec_version(self, mock_exists, mock_rmtree, mock_repo_cls, mock_yaml_load):
        mock_exists.return_value = False
        mock_repo = MagicMock()
        mock_repo.head.is_detached = True
        mock_repo_cls.clone_from.return_value = mock_repo
        mock_repo.remotes.origin.fetch.return_value = None
        mock_repo.git.pull.return_value = None

        mock_blob = MagicMock()
        mock_blob.data_stream.read.return_value = b"fake_yaml_content"
        mock_repo.tree.return_value = {"environment.yaml": mock_blob}

        mock_yaml_load.return_value = {
            "apps": {
                "feature_flags": {}
            }
        }

        result = read_global_api_spec_version("global-staging")
        self.assertIsNone(result)


    ### 8. UNIT TEST CASES FOR trigger_prs_to_global_staging_prod ###
    @patch('automate_api_spec_update.create_or_update_api_spec_bump_pr')
    @patch('automate_api_spec_update.get_last_merged_pr_with_label')
    @patch('automate_api_spec_update.read_global_api_spec_version')
    def test_trigger_prs_to_global_staging_prod_both(self, mock_read_version, mock_get_last_pr, mock_create_or_update):
        # integ_api_spec_version > staging_version and staging_version > prod
        mock_read_version.side_effect = ['r10002', 'r10001']
        mock_get_last_pr.side_effect = [
            {"title": "Test PR", "number": 123, "url": "https://mock-pr-url-1"},
            {"title": "Test PR", "number": 124, "url": "https://mock-pr-url-2"}
        ]
        trigger_prs_to_global_staging_prod("r10003")
        self.assertEqual(mock_create_or_update.call_count, 2)
        mock_create_or_update.assert_has_calls([
            call('r10002', 'https://mock-pr-url-1', 'global-prod', 'master'),
            call('r10003', 'https://mock-pr-url-2', 'global-staging', 'main')
        ], any_order=False)

    @patch('automate_api_spec_update.create_or_update_api_spec_bump_pr')
    @patch('automate_api_spec_update.get_last_merged_pr_with_label')
    @patch('automate_api_spec_update.read_global_api_spec_version')
    def test_trigger_prs_to_global_staging_prod_prod_only(self, mock_read_version, mock_get_last_pr, mock_create_or_update):
        # integ_api_spec_version == staging_version and staging_version > prod
        mock_read_version.side_effect = ['r10002', 'r10001']
        mock_get_last_pr.return_value = {
            "title": "Test PR",
            "number": 123,
            "url": "https://mock-pr-url"
        }
        trigger_prs_to_global_staging_prod("r10002")
        mock_create_or_update.assert_called_once_with(
            'r10002', 'https://mock-pr-url', 'global-prod', 'master'
        )

    @patch('automate_api_spec_update.create_or_update_api_spec_bump_pr')
    @patch('automate_api_spec_update.get_last_merged_pr_with_label')
    @patch('automate_api_spec_update.read_global_api_spec_version')
    def test_trigger_prs_to_global_staging_prod_none(self, mock_read_version, mock_get_last_pr, mock_create_or_update):
        # integ_api_spec_version < staging_version
        mock_read_version.side_effect = ['r10002', 'r10003']
        trigger_prs_to_global_staging_prod("r10001")
        mock_create_or_update.assert_not_called()
        mock_get_last_pr.assert_not_called()

    @patch('automate_api_spec_update.create_or_update_api_spec_bump_pr')
    @patch('automate_api_spec_update.get_last_merged_pr_with_label')
    @patch('automate_api_spec_update.read_global_api_spec_version')
    def test_trigger_prs_to_global_staging_prod_value_error(self, mock_read_version, mock_get_last_pr, mock_create_or_update):
        # None in any
        mock_read_version.side_effect = [None, 'r10003']
        with self.assertRaises(ValueError):
            trigger_prs_to_global_staging_prod("r10001")
        mock_create_or_update.assert_not_called()
        mock_get_last_pr.assert_not_called()
    
if __name__ == '__main__':
    unittest.main()
