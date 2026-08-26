import base64
import json
import argparse
import os
import yaml
import sys
import jsonschema
import logging
import configure_featureflags
from typing import Any
from collections import Counter

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(os.path.basename(__file__))


def load_yaml_file(file_path: str) -> Any:
    try:
        with open(file_path, 'r') as f:
            return yaml.load(f, Loader=yaml.SafeLoader)
    except FileNotFoundError:
        logger.error(f"File not found: {file_path}")
        sys.exit(1)
    except yaml.YAMLError as exc:
        logger.error(f"Error parsing YAML file: {exc}")
        sys.exit(1)


def check_unique_feature_flags(yaml_content):
    feature_flags = yaml_content.get("apps", {}).get("feature_flags", {}).get("vpc", [])
    names = [flag["name"] for flag in feature_flags]
    duplicates = [name for name, count in Counter(names).items() if count > 1]
    if duplicates:
        error_message = f"Duplicate feature flag names found: {', '.join(duplicates)}"
        logger.error(error_message)
        raise ValueError(error_message)


def yaml_schema_validator(ff_data: Any, description: str, validation_schema: json):
    try:
        jsonschema.validate(instance=ff_data, schema=validation_schema)
        print(f"Schema validation successful for {description}.")
    except jsonschema.exceptions.ValidationError as e:
        raise jsonschema.exceptions.ValidationError(
            f"Schema validation failed for {description} with an error: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-yaml-path", help="Path to the environment.yaml file",
                        default="workspace-repo/environment.yaml")
    parser.add_argument("--path-to-genctl-ci", help="Path to genctl-ci repo", default="genctl-ci-repo")
    parser.add_argument("--service-flags-path", help="Path to the service flags directory",
                        default="workspace-repo/service-flags/")
    args = parser.parse_args()

    # Validate the environment yaml file
    schema_path = args.path_to_genctl_ci + "/scripts/configure_featureflags/schema.yaml"
    with open(schema_path, "r") as file:
        env_yaml_schema = yaml.load(file, Loader=yaml.SafeLoader)

    all_yaml_paths = [args.env_yaml_path]
    if os.path.isdir(args.service_flags_path) and os.listdir(args.service_flags_path):
        filenames = os.listdir(args.service_flags_path)
        for filename in filenames:
            file_path = args.service_flags_path + filename
            all_yaml_paths.append(file_path)

    for path in all_yaml_paths:
        yaml_schema_validator(load_yaml_file(path), path, env_yaml_schema)

    print(f"Schema validation successful for individual yaml files.")

    combined_data = configure_featureflags.combine_flags(args.env_yaml_path, args.service_flags_path)
    yaml_schema_validator(combined_data, "combined FF data", env_yaml_schema)
    check_unique_feature_flags(combined_data)
    print(f"Schema validation successfully completed.")
