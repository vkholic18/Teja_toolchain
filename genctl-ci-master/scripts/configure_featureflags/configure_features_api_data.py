"""
This script reads the api-spec-version from environment.yaml and pulls this specific version of
api-spec/features.yaml file and produces features-api-config for rias.
The configmap need to be uploaded in cos and then, deployed trough razee.
The config is used as input for internal features API.
"""

import argparse
import configure_featureflags, validate_schema
import yaml, github, os, sys
import logging
import json

rias_base_yaml_for_features_api = "base-features-api-config-rias.yaml"

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(os.path.basename(__file__))

def get_api_spec_release_version(environment_file: str) -> str:
    data = validate_schema.load_yaml_file(environment_file)
    if 'api_spec_version' in data['apps']['feature_flags']:
        release = data['apps']['feature_flags']['api_spec_version']
    else:
        logger.error(f"api_spec_version field is not found in {environment_file}.")
        sys.exit(1)
    return release

def export_configmap_data(json_str: str, genctl_ci_path: str):
    pwd = genctl_ci_path + "/scripts/configure_featureflags/"
    rias_config = configure_featureflags.build_config(json_str, pwd + rias_base_yaml_for_features_api, 2, 4)
    configure_featureflags.write_config(rias_config, pwd + rias_base_yaml_for_features_api.replace("base-", ""))

def get_json_config_data(raw_data) -> str:
    json_str = json.dumps(raw_data, indent=2)
    return json_str

def download_features_api_data_from_git(repo: str, filename: str, release_version: str) -> list:
    feature_list = []
    try:
        # Instantiate GitHub object
        gh = github.Github(
            login_or_token=os.environ['GHE_API_TOKEN'],
            base_url=os.environ['GHE_API_URL'])
        # Get the repository
        repo = gh.get_repo(repo)
        tags = repo.get_tags()
        for tag in tags:
            if tag.name == release_version:
                commit_sha = tag.commit.sha
                content = repo.get_contents(filename, ref=commit_sha)
                data = yaml.safe_load(content.decoded_content)
                feature_list = data['$features']
        return feature_list
    except Exception as exception:
        logger.error(exception)
        sys.exit(1)

# This function performs validation checks to identify drift between api-spec and feature-flags configuration
def validate_flags_spec_drift(feature_list, enabled_flags):
    vpc_flags = enabled_flags['apps']['feature_flags']['vpc']
    ignore_flags = ['is-snapshot-consistency-group', 'is-load-balancer-attach-to-load-balancer', 'is-load-balancer-reserved-ip-as-pool-member-target', 
                    'is-snapshot-dynamic-cos-allowlist', 'srb-3288-block-volume-metadata-pre-allocation-profile', 'is-subnet-reserved-ip-phase-2-internal-instance-floating-ips', 
                    'is-volume-cross-account-encryption-key', 'is-dynamic-route-server-phase-1', 'is-vpc-system-vpc']
    for feature in feature_list:
        feature_name = feature["name"]
        if feature_name in ignore_flags:
            continue
        maturity = feature.get("maturity")
        for vpc_flag in vpc_flags:
            if feature_name == vpc_flag["name"]:
                flag_name = vpc_flag["name"]
                maturity_default = None
                maturity_off_variation = None
                default_variation = vpc_flag['default'].get('variation_value', {})
                if isinstance(default_variation, dict):
                    maturity_default = default_variation.get('maturity', None)
                off_variation = vpc_flag.get('off_variation', {})
                if isinstance(off_variation, dict):
                    maturity_off_variation = off_variation.get('maturity', None)
                if maturity is not None and maturity_default is None and maturity_off_variation is None:
                    logger.error(f"'{flag_name}' is defined as Maturity flag in api-spec and is missing maturity in feature flag repository.")
                    sys.exit(1)
                if maturity is None and (maturity_default is not None or maturity_off_variation is not None):
                    logger.error(f"'{flag_name}' is defined as Boolean flag in api-spec but it is configured with a maturity value in feature flag repository")
                    sys.exit(1)

def main(environment_file, genctl_ci_path, path_to_api_spec_repo, path_to_features_api_data, featureflag_groups_path):
    release_version = get_api_spec_release_version(environment_file)
    if release_version is not None:
        logger.info(f'Proceeding to pull api spec release version {release_version}')
        feature_list = download_features_api_data_from_git(path_to_api_spec_repo, path_to_features_api_data, release_version)
        enabled_flags = configure_featureflags.combine_flags(environment_file, featureflag_groups_path)
        validate_flags_spec_drift(feature_list=feature_list, enabled_flags=enabled_flags)
        export_configmap_data(get_json_config_data(feature_list), genctl_ci_path)
    else:
        logger.error(f'api_spec_release version is not set, skipping upload features api data to cos')
        sys.exit(1)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-yaml-path", help="Path to the environment.yaml file",
                        default="workspace-repo/environment.yaml")
    parser.add_argument("--path-to-genctl-ci", help="Path to genctl-ci repo", default="genctl-ci-repo")
    parser.add_argument("--path-to-api-spec-repo", help="Path to api-spec repo", default="riaas/api-spec")
    parser.add_argument("--path-to-features-api-data", help="Path to features api data in api-spec repo", default="/spec/features.yaml")
    parser.add_argument("--service-flags-path", help="Path to the service flags directory",default="workspace-repo/service-flags/")
    args = parser.parse_args()
    main(args.env_yaml_path, args.path_to_genctl_ci, args.path_to_api_spec_repo, args.path_to_features_api_data, args.service_flags_path)
