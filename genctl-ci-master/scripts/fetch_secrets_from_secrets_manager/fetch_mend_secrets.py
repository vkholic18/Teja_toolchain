# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# This function is designed to export Mend SAST secrets from a secret group to mend-sast-info.sh file
# usage example:
from ibm_cloud_sdk_core.authenticators.iam_authenticator import IAMAuthenticator
from ibm_secrets_manager_sdk.secrets_manager_v2 import *
import argparse
import json
import sys


def parse_args():
    """parsing cli args

    Returns:
        objects: parser object
    """
    parser = argparse.ArgumentParser(
        description='Fetch a secret from IBM Secrets Manager instance')
    parser.add_argument('-se', '--secrets-manager-endpoint-url', type=str,
                        help='URL of the Secrets Manager endpoint instance', required=True)
    parser.add_argument('-ck', '--cloud-apikey', type=str,
                        help='API key for the Secrets Manager instance', required=True)    
    parser.add_argument('-sg', '--secret-group-name', type=str,
                        help='Secret group name to fetch the secrets', required=True)    
    args = parser.parse_args()
    return args


def get_sm_service(sm_endpoint_url, sm_api_key):
    """Initiating the SecretManager service

    Args:
        sm_endpoint_url (string): public endpoint of the SM
        sm_api_key (string): cloud api key

    Returns:
        object: SM type
    """
    # Authenticate to IBM Secret Manager
    authenticator = IAMAuthenticator(apikey=sm_api_key)
    secrets_manager_service = SecretsManagerV2(
        authenticator=authenticator)
    secrets_manager_service.set_service_url(sm_endpoint_url)
    return secrets_manager_service


def get_all_secrets(sm_client, secret_group_id):
    """gets all secrets from a given sm client

    Args:
        sm_client (SecretsManagerV2): sm client object
        secret_group_id (string): secret group id 
    Returns:
        dic: json formatted secret results
    """
    all_results = []
    pager = SecretsPager(
        client=sm_client,
        limit=10,
        sort='created_at',
        groups=secret_group_id
    )
    while pager.has_next():
        next_page = pager.get_next()
        assert next_page is not None
        all_results.extend(next_page)
    return json.loads(json.dumps(all_results, indent=2))

def get_secret_group_id(sm_client, sg_name):
    """gets all secret groups from the sm instnace

    Args:
        sm_client (SecretsManagerV2): sm client object
        sg_name (string): secret group name
    Returns:
        string: secret group id
    """
    secret_group_id = None
    try:        
        response = sm_client.list_secret_groups()        
        secret_groups_list = response.get_result()
        if secret_groups_list['secret_groups']:            
            for secret_group in secret_groups_list['secret_groups']:
                if(secret_group['name'] == sg_name):
                    secret_group_id = secret_group['id']
                    print(f"Secret group found with name {sg_name}")
                    break
        else:
            print("No secret_groups found")

        if secret_group_id is None:
            print(f"No secret group found with name {sg_name}")
            sys.exit(1)
        else:
            return secret_group_id
    except Exception as e:
        print("Failed to list secrets: ", e)
        sys.exit(1)

def append_to_file(key, value):
    """writes the data into mend-sast-info.sh file

    Args:
        key (string) : environment variable key
        value (string): evnironment value    
    """
    try:
        file1 = open("mend-sast-info.sh", "a")  # append mode
        file1.write(f"set_env {key} \"{value}\"\n")
        file1.close()
    except Exception as e:
        print("Not able to write to a file mend-sast-info.sh",e)
        sys.exit(1)

def get_required_secret_name(secret_name, required_secrets):
    """
    Returns the required secret name if the secret matches one of the
    required secrets, otherwise returns None.

    Examples:
        ibm-mend-user-key
            -> mend-user-key

        sg-uuc-xxx-PSIRT_xxx-mend-user-key
            -> mend-user-key

        sg-uuc-xxx-PSIRT_xxxx-mend-org-token
            -> mend-org-token
    """
    if not secret_name:
        raise ValueError("Secret name is empty.")

    if not isinstance(secret_name, str):
        raise TypeError("Secret name must be a string.")

    for required_secret in required_secrets:
        if secret_name.endswith(required_secret):
            return required_secret

    return None


def export_mend_secrets(secrets_manager_service, all_secrets, secret_group_name):
    """Export the required Mend SAST secrets.

    Args:
        secrets_manager_service (SecretsManagerV2): Secrets Manager client.
        all_secrets (list): List of secrets.
        secret_group_name (str): Secret group name.
    """
    list_of_secrets_to_export = ["mend-user-key", "mend-org-token"]

    for secret in all_secrets:
        secret_name = secret.get("name")
        secret_id = secret.get("id")

        try:
            if not secret_id:
                raise ValueError(f"Secret '{secret_name}' does not contain an id.")

            matched_secret = get_required_secret_name(
                secret_name,
                list_of_secrets_to_export
            )

            if matched_secret is None:
                print(
                    f"{secret_name} is not a required secret in secret_group "
                    f"{secret_group_name}"
                )
                continue

            secret_data = secrets_manager_service.get_secret(
                id=secret_id
            ).get_result()

            payload = secret_data.get("payload")
            if payload is None:
                raise ValueError(
                    f"Payload not available for secret '{secret_name}' "
                    f"in secret_group '{secret_group_name}'."
                )

            print(f"Exporting {matched_secret} secret")
            append_to_file(matched_secret, payload)

            list_of_secrets_to_export.remove(matched_secret)

        except (ValueError, TypeError) as e:
            print(f"Validation error for secret '{secret_name}': {e}")
            sys.exit(1)
        except Exception as e:
            print(f"Failed to process secret '{secret_name}': {e}")
            sys.exit(1)

    if list_of_secrets_to_export:
        print(
            "Failed to export required environment variables: "
            f"{list_of_secrets_to_export}"
        )
        sys.exit(1)

def fetch_secrets_from_secret_group(secrets_manager_endpoint_url, cloud_apikey, secret_group_name):
    """_summary_

    Args:
        secrets_manager_endpoint_url (string): secret manager source public endpoint
        cloud_apikey (string): cloud apikey
        secret_group_name (string): secret group name

    Returns:
        list, list: list of new secrets, list of updated secrets
    """
    sg_split = str(secret_group_name).split('-')    
    if len(sg_split) != 3:    
        print(f"The secret group name '{secret_group_name}' is not in the correct format. It should follow the pattern: sg-mend-<PSIRT_ID>")
        sys.exit(1)
    # Get secrets from source IBM Secret Manager
    print("init secrets manager")
    secrets_manager_service = get_sm_service(
        secrets_manager_endpoint_url, cloud_apikey)    
    secret_group_id = get_secret_group_id(secrets_manager_service, secret_group_name)
    if secret_group_id is None:
        print(f"No secret group found with name {secret_group_name}")
        sys.exit(1)
    try:
        all_secrets = get_all_secrets(secrets_manager_service, secret_group_id)        
        if all_secrets:
            total_secrets = len(all_secrets)
            print(f"Found total {total_secrets} secrets in the secret group: {secret_group_name}")
            export_mend_secrets(secrets_manager_service, all_secrets, secret_group_name)
        else:
            print(f"No secrets found in the provided secret group {secret_group_name}")
            sys.exit(1)
    except Exception as e:
        print("Failed to list secrets: ", e)
        sys.exit(1)

def main():
    args = parse_args()        
    fetch_secrets_from_secret_group(
            args.secrets_manager_endpoint_url,
            args.cloud_apikey,
            args.secret_group_name,
        )
if __name__ == "__main__":
    main()
