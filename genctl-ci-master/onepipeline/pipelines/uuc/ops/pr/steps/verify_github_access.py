#!/usr/bin/env python3
"""
GitHub Repository Access Verification Script

This script verifies that functional IDs have the required permissions on repositories
specified in the onboarding.yaml file.

Requirements:
1. onepipelineci@ibm.com should have admin access on app repo and incident repo
2. clconc@us.ibm.com should have at least write access on app repo
3. onepipelineci@ibm.com should have at least write access on inventory repo
4. If inventory_repo.create is true, verify service_fid_dev has org-level permission to create repos;
   service_fid_prod must have admin access on the inventory repo after it is created
5. If incident_repo.create is true, verify service_fid_dev has org-level permission to create repos;
   service_fid_prod must have admin access on the incident repo after it is created
6. If inventory_repo/incident_repo already exist (create: false), both service_fid_dev and
   service_fid_prod must have admin access on those repositories

Usage:
    python3 verify_github_access.py <path_to_onboarding.yaml> [--token TOKEN]
    
Environment Variables:
    GITHUB_TOKEN or GHE_TOKEN: GitHub Enterprise personal access token
"""

import sys
import os
import yaml
import requests
import argparse
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from urllib.parse import urlparse

# Color codes for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color

class GitHubAccessVerifier:
    """Verifies GitHub repository access for functional IDs"""
    
    ONEPIPELINE_FID = "onepipelineci@ibm.com"
    ONEPIPELINE_FID_USERNAME = "OnePipeLineCI"  # GitHub username (not email)
    CLCONC_FID = "clconc@us.ibm.com"
    CLCONC_FID_USERNAME = "clconc"             # GitHub username (not email)
    REQUIRED_PERMISSIONS = {
        'admin': ['admin'],
        'write': ['admin', 'write'],
        'read': ['admin', 'write', 'read']
    }
    
    def __init__(self, token: str, github_api_url: str = "https://github.ibm.com/api/v3"):
        """
        Initialize the verifier with GitHub token
        
        Args:
            token: GitHub personal access token
            github_api_url: GitHub Enterprise API URL
        """
        self.token = token
        self.api_url = github_api_url.rstrip('/')
        self.headers = {
            'Authorization': f'token {token}',
            'Accept': 'application/vnd.github.v3+json'
        }
        self.errors = []
        self.warnings = []
        self.success_messages = []
        
    def parse_repo_url(self, repo_url: str) -> Tuple[str, str]:
        """
        Parse GitHub repository URL to extract org and repo name
        
        Args:
            repo_url: Full GitHub repository URL
            
        Returns:
            Tuple of (org, repo_name)
        """
        # Remove .git suffix if present
        repo_url = repo_url.rstrip('/').replace('.git', '')
        
        # Parse URL
        parsed = urlparse(repo_url)
        path_parts = parsed.path.strip('/').split('/')
        
        if len(path_parts) >= 2:
            org = path_parts[0]
            repo_name = path_parts[1]
            return org, repo_name
        else:
            raise ValueError(f"Invalid repository URL format: {repo_url}")
    
    def get_user_permission(self, org: str, repo: str, username: str, debug: bool = False) -> Optional[str]:
        """
        Get user's permission level on a repository
        
        Args:
            org: GitHub organization
            repo: Repository name
            username: Username or email to check
            debug: Enable debug logging
            
        Returns:
            Permission level ('admin', 'write', 'read', 'none') or None if error
        """
        # Convert email to GitHub username for known FIDs
        actual_username = username
        if username == self.ONEPIPELINE_FID:
            actual_username = self.ONEPIPELINE_FID_USERNAME
            if debug:
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Converting {username} to GitHub username: {actual_username}")
        elif username == self.CLCONC_FID:
            actual_username = self.CLCONC_FID_USERNAME
            if debug:
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Converting {username} to GitHub username: {actual_username}")
        
        # Try to get collaborator permission
        url = f"{self.api_url}/repos/{org}/{repo}/collaborators/{actual_username}/permission"
        
        if debug:
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Checking permission for {actual_username} on {org}/{repo}")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} API URL: {url}")
        
        try:
            response = requests.get(url, headers=self.headers, timeout=30)
            
            if debug:
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Response status: {response.status_code}")
                if response.status_code == 200:
                    print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Response body: {response.text[:500]}")
            
            if response.status_code == 200:
                data = response.json()
                permission = data.get('permission', 'none')
                if debug:
                    print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Direct collaborator permission: {permission}")
                return permission
            elif response.status_code == 404:
                if debug:
                    print(f"{Colors.BLUE}[DEBUG]{Colors.NC} User not found as direct collaborator, checking team access...")
                # User might not be a direct collaborator, check if they have access through team
                return self._check_team_permission(org, repo, actual_username, debug)
            else:
                error_msg = f"Unable to check permission for {actual_username} on {org}/{repo}: HTTP {response.status_code}"
                if debug:
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} {error_msg}")
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} Response: {response.text[:500]}")
                self.warnings.append(error_msg)
                return None
        except requests.exceptions.RequestException as e:
            error_msg = f"Error checking permission for {actual_username} on {org}/{repo}: {str(e)}"
            if debug:
                print(f"{Colors.RED}[DEBUG]{Colors.NC} {error_msg}")
            self.warnings.append(error_msg)
            return None
    
    def _check_team_permission(self, org: str, repo: str, username: str, debug: bool = False) -> Optional[str]:
        """
        Check if user has access through team membership
        
        Args:
            org: GitHub organization
            repo: Repository name
            username: Username to check
            debug: Enable debug logging
            
        Returns:
            Permission level or 'none'
        """
        # Get all teams with access to the repo
        url = f"{self.api_url}/repos/{org}/{repo}/teams"
        
        if debug:
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Checking team permissions for {username} on {org}/{repo}")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Teams API URL: {url}")
        
        try:
            response = requests.get(url, headers=self.headers, timeout=30)
            
            if debug:
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Teams response status: {response.status_code}")
            
            if response.status_code == 200:
                teams = response.json()
                
                if debug:
                    print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Found {len(teams)} team(s) with access to repo")
                    if len(teams) > 0:
                        print(f"{Colors.BLUE}[DEBUG]{Colors.NC} These are REPOSITORY-LEVEL teams, not org-level teams")
                
                # Check if user is member of any team with access
                for team in teams:
                    team_slug = team.get('slug')
                    team_name = team.get('name', team_slug)
                    team_permission = team.get('permission', 'none')
                    
                    if debug:
                        print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Checking team: {team_name} (permission: {team_permission})")
                    
                    if self._is_user_in_team(org, team_slug, username, debug):
                        if debug:
                            print(f"{Colors.GREEN}[DEBUG]{Colors.NC} User {username} is member of team {team_name} with {team_permission} permission")
                        return team_permission
                
                if debug:
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} User {username} is not a member of any REPOSITORY-LEVEL team with access")
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} ")
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} SOLUTION: Add {username} to one of these repository teams:")
                    for team in teams:
                        team_name = team.get('name', team.get('slug'))
                        team_permission = team.get('permission', 'none')
                        print(f"{Colors.YELLOW}[DEBUG]{Colors.NC}   - Team: {team_name} (grants {team_permission} access)")
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} ")
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} Or add {username} as a direct collaborator to the repository")
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} Repository Settings → Collaborators → Add {username}")
                
                return 'none'
            else:
                if debug:
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} Unable to fetch teams: HTTP {response.status_code}")
                return 'none'
        except requests.exceptions.RequestException as e:
            if debug:
                print(f"{Colors.RED}[DEBUG]{Colors.NC} Error checking team permission: {str(e)}")
            return 'none'
    
    def _is_user_in_team(self, org: str, team_slug: str, username: str, debug: bool = False) -> bool:
        """
        Check if user is member of a team
        
        Args:
            org: GitHub organization
            team_slug: Team slug
            username: Username to check
            debug: Enable debug logging
            
        Returns:
            True if user is in team, False otherwise
        """
        url = f"{self.api_url}/orgs/{org}/teams/{team_slug}/memberships/{username}"
        
        if debug:
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Checking if {username} is in team {team_slug}")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Team membership API URL: {url}")
        
        try:
            response = requests.get(url, headers=self.headers, timeout=30)
            
            if debug:
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Team membership response status: {response.status_code}")
                if response.status_code == 200:
                    print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Response: {response.text[:300]}")
                elif response.status_code == 404:
                    # Try to get all team members to see if user exists with different format
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} 404 - User not found in team. Fetching all team members to verify...")
                    members_url = f"{self.api_url}/orgs/{org}/teams/{team_slug}/members"
                    members_response = requests.get(members_url, headers=self.headers, timeout=30)
                    if members_response.status_code == 200:
                        members = members_response.json()
                        print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Team has {len(members)} member(s)")
                        # Check if username matches any member (by login or email)
                        for member in members[:10]:  # Show first 10 members
                            member_login = member.get('login', '')
                            print(f"{Colors.BLUE}[DEBUG]{Colors.NC}   - Member: {member_login}")
                            if username.lower() in member_login.lower() or member_login.lower() in username.lower():
                                print(f"{Colors.YELLOW}[DEBUG]{Colors.NC}   ⚠ Possible match found: {member_login}")
                    else:
                        print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} Unable to fetch team members: HTTP {members_response.status_code}")
            
            return response.status_code == 200
        except requests.exceptions.RequestException as e:
            if debug:
                print(f"{Colors.RED}[DEBUG]{Colors.NC} Error checking team membership: {str(e)}")
            return False
    
    def check_repo_exists(self, org: str, repo: str) -> bool:
        """
        Check if repository exists
        
        Args:
            org: GitHub organization
            repo: Repository name
            
        Returns:
            True if repo exists, False otherwise
        """
        url = f"{self.api_url}/repos/{org}/{repo}"
        
        try:
            response = requests.get(url, headers=self.headers, timeout=30)
            return response.status_code == 200
        except requests.exceptions.RequestException:
            return False
    
    def validate_github_username(self, username: str, expected_email: str, debug: bool = False) -> bool:
        """
        Validate that a GitHub username exists and optionally matches the expected email
        
        Args:
            username: GitHub username to validate
            expected_email: Expected email address for the user
            debug: Enable debug logging
            
        Returns:
            True if username is valid, False otherwise
        """
        if not username:
            if debug:
                print(f"{Colors.RED}[DEBUG]{Colors.NC} Username is empty")
            return False
        
        # Check if user exists
        url = f"{self.api_url}/users/{username}"
        
        if debug:
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Validating GitHub username: {username}")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} API URL: {url}")
        
        try:
            response = requests.get(url, headers=self.headers, timeout=10)
            
            if debug:
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Response status: {response.status_code}")
            
            if response.status_code == 200:
                user_data = response.json()
                actual_login = user_data.get('login', '')
                user_email = user_data.get('email', '')
                
                if debug:
                    print(f"{Colors.GREEN}[DEBUG]{Colors.NC} User exists: {actual_login}")
                    print(f"{Colors.BLUE}[DEBUG]{Colors.NC} User email: {user_email or 'Not public'}")
                
                # Check if username matches (case-insensitive)
                if actual_login.lower() != username.lower():
                    if debug:
                        print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} Username case mismatch: provided '{username}', actual '{actual_login}'")
                    self.warnings.append(
                        f"⚠ GitHub username case mismatch: provided '{username}', actual '{actual_login}'. "
                        f"Using actual username: {actual_login}"
                    )
                    return True  # Still valid, just different case
                
                # Optionally verify email matches (if email is public)
                if expected_email and user_email:
                    if user_email.lower() != expected_email.lower():
                        if debug:
                            print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} Email mismatch: expected '{expected_email}', got '{user_email}'")
                        self.warnings.append(
                            f"⚠ GitHub user {username} has email '{user_email}' but expected '{expected_email}'. "
                            f"Verify this is the correct FID username."
                        )
                
                return True
            elif response.status_code == 404:
                if debug:
                    print(f"{Colors.RED}[DEBUG]{Colors.NC} User not found: {username}")
                self.errors.append(
                    f"❌ GitHub username '{username}' does not exist. "
                    f"Please verify the username at https://github.ibm.com/{username}"
                )
                return False
            else:
                if debug:
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} Unable to validate username: HTTP {response.status_code}")
                self.warnings.append(f"⚠ Unable to validate GitHub username '{username}': HTTP {response.status_code}")
                return True  # Assume valid if we can't verify
        except requests.exceptions.RequestException as e:
            if debug:
                print(f"{Colors.RED}[DEBUG]{Colors.NC} Error validating username: {e}")
            self.warnings.append(f"⚠ Error validating GitHub username '{username}': {str(e)}")
            return True  # Assume valid if we can't verify
    
    def check_org_create_permission(self, org: str, username: str, debug: bool = False) -> bool:
        """
        Check if user has permission to create repositories in organization
        
        This method verifies multiple conditions to ensure the user can actually create repos:
        1. User must be a member of the organization
        2. Check user's role (admin/member)
        3. For admins: verify they have repo creation permissions (not just admin role)
        4. For members: check if org allows members to create repos
        5. Verify specific repository creation permissions based on org settings
        
        Args:
            org: GitHub organization
            username: Username to check
            debug: Enable debug logging
            
        Returns:
            True if user can create repos, False otherwise
        """
        # Convert email to GitHub username if it's the onepipeline FID
        actual_username = username
        if username == self.ONEPIPELINE_FID:
            actual_username = self.ONEPIPELINE_FID_USERNAME
            if debug:
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Converting {username} to GitHub username: {actual_username}")
        
        # Check if user is org member
        url = f"{self.api_url}/orgs/{org}/members/{actual_username}"
        
        if debug:
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Checking if {actual_username} is a member of org: {org}")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} API URL: {url}")
        
        try:
            response = requests.get(url, headers=self.headers, timeout=30)
            
            if debug:
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Membership check response: {response.status_code}")
            
            if response.status_code != 204:
                if debug:
                    print(f"{Colors.RED}[DEBUG]{Colors.NC} User {actual_username} is NOT a member of org {org}")
                self.errors.append(f"❌ {actual_username} is not a member of organization: {org}")
                return False
            
            if debug:
                print(f"{Colors.GREEN}[DEBUG]{Colors.NC} User {actual_username} is a member of org {org}")
            
            # Check org membership details to get role
            url = f"{self.api_url}/orgs/{org}/memberships/{actual_username}"
            if debug:
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Fetching membership details...")
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} API URL: {url}")
            
            response = requests.get(url, headers=self.headers, timeout=30)
            
            if response.status_code != 200:
                if debug:
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} Unable to fetch membership details: HTTP {response.status_code}")
                self.warnings.append(f"Unable to verify membership details for {actual_username} in {org}")
                return False
            
            data = response.json()
            role = data.get('role', '')
            
            if debug:
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} User role in org: {role}")
            
            # Fetch organization settings
            org_url = f"{self.api_url}/orgs/{org}"
            if debug:
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Fetching organization settings...")
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} API URL: {org_url}")
            
            org_response = requests.get(org_url, headers=self.headers, timeout=30)
            
            if org_response.status_code != 200:
                if debug:
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} Unable to fetch org settings: HTTP {org_response.status_code}")
                self.warnings.append(f"Unable to verify organization settings for {org}")
                return False
            
            org_data = org_response.json()
            
            # Check various repository creation permission settings
            members_can_create_repos = org_data.get('members_can_create_repositories', False)
            members_can_create_public_repos = org_data.get('members_can_create_public_repositories', False)
            members_can_create_private_repos = org_data.get('members_can_create_private_repositories', False)
            members_can_create_internal_repos = org_data.get('members_can_create_internal_repositories', False)
            
            if debug:
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Organization repository creation settings:")
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC}   - members_can_create_repositories: {members_can_create_repos}")
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC}   - members_can_create_public_repositories: {members_can_create_public_repos}")
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC}   - members_can_create_private_repositories: {members_can_create_private_repos}")
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC}   - members_can_create_internal_repositories: {members_can_create_internal_repos}")
            
            # Determine if user can create repos based on role and org settings
            if role == 'admin':
                # Even admins need to check if they have actual repo creation permissions
                # In some orgs, admins might be restricted from creating repos
                if debug:
                    print(f"{Colors.BLUE}[DEBUG]{Colors.NC} User is an admin. Checking if admins can create repos...")
                
                # Admins typically can create repos, but verify with org settings
                # If members_can_create_repositories is False and no specific type is allowed,
                # it might indicate restrictions even for admins
                can_create = (members_can_create_repos or
                             members_can_create_public_repos or
                             members_can_create_private_repos or
                             members_can_create_internal_repos)
                
                if can_create:
                    if debug:
                        print(f"{Colors.GREEN}[DEBUG]{Colors.NC} Admin {actual_username} can create repositories in {org}")
                    return True
                else:
                    if debug:
                        print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} Admin {actual_username} may have restricted repo creation permissions")
                        print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} Organization has disabled all repository creation options")
                    # Still return True for admins as they typically override restrictions
                    # but add a warning
                    self.warnings.append(
                        f"⚠ {actual_username} is an admin but org {org} has restrictive repo creation settings. "
                        f"Verify admin can actually create repos."
                    )
                    return True
            
            elif role == 'member':
                # For regular members, check if they have any repo creation permissions
                if debug:
                    print(f"{Colors.BLUE}[DEBUG]{Colors.NC} User is a regular member. Checking member permissions...")
                
                can_create = (members_can_create_repos or
                             members_can_create_public_repos or
                             members_can_create_private_repos or
                             members_can_create_internal_repos)
                
                if can_create:
                    if debug:
                        print(f"{Colors.GREEN}[DEBUG]{Colors.NC} Member {actual_username} can create repositories in {org}")
                        if members_can_create_public_repos:
                            print(f"{Colors.GREEN}[DEBUG]{Colors.NC}   - Can create public repos")
                        if members_can_create_private_repos:
                            print(f"{Colors.GREEN}[DEBUG]{Colors.NC}   - Can create private repos")
                        if members_can_create_internal_repos:
                            print(f"{Colors.GREEN}[DEBUG]{Colors.NC}   - Can create internal repos")
                    return True
                else:
                    if debug:
                        print(f"{Colors.RED}[DEBUG]{Colors.NC} Member {actual_username} CANNOT create repositories in {org}")
                        print(f"{Colors.RED}[DEBUG]{Colors.NC} Organization does not allow members to create repos")
                    self.errors.append(
                        f"❌ {actual_username} is a member but org {org} does not allow members to create repositories. "
                        f"User needs admin role or org settings must be changed."
                    )
                    return False
            else:
                if debug:
                    print(f"{Colors.RED}[DEBUG]{Colors.NC} Unknown role: {role}")
                self.errors.append(f"❌ Unknown role '{role}' for {actual_username} in org {org}")
                return False
            
        except requests.exceptions.RequestException as e:
            error_msg = f"Error checking org create permission for {actual_username} in {org}: {str(e)}"
            if debug:
                print(f"{Colors.RED}[DEBUG]{Colors.NC} {error_msg}")
            self.warnings.append(error_msg)
            return False
    
    def verify_permission(self, org: str, repo: str, username: str,
                         required_level: str, repo_type: str, debug: bool = False) -> bool:
        """
        Verify that user has required permission level on repository
        
        Args:
            org: GitHub organization
            repo: Repository name
            username: Username to check
            required_level: Required permission level ('admin', 'write', 'read')
            repo_type: Type of repository (for error messages)
            debug: Enable debug logging
            
        Returns:
            True if user has required permission, False otherwise
        """
        if debug:
            print(f"\n{Colors.BLUE}[DEBUG]{Colors.NC} {'='*60}")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Verifying permission for {username}")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Repository: {org}/{repo} ({repo_type})")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Required level: {required_level}")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} {'='*60}")
        
        permission = self.get_user_permission(org, repo, username, debug)
        
        if permission is None:
            error_msg = f"❌ Unable to verify {username} permission on {repo_type}: {org}/{repo}"
            if debug:
                print(f"{Colors.RED}[DEBUG]{Colors.NC} {error_msg}")
            self.errors.append(error_msg)
            return False
        
        required_perms = self.REQUIRED_PERMISSIONS.get(required_level, [])
        
        if debug:
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Actual permission: {permission}")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Acceptable permissions: {required_perms}")
        
        if permission in required_perms:
            success_msg = (f"✓ {username} has '{permission}' access on {repo_type}: {org}/{repo} "
                          f"(required: {required_level})")
            if debug:
                print(f"{Colors.GREEN}[DEBUG]{Colors.NC} {success_msg}")
            self.success_messages.append(success_msg)
            return True
        else:
            error_msg = (f"❌ {username} has '{permission}' access on {repo_type}: {org}/{repo}, "
                        f"but '{required_level}' is required")
            if debug:
                print(f"{Colors.RED}[DEBUG]{Colors.NC} {error_msg}")
            self.errors.append(error_msg)
            return False
    
    def verify_onboarding_yaml(self, yaml_path: str, debug: bool = False) -> bool:
        """
        Verify GitHub access based on onboarding.yaml configuration
        
        Args:
            yaml_path: Path to onboarding.yaml file
            debug: Enable debug logging
            
        Returns:
            True if all verifications pass, False otherwise
        """
        print(f"{Colors.BLUE}{'='*80}{Colors.NC}")
        print(f"{Colors.BLUE}GitHub Repository Access Verification{Colors.NC}")
        print(f"{Colors.BLUE}{'='*80}{Colors.NC}\n")
        
        if debug:
            print(f"{Colors.YELLOW}[DEBUG MODE ENABLED]{Colors.NC}\n")
        
        # Load service YAML file
        try:
            with open(yaml_path, 'r') as f:
                config = yaml.safe_load(f)
        except Exception as e:
            print(f"{Colors.RED}[ERROR]{Colors.NC} Failed to load YAML file: {e}")
            return False

        # Load commons.yaml — FIDs and GitHub usernames live there
        commons = {}
        try:
            _utils_dir = str(Path(__file__).resolve().parents[5] / "utils")
            if _utils_dir not in sys.path:
                sys.path.insert(0, _utils_dir)
            from commons_loader import load_commons, CommonsNotFoundError
            commons = load_commons(yaml_path)
            print(f"{Colors.GREEN}[SUCCESS]{Colors.NC} commons.yaml loaded for: {yaml_path}")
        except CommonsNotFoundError as _e:
            print(f"{Colors.RED}[ERROR]{Colors.NC} {_e}")
            return False
        except Exception as _e:
            print(f"{Colors.RED}[ERROR]{Colors.NC} Failed to load commons.yaml: {_e}")
            return False

        all_checks_passed = True

        # Extract configuration — service-specific fields from service yaml,
        # team-level fields (FIDs, GitHub usernames) from commons.yaml
        team_name    = commons.get('team_name', config.get('team_name', 'unknown'))
        service_name = config.get('service_name', 'unknown')
        # cicd_profile is a required field — no default applied
        cicd_profile = config.get('cicd_profile')
        if not cicd_profile:
            print(f"{Colors.RED}[ERROR]{Colors.NC} cicd_profile is required but not set. Allowed values: minimal | ci_only | ci_cd | cd_only")
            return False
        service_fid_dev  = commons.get('service_fid_dev', '')
        service_fid_prod = commons.get('service_fid_prod', '')
        service_fid_dev_github_username  = commons.get('service_fid_dev_github_username', '')
        service_fid_prod_github_username = commons.get('service_fid_prod_github_username', '')

        print(f"{Colors.BLUE}[INFO]{Colors.NC} Team: {team_name}")
        print(f"{Colors.BLUE}[INFO]{Colors.NC} Service: {service_name}")
        print(f"{Colors.BLUE}[INFO]{Colors.NC} CI/CD Profile: {cicd_profile}")
        print(f"{Colors.BLUE}[INFO]{Colors.NC} Service FID (Dev): {service_fid_dev}  [from commons.yaml]")
        print(f"{Colors.BLUE}[INFO]{Colors.NC} Service FID (Prod): {service_fid_prod}  [from commons.yaml]")
        print(f"{Colors.BLUE}[INFO]{Colors.NC} Service FID Dev GitHub Username: {service_fid_dev_github_username}  [from commons.yaml]")
        print(f"{Colors.BLUE}[INFO]{Colors.NC} Service FID Prod GitHub Username: {service_fid_prod_github_username}  [from commons.yaml]\n")

        # 0. Validate GitHub usernames
        print(f"\n{Colors.BLUE}[0/6]{Colors.NC} Validating GitHub usernames...")

        # Dev FID GitHub username is MANDATORY for all profiles
        if not service_fid_dev_github_username:
            self.errors.append(
                f"❌ MANDATORY field 'service_fid_dev_github_username' is missing in onboarding.yaml. "
                f"Please add the GitHub username for {service_fid_dev or 'service_fid_dev'}. "
                f"Find your username at: https://github.ibm.com/settings/profile"
            )
            all_checks_passed = False
        else:
            if not self.validate_github_username(service_fid_dev_github_username, service_fid_dev, debug):
                all_checks_passed = False

        # Prod FID GitHub username — not required for minimal (no production deployment)
        if cicd_profile == 'minimal':
            if service_fid_prod_github_username:
                print(f"{Colors.BLUE}[INFO]{Colors.NC} service_fid_prod_github_username provided "
                      f"(optional for minimal): {service_fid_prod_github_username}")
            else:
                print(f"{Colors.BLUE}[INFO]{Colors.NC} cicd_profile is 'minimal' — "
                      f"service_fid_prod_github_username is not required, skipping")
        else:
            if not service_fid_prod_github_username:
                self.errors.append(
                    f"❌ MANDATORY field 'service_fid_prod_github_username' is missing in onboarding.yaml. "
                    f"Please add the GitHub username for {service_fid_prod or 'service_fid_prod'}. "
                    f"Find your username at: https://github.ibm.com/settings/profile"
                )
                all_checks_passed = False
            else:
                if not self.validate_github_username(service_fid_prod_github_username, service_fid_prod, debug):
                    all_checks_passed = False

        # 1. Verify app repositories
        print(f"\n{Colors.BLUE}[1/6]{Colors.NC} Verifying app repository access "
              f"(onepipelineci@ibm.com: admin, clconc@us.ibm.com: at least write)...")
        app_repos = config.get('app_repo', [])
        
        if not app_repos:
            self.warnings.append("No app repositories defined in configuration")
        else:
            for idx, app_repo_config in enumerate(app_repos, 1):
                repo_url = app_repo_config.get('repo', '')
                if repo_url:
                    try:
                        # Add visual separator between repos
                        if idx > 1:
                            print(f"{Colors.CYAN}{'─' * 80}{Colors.NC}")
                        
                        org, repo = self.parse_repo_url(repo_url)
                        print(f"{Colors.CYAN}[Repository {idx}/{len(app_repos)}]{Colors.NC}")
                        print(f"{Colors.BLUE}[INFO]{Colors.NC} Checking {org}/{repo}...")
                        
                        if not self.check_repo_exists(org, repo):
                            self.errors.append(f"❌ App repository does not exist: {org}/{repo}")
                            all_checks_passed = False
                        else:
                            if not self.verify_permission(org, repo, self.ONEPIPELINE_FID,
                                                         'admin', 'app repository', debug):
                                all_checks_passed = False
                            if not self.verify_permission(org, repo, self.CLCONC_FID,
                                                         'write', 'app repository', debug):
                                all_checks_passed = False
                    except ValueError as e:
                        self.errors.append(f"❌ Invalid app repository URL: {repo_url} - {e}")
                        all_checks_passed = False
        
        # 2. Verify inventory repository
        print(f"\n{Colors.BLUE}[2/6]{Colors.NC} Verifying inventory repository access...")
        if cicd_profile == 'minimal':
            print(f"{Colors.BLUE}[INFO]{Colors.NC} cicd_profile is 'minimal' — "
                  f"inventory_repo access check skipped (no compliance inventory)")
        else:
          inventory_config = config.get('inventory_repo', {})
          inventory_url = inventory_config.get('repo', '')
          inventory_create = inventory_config.get('create', False)

          if inventory_url:
            try:
                org, repo = self.parse_repo_url(inventory_url)
                print(f"{Colors.BLUE}[INFO]{Colors.NC} Checking {org}/{repo}...")
                
                if inventory_create:
                    # Repo will be created by service_fid_dev — verify dev has org-level create permission.
                    # Neither FID can be checked against the repo at PR time (it doesn't exist yet).
                    # Access is governed by Access Hub — the merge pipeline will NOT grant access directly.
                    # After merge, both FIDs must request 'admin' access via Access Hub.
                    print(f"{Colors.BLUE}[INFO]{Colors.NC} Repo will be created by service_fid_dev — "
                          f"checking org creation permission...")

                    if service_fid_dev_github_username:
                        if self.check_org_create_permission(org, service_fid_dev_github_username, debug):
                            self.success_messages.append(
                                f"✓ {service_fid_dev_github_username} has permission to create repos in org: {org}"
                            )
                            self.warnings.append(
                                f"⚠ {service_fid_dev_github_username} 'admin' access on {org}/{repo} "
                                f"will be verified post-creation — ensure Access Hub approval is in place "
                                f"before merge or the pipeline will fail"
                            )
                        else:
                            all_checks_passed = False
                    else:
                        self.warnings.append(
                            f"⚠ service_fid_dev_github_username not provided — "
                            f"cannot verify inventory repo creation permission for dev FID in org: {org}"
                        )

                    # Prod FID cannot be verified against a repo that doesn't exist yet.
                    # The merge pipeline will verify admin access post-creation and fail (exit 1) if not present.
                    # Access must be pre-approved via Access Hub before the merge is triggered.
                    if service_fid_prod_github_username:
                        self.warnings.append(
                            f"⚠ {service_fid_prod_github_username} 'admin' access on {org}/{repo} "
                            f"will be verified post-creation — ensure Access Hub approval is in place "
                            f"before merge or the pipeline will fail"
                        )
                    elif cicd_profile != 'minimal':
                        self.warnings.append(
                            f"⚠ service_fid_prod_github_username not provided — "
                            f"prod FID 'admin' access on {org}/{repo} will not be verified after creation"
                        )
                else:
                    # Verify existing repo access
                    if not self.check_repo_exists(org, repo):
                        self.errors.append(f"❌ Inventory repository does not exist: {org}/{repo}")
                        all_checks_passed = False
                    else:
                        # onepipelineci needs at least write access
                        if not self.verify_permission(org, repo, self.ONEPIPELINE_FID,
                                                     'write', 'inventory repository', debug):
                            all_checks_passed = False
                        
                        # service FIDs need admin access
                        if service_fid_dev_github_username:
                            if not self.verify_permission(org, repo, service_fid_dev_github_username,
                                                         'admin', 'inventory repository', debug):
                                all_checks_passed = False
                        elif service_fid_dev:
                            self.warnings.append(
                                f"⚠ service_fid_dev_github_username not provided for {service_fid_dev}. "
                                f"Please add 'service_fid_dev_github_username' field to onboarding.yaml"
                            )
                        
                        if service_fid_prod_github_username:
                            if not self.verify_permission(org, repo, service_fid_prod_github_username,
                                                         'admin', 'inventory repository', debug):
                                all_checks_passed = False
                        elif service_fid_prod:
                            self.warnings.append(
                                f"⚠ service_fid_prod_github_username not provided for {service_fid_prod}. "
                                f"Please add 'service_fid_prod_github_username' field to onboarding.yaml"
                            )
            except ValueError as e:
                self.errors.append(f"❌ Invalid inventory repository URL: {inventory_url} - {e}")
                all_checks_passed = False
          else:
              self.warnings.append("No inventory repository defined in configuration")

        # 3. Verify incident repository
        print(f"\n{Colors.BLUE}[3/6]{Colors.NC} Verifying incident repository access...")
        if cicd_profile == 'minimal':
            print(f"{Colors.BLUE}[INFO]{Colors.NC} cicd_profile is 'minimal' — "
                  f"incident_repo access check skipped (no CD pipeline)")
        else:
          incident_config = config.get('incident_repo', {})
          incident_url = incident_config.get('repo', '')
          incident_branch = incident_config.get('branch', '')
          incident_create = incident_config.get('create', False)

          if incident_url:
            try:
                org, repo = self.parse_repo_url(incident_url)
                print(f"{Colors.BLUE}[INFO]{Colors.NC} Checking {org}/{repo}...")
                repo_exists = self.check_repo_exists(org, repo)
                
                if incident_create:
                    if repo_exists:
                        self.errors.append(f"❌ Incident repository already exists: {org}/{repo}")
                        all_checks_passed = False
                    else:
                        # Repo will be created by service_fid_dev — verify dev has org-level create permission.
                        # Neither FID can be checked against the repo at PR time (it doesn't exist yet).
                        # Access is governed by Access Hub — the merge pipeline will NOT grant access directly.
                        # After merge, both FIDs must request 'admin' access via Access Hub.
                        print(f"{Colors.BLUE}[INFO]{Colors.NC} Repo will be created by service_fid_dev — "
                              f"checking org creation permission...")

                        if service_fid_dev_github_username:
                            if self.check_org_create_permission(org, service_fid_dev_github_username, debug):
                                self.success_messages.append(
                                    f"✓ {service_fid_dev_github_username} has permission to create repos in org: {org}"
                                )
                                self.warnings.append(
                                    f"⚠ {service_fid_dev_github_username} 'admin' access on {org}/{repo} "
                                    f"will be verified post-creation — ensure Access Hub approval is in place "
                                    f"before merge or the pipeline will fail"
                                )
                            else:
                                all_checks_passed = False
                        else:
                            self.warnings.append(
                                f"⚠ service_fid_dev_github_username not provided — "
                                f"cannot verify incident repo creation permission for dev FID in org: {org}"
                            )

                        # Prod FID cannot be verified against a repo that doesn't exist yet.
                        # The merge pipeline will verify admin access post-creation and fail (exit 1) if not present.
                        # Access must be pre-approved via Access Hub before the merge is triggered.
                        if service_fid_prod_github_username:
                            self.warnings.append(
                                f"⚠ {service_fid_prod_github_username} 'admin' access on {org}/{repo} "
                                f"will be verified post-creation — ensure Access Hub approval is in place "
                                f"before merge or the pipeline will fail"
                            )
                        elif cicd_profile != 'minimal':
                            self.warnings.append(
                                f"⚠ service_fid_prod_github_username not provided — "
                                f"prod FID 'admin' access on {org}/{repo} will not be verified after creation"
                            )
                else:
                    # Verify existing repo access
                    if not repo_exists:
                        self.errors.append(f"❌ Incident repository does not exist: {org}/{repo}")
                        all_checks_passed = False
                    else:
                        if incident_branch:
                            branch_url = f"{self.api_url}/repos/{org}/{repo}/branches/{incident_branch}"
                            response = requests.get(branch_url, headers=self.headers, timeout=30)
                            if response.status_code == 200:
                                self.success_messages.append(
                                    f"✓ Incident repository branch exists: {org}/{repo}@{incident_branch}"
                                )
                            else:
                                self.errors.append(
                                    f"❌ Incident repository branch does not exist: {org}/{repo}@{incident_branch}"
                                )
                                all_checks_passed = False
                        
                        if not self.verify_permission(org, repo, self.ONEPIPELINE_FID,
                                                     'admin', 'incident repository', debug):
                            all_checks_passed = False
                        
                        if service_fid_dev_github_username:
                            if not self.verify_permission(org, repo, service_fid_dev_github_username,
                                                         'admin', 'incident repository', debug):
                                all_checks_passed = False
                        
                        if service_fid_prod_github_username:
                            if not self.verify_permission(org, repo, service_fid_prod_github_username,
                                                         'admin', 'incident repository', debug):
                                all_checks_passed = False
            except ValueError as e:
                self.errors.append(f"❌ Invalid incident repository URL: {incident_url} - {e}")
                all_checks_passed = False
          else:
              self.warnings.append("No incident repository defined in configuration")

        # 4. Verify mandatory files repositories
        print(f"\n{Colors.BLUE}[4/6]{Colors.NC} Verifying mandatory files repository access...")
        mandatory_files = config.get('mandatory_files', [])
        
        for file_config in mandatory_files:
            repo_url = file_config.get('repo', '')
            if repo_url:
                try:
                    org, repo = self.parse_repo_url(repo_url)
                    print(f"{Colors.BLUE}[INFO]{Colors.NC} Checking {org}/{repo}...")
                    
                    if not self.check_repo_exists(org, repo):
                        self.errors.append(f"❌ Mandatory files repository does not exist: {org}/{repo}")
                        all_checks_passed = False
                    else:
                        # Verify onepipelineci has at least read access
                        permission = self.get_user_permission(org, repo, self.ONEPIPELINE_FID, debug)
                        if permission and permission in ['admin', 'write', 'read']:
                            self.success_messages.append(
                                f"✓ {self.ONEPIPELINE_FID} has '{permission}' access on mandatory files repo: {org}/{repo}"
                            )
                        else:
                            self.warnings.append(
                                f"⚠ {self.ONEPIPELINE_FID} may not have access to mandatory files repo: {org}/{repo}"
                            )
                except ValueError as e:
                    self.errors.append(f"❌ Invalid mandatory files repository URL: {repo_url} - {e}")
                    all_checks_passed = False
        
        # 5. Verify optional files repositories (if they exist)
        print(f"\n{Colors.BLUE}[5/6]{Colors.NC} Verifying optional files repository access...")
        optional_files = config.get('optional_files', [])
        
        if optional_files:
            for file_config in optional_files:
                repo_url = file_config.get('repo', '')
                if repo_url:
                    try:
                        org, repo = self.parse_repo_url(repo_url)
                        print(f"{Colors.BLUE}[INFO]{Colors.NC} Checking {org}/{repo}...")
                        
                        if not self.check_repo_exists(org, repo):
                            self.warnings.append(f"⚠ Optional files repository does not exist: {org}/{repo}")
                        else:
                            # Verify onepipelineci has at least read access
                            permission = self.get_user_permission(org, repo, self.ONEPIPELINE_FID, debug)
                            if permission and permission in ['admin', 'write', 'read']:
                                self.success_messages.append(
                                    f"✓ {self.ONEPIPELINE_FID} has '{permission}' access on optional files repo: {org}/{repo}"
                                )
                            else:
                                self.warnings.append(
                                    f"⚠ {self.ONEPIPELINE_FID} may not have access to optional files repo: {org}/{repo}"
                                )
                    except ValueError as e:
                        self.warnings.append(f"⚠ Invalid optional files repository URL: {repo_url} - {e}")
        else:
            print(f"{Colors.BLUE}[INFO]{Colors.NC} No optional files repositories defined")
        
        # 6. Summary
        print(f"\n{Colors.BLUE}[6/6]{Colors.NC} Verification Summary")
        print(f"{Colors.BLUE}{'='*80}{Colors.NC}\n")
        
        # Print success messages
        if self.success_messages:
            print(f"{Colors.GREEN}✓ Successful Checks:{Colors.NC}")
            for msg in self.success_messages:
                print(f"  {Colors.GREEN}{msg}{Colors.NC}")
            print()
        
        # Print warnings
        if self.warnings:
            print(f"{Colors.YELLOW}⚠ Warnings:{Colors.NC}")
            for warning in self.warnings:
                print(f"  {Colors.YELLOW}{warning}{Colors.NC}")
            print()
        
        # Print errors
        if self.errors:
            print(f"{Colors.RED}✗ Errors:{Colors.NC}")
            for error in self.errors:
                print(f"  {Colors.RED}{error}{Colors.NC}")
            print()
        
        # Final result
        if all_checks_passed and not self.errors:
            print(f"{Colors.GREEN}{'='*80}{Colors.NC}")
            print(f"{Colors.GREEN}[SUCCESS] All GitHub access verifications passed! ✓{Colors.NC}")
            print(f"{Colors.GREEN}{'='*80}{Colors.NC}")
            return True
        else:
            print(f"{Colors.RED}{'='*80}{Colors.NC}")
            print(f"{Colors.RED}[FAILURE] Some GitHub access verifications failed! ✗{Colors.NC}")
            print(f"{Colors.RED}{'='*80}{Colors.NC}")
            return False


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Verify GitHub repository access for functional IDs based on onboarding.yaml'
    )
    parser.add_argument(
        'yaml_file',
        help='Path to onboarding.yaml file'
    )
    parser.add_argument(
        '--token',
        help='GitHub personal access token (can also use GITHUB_TOKEN or GHE_TOKEN env var)'
    )
    parser.add_argument(
        '--api-url',
        default='https://github.ibm.com/api/v3',
        help='GitHub Enterprise API URL (default: https://github.ibm.com/api/v3)'
    )
    parser.add_argument(
        '--debug',
        action='store_true',
        help='Enable debug logging to troubleshoot permission issues'
    )
    
    args = parser.parse_args()
    
    # Get GitHub token
    token = args.token or os.environ.get('GITHUB_TOKEN') or os.environ.get('GHE_TOKEN')
    
    if not token:
        print(f"{Colors.RED}[ERROR]{Colors.NC} GitHub token not provided!")
        print(f"{Colors.YELLOW}[INFO]{Colors.NC} Please provide token via:")
        print("  1. --token argument")
        print("  2. GITHUB_TOKEN environment variable")
        print("  3. GHE_TOKEN environment variable")
        sys.exit(1)
    
    # Check if YAML file exists
    if not os.path.isfile(args.yaml_file):
        print(f"{Colors.RED}[ERROR]{Colors.NC} YAML file not found: {args.yaml_file}")
        sys.exit(1)
    
    # Run verification
    verifier = GitHubAccessVerifier(token, args.api_url)
    
    try:
        success = verifier.verify_onboarding_yaml(args.yaml_file, debug=args.debug)
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"{Colors.RED}[ERROR]{Colors.NC} Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()


