import unittest
from configure_featureflags import *
import validate_data
from unittest.mock import patch, MagicMock

class TestGetDirectorySize(unittest.TestCase):
    test_env_yaml = 'test_environment.yaml'
    file_sizes = [2048, 512, 1024]
    test_dir = "test_service_flags_dir"

    @classmethod
    def setUpClass(cls) -> None:
        os.mkdir(cls.test_dir)
        cls.file_sizes = [2048, 512, 1024 * 850]
        cls.file_names = ["RCS.yaml", "IMF.yaml", "ABC.yaml"]

        with open(cls.test_env_yaml, 'wb') as f:
            f.write(b'o' * 850 * 1024)

        for i, size in enumerate(cls.file_sizes):
            with open(os.path.join(cls.test_dir, f'{cls.file_names[i]}'), 'wb') as f:
                f.write(b'0' * size)

    @classmethod
    def tearDownClass(cls) -> None:
        if os.path.exists(cls.test_env_yaml):
            os.remove(cls.test_env_yaml)
        for filename in os.listdir(cls.test_dir):
            os.remove(os.path.join(cls.test_dir, filename))
        os.rmdir(cls.test_dir)

    def test_get_directory_size(self):
        expected_size = sum(self.file_sizes)
        actual_size = validate_data.get_directory_size(self.test_dir)
        self.assertEqual(expected_size, actual_size,
                         f"Expected directory size: {expected_size}, but obtained: {actual_size}")

    def test_validate_data_size(self) -> None:
        with self.assertRaises(ValueError) as context:
            validate_data.validate_data_size(self.test_env_yaml, self.test_dir)
        self.assertIn("exceeds the maximum file size limit", str(context.exception))
    
    def test_validate_service_flags_file_name(self) -> None:
        with self.assertRaises(ValueError) as context:
            validate_data.validate_service_flags_file_name(self.test_dir)
        self.assertIn("Failed to get JIRA project ABC", str(context.exception))

class TestValidateApiSpecReleaseVersion(unittest.TestCase):
    @patch("git.Repo.clone_from")
    @patch("sys.exit")
    def test_valid_api_spec_version(self, mock_exit, mock_clone_from):
        mock_repo = MagicMock()
        mock_clone_from.return_value = mock_repo

        mock_repo.git = MagicMock()
        mock_file_content = MagicMock()
        mock_file_content.read.return_value = b"apps:\n  feature_flags:\n    api_spec_version: '3.0'"

        mock_repo.tree.return_value = {"environment.yaml": MagicMock(data_stream=mock_file_content)}
        validate_data.validate_api_spec_release_version("environment.yaml", "3.0")
        mock_exit.assert_not_called()

    @patch("git.Repo.clone_from")
    @patch("sys.exit")
    def test_older_api_spec_version(self, mock_exit, mock_clone_from):
        mock_repo = MagicMock()
        mock_clone_from.return_value = mock_repo

        mock_file_content = MagicMock()
        mock_file_content.read.return_value = b"apps:\n  feature_flags:\n    api_spec_version: '3.0'"
        mock_repo.tree.return_value = {"environment.yaml": MagicMock(data_stream=mock_file_content)}

        validate_data.validate_api_spec_release_version("environment.yaml", "2.0")
        mock_exit.assert_called_once_with(1)


if __name__ == "__main__":
    unittest.main()