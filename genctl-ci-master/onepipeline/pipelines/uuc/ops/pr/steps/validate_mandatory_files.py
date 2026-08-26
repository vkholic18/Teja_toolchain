#!/usr/bin/env python3

"""
Mandatory Files Validation Script
This script validates mandatory files from repositories based on onboarding.yaml configuration.
It checks:
1. File existence in the specified repository and branch
2. Executable permissions (for shell scripts)
3. Empty file validation (based on can_be_empty flag)

Usage: python3 validate_mandatory_files.py [--debug] <path_to_onboarding.yaml>
"""

import os
import sys
import yaml
import requests
import base64
import argparse
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from urllib.parse import urlparse
from github_utils import get_file_from_github, get_file_mode_from_tree

# Locate commons_loader relative to this file.
# parents[5] = .../genctl-ci/onepipeline  → .../genctl-ci/onepipeline/utils
_UTILS_DIR = Path(__file__).resolve().parents[5] / "utils"
if str(_UTILS_DIR) not in sys.path:
    sys.path.insert(0, str(_UTILS_DIR))

try:
    from commons_loader import load_commons, CommonsNotFoundError, CommonsParseError
except ImportError:
    # Graceful degradation when running outside the full repo tree.
    class CommonsNotFoundError(FileNotFoundError):  # type: ignore[misc]
        pass
    class CommonsParseError(ValueError):  # type: ignore[misc]
        pass
    def load_commons(ref_path):  # type: ignore[misc]
        raise CommonsNotFoundError(str(Path(ref_path).parent))

# Color codes for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color

class MandatoryFilesValidator:
    """Validator for mandatory files in GitHub repositories"""
    
    def __init__(self, debug: bool = False):
        self.debug = debug
        self.github_token = (
            os.environ.get('GH_TOKEN')
            or os.environ.get('GITHUB_TOKEN')
            or os.environ.get('GHE_TOKEN')
        )
        self.errors = []
        self.warnings = []
        self.success_count = 0
        self.total_files = 0
        
        if not self.github_token:
            self.log_error("GitHub token not found in environment variables (GH_TOKEN, GITHUB_TOKEN, or GHE_TOKEN)")
            sys.exit(1)
    
    def log_debug(self, message: str):
        """Log debug message"""
        if self.debug:
            print(f"{Colors.CYAN}[DEBUG]{Colors.NC} {message}")
    
    def log_info(self, message: str):
        """Log info message"""
        print(f"{Colors.BLUE}[INFO]{Colors.NC} {message}")
    
    def log_success(self, message: str):
        """Log success message"""
        print(f"{Colors.GREEN}[SUCCESS]{Colors.NC} {message}")
    
    def log_warning(self, message: str):
        """Log warning message"""
        print(f"{Colors.YELLOW}[WARNING]{Colors.NC} {message}")
        self.warnings.append(message)
    
    def log_error(self, message: str):
        """Log error message"""
        print(f"{Colors.RED}[ERROR]{Colors.NC} {message}")
        self.errors.append(message)
    
    def parse_github_url(self, repo_url: str) -> Tuple[Optional[str], Optional[str], Optional[str]]:
        """
        Parse GitHub repository URL to extract host, owner, and repo name
        
        Args:
            repo_url: GitHub repository URL
            
        Returns:
            Tuple of (host, owner, repo_name) or (None, None, None) if parsing fails
        """
        try:
            # Remove .git suffix if present
            repo_url = repo_url.rstrip('/')
            if repo_url.endswith('.git'):
                repo_url = repo_url[:-4]
            
            parsed = urlparse(repo_url)
            host = parsed.netloc
            
            # Extract owner and repo from path
            path_parts = parsed.path.strip('/').split('/')
            if len(path_parts) >= 2:
                owner = path_parts[0]
                repo_name = path_parts[1]
                return host, owner, repo_name
            
            return None, None, None
        except Exception as e:
            self.log_debug(f"Error parsing GitHub URL '{repo_url}': {str(e)}")
            return None, None, None
    
    def get_file_mode_from_tree(self, host: str, owner: str, repo: str, branch: str, file_path: str) -> Optional[str]:
        """Delegate to shared github_utils implementation."""
        return get_file_mode_from_tree(
            self.github_token, host, owner, repo, branch, file_path, self.log_debug
        )

    def get_file_from_github(self, host: str, owner: str, repo: str, branch: str, file_path: str) -> Optional[Dict]:
        """Delegate to shared github_utils implementation."""
        return get_file_from_github(
            self.github_token, host, owner, repo, branch, file_path, self.log_debug
        )
    
    def check_file_executable(self, file_info: Dict) -> Tuple[bool, str]:
        """
        Check if file has minimum executable permissions
        
        Args:
            file_info: File information from GitHub API
            
        Returns:
            Tuple of (is_executable, mode_info) where mode_info is a string describing the mode
        """
        # GitHub API returns mode in the format "100644" or "100755"
        # We check if the file has at least owner execute permission
        # Common executable modes: 100755, 100775, 100777, 100750, etc.
        # The last 3 digits represent permissions: owner, group, other
        # We need at least owner execute (x bit set in owner position)
        mode = file_info.get('mode', '')
        
        if not mode:
            # Mode not present in API response - this can happen with some GitHub Enterprise versions
            # Try to infer from file name (shell scripts typically have .sh extension)
            name = file_info.get('name', '')
            self.log_debug(f"Mode field not present in API response for file: {name}")
            
            # For shell scripts, we'll assume they should be executable
            # This is a fallback - ideally mode should be present
            if name.endswith('.sh'):
                return True, "inferred from .sh extension (mode field not available)"
            else:
                return False, "mode field not available in API response"
        
        try:
            # Extract the permission bits (last 3 digits)
            # For mode "100755", we want "755"
            if len(mode) >= 3:
                perms = mode[-3:]
                owner_perm = int(perms[0])
                # Check if owner has execute permission (bit 0 set)
                # Owner permissions: 1=x, 2=w, 4=r, 5=r+x, 6=r+w, 7=r+w+x
                # Execute bit is set if permission is odd (1, 3, 5, 7)
                is_exec = owner_perm in [1, 3, 5, 7]
                return is_exec, mode
        except (ValueError, IndexError) as e:
            self.log_debug(f"Error parsing mode '{mode}': {str(e)}")
            return False, f"invalid mode format: {mode}"
        
        return False, mode
    
    def check_file_empty(self, file_info: Dict) -> bool:
        """
        Check if file is empty or contains only whitespace/comments
        
        Args:
            file_info: File information from GitHub API
            
        Returns:
            True if file is empty or has no meaningful content, False otherwise
        """
        size = file_info.get('size', 0)
        
        # If size is 0, definitely empty
        if size == 0:
            return True
        
        # Check actual content for meaningful data
        content = self.get_file_content(file_info)
        if not content:
            return True
        
        # Remove whitespace and check if anything remains
        content_stripped = content.strip()
        if not content_stripped:
            return True
        
        # For YAML files, check if there's actual content beyond comments
        if file_info.get('name', '').endswith(('.yaml', '.yml')):
            # Remove comment lines and check if any content remains
            lines = content_stripped.split('\n')
            meaningful_lines = [
                line.strip() for line in lines
                if line.strip() and not line.strip().startswith('#')
            ]
            if not meaningful_lines:
                return True
        
        # For shell scripts, check if there's content beyond shebang and comments
        if file_info.get('name', '').endswith('.sh'):
            lines = content_stripped.split('\n')
            meaningful_lines = [
                line.strip() for line in lines
                if line.strip() and not line.strip().startswith('#')
            ]
            if not meaningful_lines:
                return True
        
        return False
    
    def get_file_content(self, file_info: Dict) -> Optional[str]:
        """
        Get decoded file content from GitHub API response
        
        Args:
            file_info: File information from GitHub API
            
        Returns:
            Decoded file content as string or None if not available
        """
        try:
            content_encoded = file_info.get('content', '')
            if not content_encoded:
                return None
            
            # GitHub API returns base64 encoded content
            content_decoded = base64.b64decode(content_encoded).decode('utf-8')
            return content_decoded
        except Exception as e:
            self.log_debug(f"Error decoding file content: {str(e)}")
            return None
    
    def validate_build_meta_yaml_content(self, content: str) -> Tuple[bool, List[str]]:
        """
        Validate build-meta.yaml content for required sections
        
        Args:
            content: File content as string
            
        Returns:
            Tuple of (is_valid, error_messages)
        """
        errors = []
        
        try:
            # Parse YAML content
            build_meta_data = yaml.safe_load(content)
            
            if not build_meta_data or not isinstance(build_meta_data, dict):
                errors.append("Invalid YAML structure in build-meta.yaml")
                return False, errors
            
            # Check if at least one of the required sections exists
            has_images = 'images' in build_meta_data and build_meta_data['images']
            has_packages = 'packages' in build_meta_data and build_meta_data['packages']
            
            if not has_images and not has_packages:
                errors.append(
                    "build-meta.yaml must contain at least one of the following sections: 'images' or 'packages'"
                )
                return False, errors
            
            # Validate images section if present
            if has_images:
                images = build_meta_data['images']
                if not isinstance(images, dict):
                    errors.append("'images' section must be a dictionary")
                elif not any(images.values()):
                    errors.append("'images' section exists but contains no image definitions")
            
            # Validate packages section if present
            if has_packages:
                packages = build_meta_data['packages']
                if not isinstance(packages, dict):
                    errors.append("'packages' section must be a dictionary")
                elif not any(packages.values()):
                    errors.append("'packages' section exists but contains no package definitions")
            
            return len(errors) == 0, errors
            
        except yaml.YAMLError as e:
            errors.append(f"Failed to parse YAML content: {str(e)}")
            return False, errors
        except Exception as e:
            errors.append(f"Error validating build-meta.yaml content: {str(e)}")
            return False, errors
    
    def validate_pipeline_yaml_content(self, content: str, team_name: str) -> Tuple[bool, List[str]]:
        """
        Validate pipeline.yaml content for mend_sast_info section
        
        Args:
            content: File content as string
            team_name: Team name from onboarding.yaml
            
        Returns:
            Tuple of (is_valid, error_messages)
        """
        import re
        
        errors = []
        
        try:
            # Detect non-breaking spaces (\xa0) which editors like VS Code or
            # web-based tools sometimes insert instead of regular spaces.
            # YAML does not treat \xa0 as indentation — fail early with a clear message.
            if '\xa0' in content:
                self.log_error(
                    "  ✗ pipeline.yaml contains non-breaking spaces (\\xa0) instead of regular spaces for indentation. "
                    "This is caused by some editors (e.g. VS Code, web-based tools) inserting \\xa0 characters. "
                    "Please fix the source file by replacing all \\xa0 characters with regular spaces in your editor."
                )
                self.log_debug("[DEBUG] Non-breaking spaces (\\xa0) detected in pipeline.yaml content")
                errors.append(
                    "pipeline.yaml uses non-breaking spaces (\\xa0) for indentation instead of regular spaces. "
                    "Fix by replacing \\xa0 with regular spaces in your editor."
                )
                return False, errors

            # Parse YAML content
            pipeline_data = yaml.safe_load(content)

            self.log_debug(f"[DEBUG] pipeline_data type: {type(pipeline_data).__name__}, value: {pipeline_data}")

            # safe_load returns None for empty/comment-only YAML
            if not isinstance(pipeline_data, dict):
                errors.append("Missing required section: 'mend_sast_info'")
                return False, errors

            # Check if mend_sast_info section exists
            if 'mend_sast_info' not in pipeline_data:
                errors.append("Missing required section: 'mend_sast_info'")
                return False, errors

            mend_info = pipeline_data['mend_sast_info']

            self.log_debug(f"[DEBUG] mend_info type: {type(mend_info).__name__}, value: {mend_info}")

            # mend_sast_info exists but has no keys (e.g. empty section)
            if not isinstance(mend_info, dict):
                errors.append("'mend_sast_info' section exists but contains no valid key-value pairs")
                return False, errors

            # Check required keys
            required_keys = ['mend-product-name', 'mend-user-email', 'mend-secret-group']
            for key in required_keys:
                if key not in mend_info:
                    errors.append(f"Missing required key in mend_sast_info: '{key}'")

            if errors:
                return False, errors
            
            # Validate mend-product-name format: PSIRT_PRD + 7 digits
            product_name = mend_info.get('mend-product-name') or ''
            product_pattern = r'^PSIRT_PRD\d{7}$'
            if not re.match(product_pattern, product_name):
                errors.append(
                    f"Invalid mend-product-name format: '{product_name}'. "
                    f"Expected format: PSIRT_PRD followed by 7 digits (e.g., PSIRT_PRD0000000)"
                )

            # Validate mend-user-email format: psirt_prd{7 digits}service_user@ibm.com
            user_email = mend_info.get('mend-user-email') or ''
            email_pattern = r'^psirt_prd\d{7}service_user@ibm\.com$'
            if not re.match(email_pattern, user_email):
                errors.append(
                    f"Invalid mend-user-email format: '{user_email}'. "
                    f"Expected format: psirt_prd{{7 digits}}service_user@ibm.com (e.g., psirt_prd0000000service_user@ibm.com)"
                )

            # Validate mend-secret-group format: sg-uuc-{team-name-with-hyphens}
            secret_group = mend_info.get('mend-secret-group') or ''
            # Convert team name to expected format (lowercase, spaces to hyphens)
            expected_team_slug = team_name.lower().replace(' ', '-')
            expected_secret_group = f"sg-uuc-{expected_team_slug}"
            
            if not secret_group or secret_group != expected_secret_group:
                errors.append(
                    f"Invalid mend-secret-group: '{secret_group}'. "
                    f"Expected: '{expected_secret_group}' (based on team name: '{team_name}')"
                )
            
            # Check if product name and email have matching digits (only if both passed format check)
            if not errors:
                product_digits = product_name.replace('PSIRT_PRD', '')
                email_digits = user_email.replace('psirt_prd', '').replace('service_user@ibm.com', '')
                
                if product_digits != email_digits:
                    errors.append(
                        f"Mismatch between product name and email digits. "
                        f"Product: PSIRT_PRD{product_digits}, Email: psirt_prd{email_digits}service_user@ibm.com. "
                        f"The 7 digits should match."
                    )
            
            return len(errors) == 0, errors
            
        except yaml.YAMLError as e:
            errors.append(f"Failed to parse YAML content: {str(e)}")
            return False, errors
        except Exception as e:
            errors.append(f"Error validating pipeline.yaml content: {str(e)}")
            return False, errors
    
    def validate_file(self, repo_url: str, branch: str, file_config: Dict, category_name: str, team_name: str = '') -> bool:
        """
        Validate a single file
        
        Args:
            repo_url: Repository URL
            branch: Branch name
            file_config: File configuration dictionary
            category_name: Category name (CI, CD, etc.)
            team_name: Team name for content validation
            
        Returns:
            True if validation passed, False otherwise
        """
        file_path = file_config.get('path', '')
        can_be_empty = file_config.get('can_be_empty', False)
        executable = file_config.get('executable', False)
        validate_content = file_config.get('validate_content', False)
        
        self.total_files += 1
        
        self.log_info(f"Validating [{category_name}] {file_path}")
        
        # Parse repository URL
        host, owner, repo_name = self.parse_github_url(repo_url)
        if not all([host, owner, repo_name]):
            self.log_error(f"  ✗ Invalid repository URL: {repo_url}")
            return False
        
        # Type assertion: we know these are not None after the check above
        assert host is not None and owner is not None and repo_name is not None
        
        self.log_debug(f"  Repository: {owner}/{repo_name} on {host}")
        self.log_debug(f"  Branch: {branch}")
        self.log_debug(f"  File path: {file_path}")
        self.log_debug(f"  Can be empty: {can_be_empty}")
        self.log_debug(f"  Should be executable: {executable}")
        self.log_debug(f"  Validate content: {validate_content}")
        
        # Get file from GitHub
        file_info = self.get_file_from_github(host, owner, repo_name, branch, file_path)
        
        if not file_info:
            self.log_error(f"  ✗ File does not exist: {file_path}")
            self.log_error(f"    Repository: {repo_url}")
            self.log_error(f"    Branch: {branch}")
            return False
        
        # Check if file exists
        self.log_success(f"  ✓ File exists")
        
        # Check executable permissions
        if executable:
            is_executable, mode_info = self.check_file_executable(file_info)
            if is_executable:
                self.log_success(f"  ✓ File has executable permissions ({mode_info})")
            else:
                self.log_error(f"  ✗ File does not have minimum executable permissions")
                self.log_error(f"    Expected: at least owner execute permission (e.g., 100755, 100750, 100775)")
                self.log_error(f"    Actual: {mode_info}")
                return False
        
        # Check if file is empty
        is_empty = self.check_file_empty(file_info)
        if is_empty:
            if can_be_empty:
                self.log_warning(f"  ⚠ File is empty (allowed by configuration)")
            else:
                # Provide specific error message for build-meta.yaml
                if file_path.endswith('build-meta.yaml'):
                    self.log_error(f"  ✗ File is empty but should contain content")
                    self.log_error(f"    File size: 0 bytes")
                    self.log_error(f"    build-meta.yaml must contain at least one of the following sections:")
                    self.log_error(f"      - 'images' (image definitions by architecture)")
                    self.log_error(f"      - 'packages' (package definitions by type)")
                # Provide specific error message for pipeline.yaml
                elif file_path.endswith('pipeline.yaml'):
                    self.log_error(f"  ✗ File is empty but should contain content")
                    self.log_error(f"    File size: 0 bytes")
                    self.log_error(f"    pipeline.yaml must contain the 'mend_sast_info' section")
                else:
                    self.log_error(f"  ✗ File is empty but should contain content")
                    self.log_error(f"    File size: 0 bytes")
                return False
        else:
            file_size = file_info.get('size', 0)
            self.log_success(f"  ✓ File is not empty (size: {file_size} bytes)")
        
        # Validate content for pipeline.yaml (check if filename ends with pipeline.yaml)
        if validate_content and file_path.endswith('pipeline.yaml'):
            self.log_info(f"  Validating pipeline.yaml content...")
            content = self.get_file_content(file_info)
            
            if not content:
                self.log_error(f"  ✗ Failed to retrieve file content for validation")
                return False
            
            is_valid, content_errors = self.validate_pipeline_yaml_content(content, team_name)
            
            if is_valid:
                self.log_success(f"  ✓ pipeline.yaml content validation passed")
            else:
                self.log_error(f"  ✗ pipeline.yaml content validation failed:")
                for error in content_errors:
                    self.log_error(f"    - {error}")
                return False
        
        # Validate content for build-meta.yaml when can_be_empty is false
        if file_path.endswith('build-meta.yaml') and not can_be_empty:
            self.log_info(f"  Validating build-meta.yaml content...")
            content = self.get_file_content(file_info)
            
            if not content:
                self.log_error(f"  ✗ Failed to retrieve file content for validation")
                return False
            
            is_valid, content_errors = self.validate_build_meta_yaml_content(content)
            
            if is_valid:
                self.log_success(f"  ✓ build-meta.yaml content validation passed")
            else:
                self.log_error(f"  ✗ build-meta.yaml content validation failed:")
                for error in content_errors:
                    self.log_error(f"    - {error}")
                return False
        
        self.success_count += 1
        return True
    
    def validate_mandatory_files(self, yaml_path: str) -> bool:
        """
        Validate all mandatory files from onboarding.yaml.

        Profile-aware behaviour (cicd_profile):
          - minimal:  CD group skipped entirely. In the CI group only
                      hack/ci/build.sh is required; extra files are still
                      validated structurally but not enforced as mandatory.
          - ci_only:  CD group skipped entirely. All CI files enforced.
          - cd_only:  CI group skipped entirely. Only CD group enforced.
          - ci_cd:    Full validation — CI and CD groups both enforced.

        Args:
            yaml_path: Path to onboarding.yaml file

        Returns:
            True if all validations passed, False otherwise
        """
        self.log_info(f"Loading configuration from: {yaml_path}")

        # Load YAML file
        try:
            with open(yaml_path, 'r') as f:
                config = yaml.safe_load(f)
        except Exception as e:
            self.log_error(f"Failed to load YAML file: {str(e)}")
            return False

        # team_name lives in commons.yaml — load it from there.
        team_name = ''
        try:
            commons = load_commons(yaml_path)
            team_name = commons.get('team_name', '')
            if team_name:
                self.log_debug(f"Loaded team_name from commons.yaml: {team_name}")
        except CommonsNotFoundError as exc:
            self.log_error(
                f"commons.yaml not found: {exc}. "
                f"Every team branch must contain a commons.yaml at its root."
            )
            return False
        except CommonsParseError as exc:
            self.log_error(f"commons.yaml parse error: {exc}")
            return False

        if not team_name:
            self.log_warning("No team_name found in commons.yaml")

        # cicd_profile is a required field — no default applied
        cicd_profile = config.get('cicd_profile')
        if not cicd_profile:
            self.log_error(
                "cicd_profile is required but not set. "
                "Allowed values: minimal | ci_only | ci_cd | cd_only"
            )
            return False
        self.log_info(f"cicd_profile: {cicd_profile}")

        # Required CI files per profile.
        # cd_only has no CI pipeline — CI group will be skipped below.
        REQUIRED_CI_FILES_BY_PROFILE = {
            'minimal':  {'hack/ci/build.sh'},
            'ci_only':  {'hack/ci/build.sh', 'hack/ci/run-unit-tests.sh',
                         'hack/ci/build-meta.yaml', 'hack/ci/pipeline.yaml'},
            'ci_cd':    {'hack/ci/build.sh', 'hack/ci/run-unit-tests.sh',
                         'hack/ci/build-meta.yaml', 'hack/ci/pipeline.yaml'},
            'cd_only':  set(),  # no CI files required — CI group is skipped entirely
        }
        required_ci_files = REQUIRED_CI_FILES_BY_PROFILE.get(
            cicd_profile, REQUIRED_CI_FILES_BY_PROFILE['ci_cd']
        )

        # Get mandatory_files section
        mandatory_files = config.get('mandatory_files', [])

        if not mandatory_files:
            self.log_warning("No mandatory_files section found in configuration")
            return True

        self.log_info(f"Found {len(mandatory_files)} category(ies) with mandatory files")
        if team_name:
            self.log_info(f"Team name: {team_name}")
        print()

        # Validate each category
        all_passed = True

        for category in mandatory_files:
            category_name = category.get('name', 'Unknown')
            repo_url = category.get('repo', '')
            branch = category.get('branch', 'main')
            files = category.get('files', [])

            # Skip CD group for profiles without a CD pipeline
            if category_name == 'CD' and cicd_profile in ('minimal', 'ci_only'):
                self.log_info(
                    f"cicd_profile is '{cicd_profile}' — skipping mandatory_files "
                    f"group 'CD' (no CD pipeline)"
                )
                continue

            # Skip CI group for cd_only (no CI pipeline)
            if category_name == 'CI' and cicd_profile == 'cd_only':
                self.log_info(
                    "cicd_profile is 'cd_only' — skipping mandatory_files "
                    "group 'CI' (no CI pipeline)"
                )
                continue

            if not repo_url:
                self.log_error(f"Category '{category_name}': Missing repository URL")
                all_passed = False
                continue

            if not files:
                self.log_warning(f"Category '{category_name}': No files to validate")
                continue

            print(f"{Colors.BLUE}{'='*60}{Colors.NC}")
            print(f"{Colors.BLUE}Category: {category_name}{Colors.NC}")
            print(f"{Colors.BLUE}Repository: {repo_url}{Colors.NC}")
            print(f"{Colors.BLUE}Branch: {branch}{Colors.NC}")
            if category_name == 'CI' and cicd_profile == 'minimal':
                print(f"{Colors.YELLOW}[Profile: minimal] Only 'hack/ci/build.sh' is enforced; "
                      f"extra CI files are validated but not required.{Colors.NC}")
            print(f"{Colors.BLUE}{'='*60}{Colors.NC}")
            print()

            # Validate each file in category
            for idx, file_config in enumerate(files, 1):
                # Add visual separator between files
                if idx > 1:
                    print(f"{Colors.CYAN}{'─' * 80}{Colors.NC}")
                    print()

                file_path = file_config.get('path', '')

                # Honour per-file applies_to filter when present.
                # e.g. applies_to: [ci_cd] means skip this file for minimal/ci_only.
                applies_to = file_config.get('applies_to')
                if applies_to and cicd_profile not in applies_to:
                    self.log_info(
                        f"Skipping '{file_path}' — applies_to {applies_to} does not include "
                        f"cicd_profile '{cicd_profile}'"
                    )
                    continue

                # For minimal CI group: skip enforcement of non-required files
                # (still validate them structurally if present)
                if category_name == 'CI' and cicd_profile == 'minimal' \
                        and file_path not in required_ci_files:
                    self.log_info(
                        f"cicd_profile is 'minimal' — '{file_path}' is not required, "
                        f"validating structurally only"
                    )

                # Auto-enable content validation for pipeline.yaml
                if file_path.endswith('pipeline.yaml') and 'validate_content' not in file_config:
                    file_config['validate_content'] = True

                # Add file counter to log
                print(f"{Colors.CYAN}[File {idx}/{len(files)}]{Colors.NC}")

                result = self.validate_file(repo_url, branch, file_config, category_name, team_name)

                # For minimal profile CI group, non-required file failures are warnings only
                if not result:
                    if category_name == 'CI' and cicd_profile == 'minimal' \
                            and file_path not in required_ci_files:
                        self.log_info(
                            f"'{file_path}' failed validation but is not required for "
                            f"cicd_profile 'minimal' — not counted as a blocking error"
                        )
                    else:
                        all_passed = False
                print()

        return all_passed
    
    def print_summary(self):
        """Print validation summary"""
        print(f"{Colors.BLUE}{'='*60}{Colors.NC}")
        print(f"{Colors.BLUE}Validation Summary{Colors.NC}")
        print(f"{Colors.BLUE}{'='*60}{Colors.NC}")
        print(f"Total files validated: {self.total_files}")
        print(f"{Colors.GREEN}Successful validations: {self.success_count}{Colors.NC}")
        
        if self.warnings:
            print(f"{Colors.YELLOW}Warnings: {len(self.warnings)}{Colors.NC}")
        
        if self.errors:
            print(f"{Colors.RED}Errors: {len(self.errors)}{Colors.NC}")
            print()
            print(f"{Colors.RED}Failed Validations:{Colors.NC}")
            for i, error in enumerate(self.errors, 1):
                print(f"  {i}. {error}")
        
        print(f"{Colors.BLUE}{'='*60}{Colors.NC}")

def main():
    """Main function"""
    parser = argparse.ArgumentParser(
        description='Validate mandatory files from GitHub repositories based on onboarding.yaml'
    )
    parser.add_argument('yaml_file', help='Path to onboarding.yaml file')
    parser.add_argument('--debug', action='store_true', help='Enable debug output')
    
    args = parser.parse_args()
    
    # Check if YAML file exists
    if not os.path.isfile(args.yaml_file):
        print(f"{Colors.RED}[ERROR]{Colors.NC} File not found: {args.yaml_file}")
        sys.exit(1)
    
    # Create validator and run validation
    validator = MandatoryFilesValidator(debug=args.debug)
    
    try:
        success = validator.validate_mandatory_files(args.yaml_file)
        validator.print_summary()
        
        if success:
            print()
            print(f"{Colors.GREEN}✓ All mandatory files validated successfully!{Colors.NC}")
            sys.exit(0)
        else:
            print()
            print(f"{Colors.RED}✗ Mandatory files validation failed!{Colors.NC}")
            sys.exit(1)
            
    except KeyboardInterrupt:
        print()
        print(f"{Colors.YELLOW}[INFO]{Colors.NC} Validation interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"{Colors.RED}[ERROR]{Colors.NC} Unexpected error: {str(e)}")
        if args.debug:
            import traceback
            traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()


