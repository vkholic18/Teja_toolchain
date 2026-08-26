#!/usr/bin/env python3

"""
Optional Files Validation Script
This script validates optional files from repositories based on onboarding.yaml configuration.
Optional files are only validated if they exist - their absence doesn't cause validation failure.

Usage: python3 validate_optional_files.py [--debug] <path_to_onboarding.yaml>
"""

import os
import sys
import yaml
import requests
import base64
import argparse
from typing import Dict, List, Tuple, Optional
from urllib.parse import urlparse
from github_utils import get_file_from_github, get_file_mode_from_tree

# Color codes for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color

class OptionalFilesValidator:
    """Validator for optional files in GitHub repositories"""
    
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
        self.skipped_count = 0
        
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
    
    def log_skip(self, message: str):
        """Log skip message"""
        print(f"{Colors.YELLOW}[SKIP]{Colors.NC} {message}")
    
    def parse_github_url(self, repo_url: str) -> Tuple[Optional[str], Optional[str], Optional[str]]:
        """Parse GitHub repository URL to extract host, owner, and repo name"""
        try:
            repo_url = repo_url.rstrip('/')
            if repo_url.endswith('.git'):
                repo_url = repo_url[:-4]
            
            parsed = urlparse(repo_url)
            host = parsed.netloc
            
            path_parts = parsed.path.strip('/').split('/')
            if len(path_parts) >= 2:
                owner = path_parts[0]
                repo_name = path_parts[1]
                return host, owner, repo_name
            
            return None, None, None
        except Exception as e:
            self.log_debug(f"Error parsing GitHub URL '{repo_url}': {str(e)}")
            return None, None, None
    
    def get_file_from_github(self, host: str, owner: str, repo: str, branch: str, file_path: str) -> Optional[Dict]:
        """Delegate to shared github_utils implementation."""
        return get_file_from_github(
            self.github_token, host, owner, repo, branch, file_path, self.log_debug
        )

    def get_file_mode_from_tree(self, host: str, owner: str, repo: str, branch: str, file_path: str) -> Optional[str]:
        """Delegate to shared github_utils implementation."""
        return get_file_mode_from_tree(
            self.github_token, host, owner, repo, branch, file_path, self.log_debug
        )
    
    def check_file_executable(self, file_info: Dict) -> Tuple[bool, str]:
        """Check if file has minimum executable permissions"""
        mode = file_info.get('mode', '')
        
        if not mode:
            name = file_info.get('name', '')
            if name.endswith('.sh'):
                return True, "inferred from .sh extension (mode field not available)"
            else:
                return False, "mode field not available in API response"
        
        try:
            if len(mode) >= 3:
                perms = mode[-3:]
                owner_perm = int(perms[0])
                is_exec = owner_perm in [1, 3, 5, 7]
                return is_exec, mode
        except (ValueError, IndexError) as e:
            self.log_debug(f"Error parsing mode '{mode}': {str(e)}")
            return False, f"invalid mode format: {mode}"
        
        return False, mode
    
    def check_file_empty(self, file_info: Dict) -> bool:
        """Check if file is empty"""
        size = file_info.get('size', 0)
        return size == 0
    
    def validate_file(self, repo_url: str, branch: str, file_config: Dict, category_name: str) -> bool:
        """
        Validate a single optional file
        Returns True if validation passed or file doesn't exist (optional)
        """
        file_path = file_config.get('path', '')
        can_be_empty = file_config.get('can_be_empty', True)
        executable = file_config.get('executable', False)
        
        self.total_files += 1
        
        self.log_info(f"Checking [{category_name}] {file_path}")
        
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
        
        # Get file from GitHub
        file_info = self.get_file_from_github(host, owner, repo_name, branch, file_path)
        
        if not file_info:
            # File doesn't exist - this is an ERROR
            # If teams add files to optional_files section, those files MUST exist
            self.log_error(f"  ✗ File does not exist: {file_path}")
            self.log_error(f"    Repository: {repo_url}")
            self.log_error(f"    Branch: {branch}")
            self.log_error(f"    Note: Files listed in optional_files section must exist")
            return False
        
        # File exists - validate it
        self.log_success(f"  ✓ File exists")
        
        # If mode is not in response, try to get it from tree API
        if 'mode' not in file_info or not file_info['mode']:
            self.log_debug("Mode not in contents API response, fetching from tree API...")
            mode = self.get_file_mode_from_tree(host, owner, repo_name, branch, file_path)
            if mode:
                file_info['mode'] = mode
                self.log_debug(f"File mode from tree API: {mode}")
        
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
                self.log_success(f"  ✓ File is empty (allowed by configuration)")
            else:
                self.log_error(f"  ✗ File is empty but should contain content")
                self.log_error(f"    File size: 0 bytes")
                return False
        else:
            file_size = file_info.get('size', 0)
            self.log_success(f"  ✓ File is not empty (size: {file_size} bytes)")
        
        self.success_count += 1
        return True
    
    def validate_optional_files(self, yaml_path: str) -> bool:
        """Validate all optional files from onboarding.yaml.

        Profile-aware behaviour:
          - minimal: 'mend' group skipped (no SAST scanning).
          - ci_only / ci_cd: all groups validated as normal.
        """
        self.log_info(f"Loading configuration from: {yaml_path}")

        # Load YAML file
        try:
            with open(yaml_path, 'r') as f:
                config = yaml.safe_load(f)
        except Exception as e:
            self.log_error(f"Failed to load YAML file: {str(e)}")
            return False

        # cicd_profile is a required field — no default applied
        cicd_profile = config.get('cicd_profile')
        if not cicd_profile:
            self.log_error(
                "cicd_profile is required but not set. "
                "Allowed values: minimal | ci_only | ci_cd | cd_only"
            )
            return False

        # Get optional_files section
        optional_files = config.get('optional_files', [])

        if not optional_files:
            self.log_info("No optional_files section found in configuration")
            return True

        self.log_info(f"Found {len(optional_files)} category(ies) with optional files")
        print()

        # Validate each category
        all_passed = True

        for category in optional_files:
            category_name = category.get('name', 'Unknown')

            # Skip mend SAST suppressions for profiles without SAST scanning
            if category_name == 'mend' and cicd_profile in ('minimal', 'cd_only'):
                self.log_info(
                    f"cicd_profile is '{cicd_profile}' — skipping optional_files group "
                    "'mend' (no SAST scanning)"
                )
                continue
            repo_url = category.get('repo', '')
            branch = category.get('branch', 'main')
            files = category.get('files', [])
            
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
            print(f"{Colors.BLUE}{'='*60}{Colors.NC}")
            print()
            
            # Validate each file in category
            for idx, file_config in enumerate(files, 1):
                # Add visual separator between files
                if idx > 1:
                    print(f"{Colors.CYAN}{'─' * 80}{Colors.NC}")
                    print()
                
                # Add file counter to log
                print(f"{Colors.CYAN}[File {idx}/{len(files)}]{Colors.NC}")
                
                if not self.validate_file(repo_url, branch, file_config, category_name):
                    all_passed = False
                print()
        
        return all_passed
    
    def print_summary(self):
        """Print validation summary"""
        print(f"{Colors.BLUE}{'='*60}{Colors.NC}")
        print(f"{Colors.BLUE}Validation Summary{Colors.NC}")
        print(f"{Colors.BLUE}{'='*60}{Colors.NC}")
        print(f"Total files checked: {self.total_files}")
        print(f"{Colors.YELLOW}Files skipped (not found): {self.skipped_count}{Colors.NC}")
        print(f"{Colors.GREEN}Files validated successfully: {self.success_count}{Colors.NC}")
        
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
        description='Validate optional files from GitHub repositories based on onboarding.yaml'
    )
    parser.add_argument('yaml_file', help='Path to onboarding.yaml file')
    parser.add_argument('--debug', action='store_true', help='Enable debug output')
    
    args = parser.parse_args()
    
    # Check if YAML file exists
    if not os.path.isfile(args.yaml_file):
        print(f"{Colors.RED}[ERROR]{Colors.NC} File not found: {args.yaml_file}")
        sys.exit(1)
    
    # Create validator and run validation
    validator = OptionalFilesValidator(debug=args.debug)
    
    try:
        success = validator.validate_optional_files(args.yaml_file)
        validator.print_summary()
        
        if success:
            print()
            print(f"{Colors.GREEN}✓ All optional files validated successfully!{Colors.NC}")
            sys.exit(0)
        else:
            print()
            print(f"{Colors.RED}✗ Optional files validation failed!{Colors.NC}")
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


