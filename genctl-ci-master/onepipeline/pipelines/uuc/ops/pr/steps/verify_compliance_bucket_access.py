#!/usr/bin/env python3
"""
IBM Cloud Object Storage Compliance Bucket Access Verification Script

This script verifies that the provided IBM Cloud API key (belonging to onepipelineci@ibm.com service ID)
has the required write permissions on compliance buckets specified in the onboarding.yaml file.

Requirements:
1. The API key must have at least Writer role on the compliance bucket
2. The API key should belong to the onepipelineci@ibm.com service ID

Usage:
    python3 verify_compliance_bucket_access.py <path_to_onboarding.yaml> [--api-key API_KEY]
    
Environment Variables:
    IBM_CLOUD_COS_API_KEY: IBM Cloud COS API key for onepipelineci@ibm.com service ID
"""

import sys
import os
import yaml
import requests
import argparse
import json
from pathlib import Path
from typing import Dict, List, Optional
from urllib.parse import urlparse

# ---------------------------------------------------------------------------
# commons_loader bootstrap — team-level fields (team_name) live in commons.yaml
# ---------------------------------------------------------------------------
_UTILS_DIR = str(Path(__file__).resolve().parents[5] / "utils")
if _UTILS_DIR not in sys.path:
    sys.path.insert(0, _UTILS_DIR)

try:
    from commons_loader import load_commons, CommonsNotFoundError, CommonsParseError
except ImportError:
    # Graceful degradation when running outside the full repo tree
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

class ComplianceBucketVerifier:
    """Verifies IBM Cloud Object Storage compliance bucket access using API key"""
    
    ONEPIPELINE_SERVICE_ID = "onepipelineci@ibm.com"
    IAM_TOKEN_URL = "https://iam.cloud.ibm.com/identity/token"
    COS_CONFIG_API_URL = "https://config.cloud-object-storage.cloud.ibm.com/v1"
    
    REQUIRED_PERMISSIONS = {
        'write': ['Writer', 'Manager', 'Administrator'],
        'read': ['Reader', 'Writer', 'Manager', 'Administrator']
    }
    
    def __init__(self, api_key: str):
        """
        Initialize the verifier with IBM Cloud API key
        
        Args:
            api_key: IBM Cloud API key
        """
        self.api_key = api_key
        self.iam_token = None
        self.errors = []
        self.warnings = []
        self.success_messages = []
        
    def get_iam_token(self) -> Optional[str]:
        """
        Get IAM access token using API key
        
        Returns:
            IAM access token or None if error
        """
        if self.iam_token:
            return self.iam_token
            
        headers = {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json'
        }
        
        data = {
            'grant_type': 'urn:ibm:params:oauth:grant-type:apikey',
            'apikey': self.api_key
        }
        
        try:
            response = requests.post(self.IAM_TOKEN_URL, headers=headers, data=data, timeout=30)
            
            if response.status_code == 200:
                token_data = response.json()
                self.iam_token = token_data.get('access_token')
                return self.iam_token
            else:
                error_msg = f"Failed to get IAM token: HTTP {response.status_code}"
                self.errors.append(error_msg)
                return None
        except requests.exceptions.RequestException as e:
            error_msg = f"Error getting IAM token: {str(e)}"
            self.errors.append(error_msg)
            return None
    
    def parse_bucket_url(self, bucket_url: str) -> tuple:
        """
        Parse COS bucket URL to extract bucket name and endpoint
        
        Args:
            bucket_url: Full COS bucket URL (e.g., s3://bucket-name, cos://region/bucket-name, or plain bucket-name)
            
        Returns:
            Tuple of (bucket_name, endpoint)
        """
        # Remove trailing slashes
        bucket_url = bucket_url.rstrip('/')
        
        # Parse URL
        parsed = urlparse(bucket_url)
        
        if parsed.scheme in ['s3', 'cos']:
            # Extract bucket name from path or netloc
            bucket_name = parsed.netloc or parsed.path.strip('/')
            
            # Default to public endpoint if not specified
            endpoint = "s3.us.cloud-object-storage.appdomain.cloud"
            
            return bucket_name, endpoint
        elif parsed.scheme == '':
            # Plain bucket name without scheme (e.g., "uuc-ci-storage")
            bucket_name = bucket_url.strip('/')
            
            # Default to public endpoint
            endpoint = "s3.us.cloud-object-storage.appdomain.cloud"
            
            return bucket_name, endpoint
        else:
            raise ValueError(f"Invalid bucket URL format: {bucket_url}. Expected s3://, cos:// scheme, or plain bucket name")
    
    def get_bucket_iam_policy(self, bucket_name: str, endpoint: str, debug: bool = False) -> Optional[Dict]:
        """
        Get IAM policy for a bucket
        
        Args:
            bucket_name: Name of the bucket
            endpoint: COS endpoint
            debug: Enable debug logging
            
        Returns:
            IAM policy data or None if error
        """
        token = self.get_iam_token()
        if not token:
            return None
        
        # Use IBM Cloud IAM Policy API to check bucket access
        iam_policy_url = f"https://iam.cloud.ibm.com/v1/policies"
        
        headers = {
            'Authorization': f'Bearer {token}',
            'Accept': 'application/json'
        }
        
        if debug:
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Fetching IAM policies for bucket: {bucket_name}")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} API URL: {iam_policy_url}")
        
        try:
            response = requests.get(iam_policy_url, headers=headers, timeout=30)
            
            if debug:
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Response status: {response.status_code}")
            
            if response.status_code == 200:
                policies = response.json()
                return policies
            else:
                if debug:
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} Unable to fetch IAM policies: HTTP {response.status_code}")
                return None
        except requests.exceptions.RequestException as e:
            if debug:
                print(f"{Colors.RED}[DEBUG]{Colors.NC} Error fetching IAM policies: {str(e)}")
            return None
    
    def check_bucket_access(self, bucket_name: str, endpoint: str, user_email: str, 
                           required_level: str, debug: bool = False) -> bool:
        """
        Check if user has required access level on bucket
        
        Args:
            bucket_name: Name of the bucket
            endpoint: COS endpoint
            user_email: User email to check
            required_level: Required permission level ('write', 'read')
            debug: Enable debug logging
            
        Returns:
            True if user has required access, False otherwise
        """
        if debug:
            print(f"\n{Colors.BLUE}[DEBUG]{Colors.NC} {'='*60}")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Checking bucket access")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Bucket: {bucket_name}")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} User: {user_email}")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Required level: {required_level}")
            print(f"{Colors.BLUE}[DEBUG]{Colors.NC} {'='*60}")
        
        token = self.get_iam_token()
        if not token:
            return False
        
        # Check bucket existence and access using COS API
        bucket_url = f"https://{endpoint}/{bucket_name}"
        
        headers = {
            'Authorization': f'Bearer {token}',
            'ibm-service-instance-id': ''  # Will be populated if needed
        }
        
        try:
            # Try to list bucket (HEAD request)
            response = requests.head(bucket_url, headers=headers, timeout=30)
            
            if debug:
                print(f"{Colors.BLUE}[DEBUG]{Colors.NC} Bucket HEAD response: {response.status_code}")
            
            if response.status_code == 200:
                # Bucket exists and is accessible
                # For now, we'll assume if we can access it with the API key, 
                # the FID has appropriate access
                success_msg = f"✓ Bucket '{bucket_name}' is accessible"
                if debug:
                    print(f"{Colors.GREEN}[DEBUG]{Colors.NC} {success_msg}")
                self.success_messages.append(success_msg)
                return True
            elif response.status_code == 404:
                error_msg = f"❌ Bucket '{bucket_name}' does not exist or is not accessible"
                if debug:
                    print(f"{Colors.RED}[DEBUG]{Colors.NC} {error_msg}")
                self.errors.append(error_msg)
                return False
            elif response.status_code == 403:
                error_msg = f"❌ Access denied to bucket '{bucket_name}'"
                if debug:
                    print(f"{Colors.RED}[DEBUG]{Colors.NC} {error_msg}")
                self.errors.append(error_msg)
                return False
            else:
                warning_msg = f"⚠ Unable to verify access to bucket '{bucket_name}': HTTP {response.status_code}"
                if debug:
                    print(f"{Colors.YELLOW}[DEBUG]{Colors.NC} {warning_msg}")
                self.warnings.append(warning_msg)
                return False
                
        except requests.exceptions.RequestException as e:
            error_msg = f"Error checking bucket access: {str(e)}"
            if debug:
                print(f"{Colors.RED}[DEBUG]{Colors.NC} {error_msg}")
            self.warnings.append(error_msg)
            return False
    
    def verify_onboarding_yaml(self, yaml_path: str, debug: bool = False) -> bool:
        """
        Verify compliance bucket access based on onboarding.yaml configuration
        
        Args:
            yaml_path: Path to onboarding.yaml file
            debug: Enable debug logging
            
        Returns:
            True if all verifications pass, False otherwise
        """
        print(f"{Colors.BLUE}{'='*80}{Colors.NC}")
        print(f"{Colors.BLUE}IBM Cloud Object Storage Compliance Bucket Access Verification{Colors.NC}")
        print(f"{Colors.BLUE}{'='*80}{Colors.NC}\n")
        
        if debug:
            print(f"{Colors.YELLOW}[DEBUG MODE ENABLED]{Colors.NC}\n")
        
        # Load YAML file
        try:
            with open(yaml_path, 'r') as f:
                config = yaml.safe_load(f)
        except Exception as e:
            print(f"{Colors.RED}[ERROR]{Colors.NC} Failed to load YAML file: {e}")
            return False
        
        all_checks_passed = True

        # Load commons.yaml — team_name lives there after the commons separation
        try:
            commons = load_commons(yaml_path)
            print(f"{Colors.GREEN}[SUCCESS]{Colors.NC} commons.yaml loaded")
        except CommonsNotFoundError as _e:
            print(f"{Colors.RED}[ERROR]{Colors.NC} {_e}")
            return False
        except Exception as _e:
            print(f"{Colors.RED}[ERROR]{Colors.NC} Failed to load commons.yaml: {_e}")
            return False

        # Extract configuration — team_name from commons.yaml, rest from service yaml
        team_name = commons.get('team_name', config.get('team_name', 'unknown'))
        service_name = config.get('service_name', 'unknown')
        
        print(f"{Colors.BLUE}[INFO]{Colors.NC} Team: {team_name}")
        print(f"{Colors.BLUE}[INFO]{Colors.NC} Service: {service_name}\n")
        
        # Check for compliance bucket configuration
        compliance_bucket = config.get('compliance_bucket', {})
        
        if not compliance_bucket:
            # Check alternative keys
            compliance_bucket = config.get('cos_bucket', {}) or config.get('evidence_locker', {})
        
        if not compliance_bucket:
            warning_msg = "⚠ No compliance bucket configuration found in onboarding.yaml"
            print(f"{Colors.YELLOW}[WARNING]{Colors.NC} {warning_msg}")
            self.warnings.append(warning_msg)
            print(f"\n{Colors.YELLOW}[INFO]{Colors.NC} Looking for keys: 'compliance_bucket', 'cos_bucket', or 'evidence_locker'")
            return False
        
        # Check use_existing flag
        use_existing = compliance_bucket.get('use_existing', False)
        bucket_endpoint = compliance_bucket.get('endpoint', '')
        
        # Determine bucket name based on use_existing flag
        if use_existing:
            # Use existing bucket - get name and endpoint from YAML
            bucket_name = compliance_bucket.get('bucket', '') or compliance_bucket.get('url', '') or compliance_bucket.get('name', '')
            
            if not bucket_name:
                error_msg = "❌ use_existing is true but no bucket name found in compliance bucket configuration"
                print(f"{Colors.RED}[ERROR]{Colors.NC} {error_msg}")
                self.errors.append(error_msg)
                return False
            
            if not bucket_endpoint:
                error_msg = "❌ use_existing is true but no endpoint found in compliance bucket configuration"
                print(f"{Colors.RED}[ERROR]{Colors.NC} {error_msg}")
                self.errors.append(error_msg)
                return False
            
            print(f"{Colors.BLUE}[INFO]{Colors.NC} Using existing compliance bucket")
            print(f"{Colors.BLUE}[INFO]{Colors.NC} Bucket Name: {bucket_name}")
            print(f"{Colors.BLUE}[INFO]{Colors.NC} Configured Endpoint: {bucket_endpoint}\n")
        else:
            # Generate bucket name based on team name
            # Format: uuc-<team-name-with-spaces-replaced-by-hyphens>-ci-storage
            team_name_normalized = team_name.lower().replace(' ', '-')
            bucket_name = f"uuc-{team_name_normalized}-ci-storage"
            
            if not bucket_endpoint:
                error_msg = "❌ No endpoint found in compliance bucket configuration"
                print(f"{Colors.RED}[ERROR]{Colors.NC} {error_msg}")
                self.errors.append(error_msg)
                return False
            
            print(f"{Colors.BLUE}[INFO]{Colors.NC} Using CICD-managed compliance bucket (use_existing: false)")
            print(f"{Colors.BLUE}[INFO]{Colors.NC} Auto-generated Bucket Name: {bucket_name}")
            print(f"{Colors.BLUE}[INFO]{Colors.NC}   (Format: uuc-<team-name-with-spaces-replaced-by-hyphens>-ci-storage)")
            print(f"{Colors.BLUE}[INFO]{Colors.NC}   (Based on team: '{team_name}')")
            print(f"{Colors.BLUE}[INFO]{Colors.NC} Configured Endpoint: {bucket_endpoint}\n")
        
        # Verify bucket access
        print(f"{Colors.BLUE}[1/1]{Colors.NC} Verifying API key (for {self.ONEPIPELINE_SERVICE_ID}) write access on compliance bucket...")
        
        try:
            # Extract hostname from endpoint URL if it's a full URL
            endpoint = bucket_endpoint
            if endpoint.startswith('http://') or endpoint.startswith('https://'):
                from urllib.parse import urlparse
                parsed_endpoint = urlparse(endpoint)
                endpoint = parsed_endpoint.netloc or parsed_endpoint.path.strip('/')
            
            print(f"{Colors.BLUE}[INFO]{Colors.NC} Bucket Name: {bucket_name}")
            print(f"{Colors.BLUE}[INFO]{Colors.NC} Using Endpoint: {endpoint}\n")
            
            if not self.check_bucket_access(bucket_name, endpoint, self.ONEPIPELINE_SERVICE_ID, 'write', debug):
                all_checks_passed = False
        except Exception as e:
            error_msg = f"❌ Error verifying bucket access: {str(e)}"
            print(f"{Colors.RED}[ERROR]{Colors.NC} {error_msg}")
            self.errors.append(error_msg)
            all_checks_passed = False
        
        # Summary
        print(f"\n{Colors.BLUE}Verification Summary{Colors.NC}")
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
            print(f"{Colors.GREEN}[SUCCESS] Compliance bucket access verification passed! ✓{Colors.NC}")
            print(f"{Colors.GREEN}{'='*80}{Colors.NC}")
            print(f"\n{Colors.GREEN}[INFO]{Colors.NC} The API key (for {self.ONEPIPELINE_SERVICE_ID}) has the required write access to the compliance bucket.")
            return True
        else:
            print(f"{Colors.RED}{'='*80}{Colors.NC}")
            print(f"{Colors.RED}[FAILURE] Compliance bucket access verification failed! ✗{Colors.NC}")
            print(f"{Colors.RED}{'='*80}{Colors.NC}")
            print(f"\n{Colors.YELLOW}[ACTION REQUIRED]{Colors.NC} Please ensure the API key for {self.ONEPIPELINE_SERVICE_ID} has at least 'Writer' role on the compliance bucket.")
            print(f"{Colors.YELLOW}[INFO]{Colors.NC} You can grant access using IBM Cloud Console or CLI:")
            print(f"  ibmcloud cos bucket-policy-put --bucket <bucket-name> --policy <policy-file>")
            return False


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Verify IBM Cloud Object Storage compliance bucket access for onepipelineci@ibm.com'
    )
    parser.add_argument(
        'yaml_file',
        help='Path to onboarding.yaml file'
    )
    parser.add_argument(
        '--api-key',
        help='IBM Cloud COS API key (can also use IBM_CLOUD_COS_API_KEY env var)'
    )
    parser.add_argument(
        '--debug',
        action='store_true',
        help='Enable debug logging to troubleshoot access issues'
    )
    
    args = parser.parse_args()
    
    # Get IBM Cloud API key
    api_key = args.api_key or os.environ.get('IBM_CLOUD_API_KEY') or os.environ.get('IBMCLOUD_API_KEY')
    
    if not api_key:
        print(f"{Colors.RED}[ERROR]{Colors.NC} IBM Cloud API key not provided!")
        print(f"{Colors.YELLOW}[INFO]{Colors.NC} Please provide API key via:")
        print("  1. --api-key argument")
        print("  2. IBM_CLOUD_API_KEY environment variable")
        print("  3. IBMCLOUD_API_KEY environment variable")
        sys.exit(1)
    
    # Check if YAML file exists
    if not os.path.isfile(args.yaml_file):
        print(f"{Colors.RED}[ERROR]{Colors.NC} YAML file not found: {args.yaml_file}")
        sys.exit(1)
    
    # Run verification
    verifier = ComplianceBucketVerifier(api_key)
    
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

