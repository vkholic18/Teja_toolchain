# This function is designed to backup secrets between secret managers
# usage example:
# python3 scripts/backup_sm/backup_sm.py -se "https://xxxx.eu-gb.secrets-manager.appdomain.cloud" -ck "<cloud-key>" -de "https://XXXXX.other-region.secrets-manager.appdomain.cloud"
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
        description='Backup a secret from one IBM Secrets Manager instance to another.')
    parser.add_argument('-se', '--src-secrets-manager-endpoint-url', type=str,
                        help='URL of the source Secrets Manager endpoint instance', required=True)
    parser.add_argument('-ck', '--cloud-apikey', type=str,
                        help='API key for the source Secrets Manager instance', required=True)
    parser.add_argument('-de', '--dest-secrets-manager-endpoint-url', type=str,
                        help='URL of the destination Secrets Manager endpoint instance', required=True)
    parser.add_argument('--auto-approve', required=False, action='store_true',
                        help='auto approve and run the scripts, without interactive interference')
    args = parser.parse_args()
    return args


def get_sm_service(sm_endpoint_url, sm_api_key):
    """Initiating the SecretManager service

    Args:
        sm_endpoint_url (string): public endpoint of the SM
        sm_api_key (string): cloud api key

    Returns:
        object: SM tyoe
    """
    # Authenticate to IBM Secret Manager
    authenticator = IAMAuthenticator(apikey=sm_api_key)
    secrets_manager_service = SecretsManagerV2(
        authenticator=authenticator)
    secrets_manager_service.set_service_url(sm_endpoint_url)
    return secrets_manager_service


def get_all_secrets(sm_client, groups):
    """gets all secrets from a given sm client

    Args:
        sm_client (SecretsManagerV2): sm client object

    Returns:
        dic: json formatted secret results
    """
    all_results = []
    pager = SecretsPager(
        client=sm_client,
        limit=1000,
        sort='created_at',
        groups=groups
    )
    while pager.has_next():
        next_page = pager.get_next()
        assert next_page is not None
        all_results.extend(next_page)
    return json.loads(json.dumps(all_results, indent=2))

def list_secret_groups(sm_service):
    data=sm_service.list_secret_groups()
    if data is not None:
        return data.get_result()["secret_groups"]
    return None

def create_secret_group_in_dest(dest_sm_service, sg_name, sg_description):
    print(f"Creating a secret group with name: {sg_name}")
    response=dest_sm_service.create_secret_group(name=sg_name, description=sg_description)
    if response.get_result() is not None:
        print(f"Secret Group with name {sg_name} created successfully in destination secrets manager")
        return response.get_result()["id"]
    else:
        return 1
    
def fetch_secret_group_ids(source_sm_service, dest_sm_service):
    all_sg_data = []    
    source_sg_list=list_secret_groups(source_sm_service)
    dest_sg_list=list_secret_groups(dest_sm_service)
    if source_sg_list is not None and dest_sg_list is not None:
        for i in source_sg_list:
            source_sg_name=i["name"]
            source_sg_description=i["description"]
            source_sg_id=i["id"]
            sg_data=dict()
            found=0
            for j in dest_sg_list:
                if j["name"] == source_sg_name:
                    found=1
                    break
            if found==1:
                print(f"Secret Group: {source_sg_name} found in destination secrets manager")
                sg_data["sg_name"]=source_sg_name
                sg_data["source_sg_id"]=source_sg_id
                sg_data["dest_sg_id"]=j["id"]
                all_sg_data.append(sg_data)
            else:
                response=create_secret_group_in_dest(dest_sm_service, source_sg_name, source_sg_description)
                if response == 1:
                    print(f"Failed to create a secret group with name {source_sg_name}")        
                else:
                    sg_data["sg_name"]=source_sg_name
                    sg_data["source_sg_id"]=source_sg_id
                    sg_data["dest_sg_id"]=j["id"]
                    all_sg_data.append(sg_data)        
        return all_sg_data    
    return None

def backup_secrets(src_secrets_manager_endpoint_url, cloud_apikey, dest_secrets_manager_endpoint_url):
    """_summary_

    Args:
        src_secrets_manager_endpoint_url (string): secret manager source public endpoint
        cloud_apikey (string): cloud apikey
        dest_secrets_manager_endpoint_url (string): secret manager destination public endpoint

    Returns:
        list, list: list of new secrets, list of updated secrets
    """
    updated_secrets = list()
    new_secrets = list()
    recreated_secrets = list()
    list_of_destroyed_secrets = list()
    # Get secrets from source IBM Secret Manager
    print("init secrets manager")
    source_secrets_manager_service = get_sm_service(
        src_secrets_manager_endpoint_url, cloud_apikey)
    dest_secret_manager_service = get_sm_service(
        dest_secrets_manager_endpoint_url, cloud_apikey)
    source_secrets = None
    response=fetch_secret_group_ids(source_secrets_manager_service, dest_secret_manager_service)
    if response is not None:                         
        for sg in response:
            sg_name = sg["sg_name"]
            source_secret_group_id = sg["source_sg_id"]
            dest_secets_group_id = sg["dest_sg_id"]            
            source_group_list = []
            dest_group_list = []
            source_group_list.append(source_secret_group_id)
            dest_group_list.append(dest_secets_group_id)
            print(f"\nCopying the secrets from the Source Secret Group: {sg_name}")
            print(f"********************************************************************************")
            try:
                source_secrets = get_all_secrets(source_secrets_manager_service, source_group_list)
                dest_secrets = get_all_secrets(dest_secret_manager_service, dest_group_list)
            except Exception as e:
                print("Failed to list secrets: ", e)
                sys.exit(1)    
            # Copy secrets to destination IBM Secret Manager
            if source_secrets:
                for secret in source_secrets:
                    secret_name = secret["name"]
                    secret_id = secret["id"]
                    # Get the secret from the source Secret Manager
                    try:
                        source_secret = source_secrets_manager_service.get_secret(
                            id=secret_id
                        ).get_result()
                    except Exception as e:
                        print(f"Failed to get secret {secret_name}: ", e)
                        sys.exit(1)
                    if source_secret["state_description"] == "active":
                        secret_type = source_secret["secret_type"]

                        # private_cert requires the same PKI certificate template to exist in the
                        # destination SM — skip with a warning if it may not be present.
                        if secret_type == "private_cert":
                            print(f"skipping {secret_name} (type=private_cert): certificate template '{source_secret.get('certificate_template')}' must be pre-configured in the destination SM")
                            continue

                        # DEBUG: print full API response for username_password to understand available fields
                        if secret_type == "username_password":
                            print(f"\n[DEBUG] Full get_secret response for {secret_name} (type=username_password):")
                            print(json.dumps(source_secret, indent=2, default=str))
                            print("[DEBUG END]\n")
                            continue

                        # ----------------------------------------------------------------
                        # Build the create prototype based on secret type
                        # ----------------------------------------------------------------
                        if secret_type == "kv":
                            secret_resource_model = {
                                "name": secret_name,
                                "secret_type": secret_type,
                                **({"description": source_secret["description"]} if "description" in source_secret else {}),
                                "labels": source_secret["labels"],
                                "secret_group_id": dest_secets_group_id,
                                **({"expiration_date": source_secret["expiration_date"]} if "expiration_date" in source_secret else {}),
                                **({'data': source_secret["data"]} if "data" in source_secret else {})
                            }
                        elif secret_type == "private_cert":
                            # private_cert is re-issued by the destination PKI engine using the
                            # same certificate_template and parameters — cert material is not copied.
                            secret_resource_model = {
                                "name": secret_name,
                                "secret_type": secret_type,
                                **({"description": source_secret["description"]} if "description" in source_secret else {}),
                                "labels": source_secret["labels"],
                                "secret_group_id": dest_secets_group_id,
                                "certificate_template": source_secret["certificate_template"],
                                "common_name": source_secret["common_name"],
                                **({"alt_names": source_secret["alt_names"]} if source_secret.get("alt_names") else {}),
                                **({"rotation": source_secret["rotation"]} if "rotation" in source_secret else {}),
                            }
                        elif secret_type == "imported_cert":
                            # imported_cert: expiration_date is embedded in the cert — do not pass it.
                            secret_resource_model = {
                                "name": secret_name,
                                "secret_type": secret_type,
                                **({"description": source_secret["description"]} if "description" in source_secret else {}),
                                "labels": source_secret["labels"],
                                "secret_group_id": dest_secets_group_id,
                                **({"certificate": source_secret["certificate"]} if "certificate" in source_secret else {}),
                                **({"private_key": source_secret["private_key"]} if "private_key" in source_secret else {}),
                                **({"intermediate": source_secret["intermediate"]} if "intermediate" in source_secret else {}),
                            }
                        else:
                            # arbitrary / username_password and any other types
                            secret_resource_model = {
                                "name": secret_name,
                                "secret_type": secret_type,
                                **({"description": source_secret["description"]} if "description" in source_secret else {}),
                                "labels": source_secret["labels"],
                                "secret_group_id": dest_secets_group_id,
                                **({"expiration_date": source_secret["expiration_date"]} if "expiration_date" in source_secret else {}),
                                **({'payload': source_secret["payload"]} if "payload" in source_secret else {})
                            }

                        secret_metadata_patch_model = {
                            "name": secret_name,
                            **({"description": source_secret["description"]} if "description" in source_secret else {}),
                            "labels": source_secret["labels"],
                            # expiration_date is not patchable on cert types
                            **({"expiration_date": source_secret["expiration_date"]} if "expiration_date" in source_secret and secret_type not in ("private_cert", "imported_cert", "public_cert") else {}),
                        }

                        found = False
                        try:
                            if dest_secrets:
                                for dest_secret in dest_secrets:
                                    if dest_secret["name"] == secret_name:
                                        print(f"found secret {secret_name}, checking the state and upload revision of the secret...")
                                        try:
                                            dest_secret_data = dest_secret_manager_service.get_secret(
                                                id=dest_secret["id"]
                                            ).get_result()
                                        except Exception as e:
                                            print(f"Failed to get secret {secret_name}: ", e)
                                            sys.exit(1)
                                        if dest_secret_data["state_description"] == "destroyed":
                                            print(f"secret {secret_name} got destroyed... so deleting and re-creating the secret...")
                                            try:
                                                dest_secret_manager_service.delete_secret(
                                                    id=dest_secret["id"]
                                                )
                                                recreated_secrets.append(secret_name)
                                                dest_secret_manager_service.create_secret(secret_prototype=secret_resource_model)
                                                print(f"Successfully deleted and re-created the secret {secret_name}")
                                                break
                                            except Exception as e:
                                                print(f"Failed to delete and re-create the secret - {secret_name}: ", e)
                                                sys.exit(1)
                                        if secret_type == "kv":
                                            if dest_secret_data["data"] != source_secret["data"]:
                                                print(f"found data variation in secret {secret_name}, updating secret...")
                                                updated_secrets.append(secret_name)
                                                found = True
                                                dest_secret_manager_service.update_secret_metadata(
                                                    id=dest_secret["id"],
                                                    secret_metadata_patch=secret_metadata_patch_model)
                                                dest_secret_manager_service.create_secret_version(
                                                    secret_id=dest_secret["id"],
                                                    secret_version_prototype={'data': source_secret["data"]}
                                                ).get_result()
                                                break
                                            else:
                                                found = True
                                                print(f"secret {secret_name} payload is unchanged.")
                                        elif secret_type == "private_cert":
                                            # Compare serial numbers — if different the cert was rotated
                                            # in source and needs to be re-issued in destination too.
                                            if dest_secret_data.get("serial_number") != source_secret.get("serial_number"):
                                                print(f"found certificate variation in secret {secret_name} (serial mismatch), rotating secret...")
                                                updated_secrets.append(secret_name)
                                                found = True
                                                dest_secret_manager_service.update_secret_metadata(
                                                    id=dest_secret["id"],
                                                    secret_metadata_patch=secret_metadata_patch_model)
                                                dest_secret_manager_service.create_secret_version(
                                                    secret_id=dest_secret["id"],
                                                    secret_version_prototype={"secret_type": "private_cert"}
                                                ).get_result()
                                                break
                                            else:
                                                found = True
                                                print(f"secret {secret_name} certificate is unchanged.")
                                        elif secret_type == "imported_cert":
                                            # Compare serial numbers for imported certs too
                                            if dest_secret_data.get("serial_number") != source_secret.get("serial_number"):
                                                print(f"found certificate variation in secret {secret_name} (serial mismatch), updating secret...")
                                                updated_secrets.append(secret_name)
                                                found = True
                                                dest_secret_manager_service.update_secret_metadata(
                                                    id=dest_secret["id"],
                                                    secret_metadata_patch=secret_metadata_patch_model)
                                                dest_secret_manager_service.create_secret_version(
                                                    secret_id=dest_secret["id"],
                                                    secret_version_prototype={
                                                        "secret_type": "imported_cert",
                                                        **({"certificate": source_secret["certificate"]} if "certificate" in source_secret else {}),
                                                        **({"private_key": source_secret["private_key"]} if "private_key" in source_secret else {}),
                                                        **({"intermediate": source_secret["intermediate"]} if "intermediate" in source_secret else {}),
                                                    }
                                                ).get_result()
                                                break
                                            else:
                                                found = True
                                                print(f"secret {secret_name} certificate is unchanged.")
                                        else:
                                            if dest_secret_data.get("payload") != source_secret.get("payload"):
                                                print(f"found payload variation in secret {secret_name}, updating secret...")
                                                updated_secrets.append(secret_name)
                                                found = True
                                                dest_secret_manager_service.update_secret_metadata(
                                                    id=dest_secret["id"],
                                                    secret_metadata_patch=secret_metadata_patch_model)
                                                dest_secret_manager_service.create_secret_version(
                                                    secret_id=dest_secret["id"],
                                                    secret_version_prototype={'payload': source_secret["payload"]}
                                                ).get_result()
                                                break
                                            else:
                                                found = True
                                                print(f"secret {secret_name} payload is unchanged.")
                            else:
                                found = False
                            if not found:
                                print(f"did not find secret {secret_name}, creating new secret in destination")
                                new_secrets.append(secret_name)
                                try:
                                    dest_secret_manager_service.create_secret(
                                        secret_prototype=secret_resource_model)
                                except Exception as create_err:
                                    err_str = str(create_err)
                                    if "secrets-manager.05047E" in err_str or "same name already exists" in err_str:
                                        # Secret exists in a different group in destination — source is truth,
                                        # so find it destination-wide, delete it and recreate in the correct group.
                                        print(f"409 conflict: secret {secret_name} exists in a different group in destination, relocating...")
                                        try:
                                            conflict_pager = SecretsPager(client=dest_secret_manager_service, limit=1000)
                                            all_dest = []
                                            while conflict_pager.has_next():
                                                all_dest.extend(conflict_pager.get_next())
                                            conflict = next((s for s in all_dest if s["name"] == secret_name), None)
                                            if conflict:
                                                dest_secret_manager_service.delete_secret(id=conflict["id"])
                                                print(f"deleted stale copy of {secret_name} from group {conflict['secret_group_id']}")
                                            dest_secret_manager_service.create_secret(secret_prototype=secret_resource_model)
                                            print(f"recreated {secret_name} in correct group {dest_secets_group_id}")
                                        except Exception as relocate_err:
                                            print(secret_resource_model)
                                            print(f"Failed to relocate secret {secret_name}: ", relocate_err)
                                            sys.exit(1)
                                    else:
                                        print(secret_resource_model)
                                        print(f"Failed to create secret {secret_name}: ", create_err)
                                        sys.exit(1)
                        except Exception as e:
                            print(secret_resource_model)
                            print(f"Failed to create secret {secret_name}: ", e)
                            sys.exit(1)
                    else:
                        list_of_destroyed_secrets.append(secret_name)
        return updated_secrets, new_secrets, recreated_secrets, list_of_destroyed_secrets


def print_result(updated_secrets, new_secrets, recreated_secrets, list_of_destroyed_secrets):
    """
    prints the result of the script
    """
    formatted_new_secrets = f"\n".join(new_secrets)
    formatted_updated_secrets = f"\n".join(updated_secrets)
    formatted_destroyed_secrets = f"\n".join(recreated_secrets)
    formatted_list_of_destroyed_secrets = f"\n".join(list_of_destroyed_secrets)
    print(f"#### Created {len(new_secrets)} new secrets ####\n{formatted_new_secrets}\n#### Updated {len(updated_secrets)} existed secrets ####\n{formatted_updated_secrets}\n#### Re-created {len(recreated_secrets)} destroyed secrets ####\n{formatted_destroyed_secrets}\n#### Found {len(list_of_destroyed_secrets)} destroyed secrets from the source ####\n{formatted_list_of_destroyed_secrets}")

def main():
    args = parse_args()
    if args.src_secrets_manager_endpoint_url == args.dest_secrets_manager_endpoint_url:
        print("Source and destination endpoints must be different!")
        sys.exit(1)
    if args.auto_approve:
        updated_secrets, new_secrets, recreated_secrets, list_of_destroyed_secrets = backup_secrets(
            args.src_secrets_manager_endpoint_url,
            args.cloud_apikey,
            args.dest_secrets_manager_endpoint_url,
        )
        print_result(updated_secrets, new_secrets, recreated_secrets, list_of_destroyed_secrets)
    else:
        masked_key = f"{'*' * (len(args.cloud_apikey) - 4)}{args.cloud_apikey[-4:]}"
        user_input = input(
            f"You are about to run the secret manager backup script\nusing key: {masked_key}\nsource url is: {args.src_secrets_manager_endpoint_url}\ndestination url is: {args.dest_secrets_manager_endpoint_url}\nare you sure [Y/n]?")
        if user_input.lower() == 'y':
            updated_secrets, new_secrets, recreated_secrets, list_of_destroyed_secrets = backup_secrets(
                args.src_secrets_manager_endpoint_url,
                args.cloud_apikey,
                args.dest_secrets_manager_endpoint_url,
            )
            print_result(updated_secrets, new_secrets, recreated_secrets, list_of_destroyed_secrets)


if __name__ == "__main__":
    main()
