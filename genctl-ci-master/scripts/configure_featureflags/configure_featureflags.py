"""
This script loads featureflags from the environment.yaml file as well as service specific flags
located at service-flags  directory and creates featureflags configmap yamls for rias and genctl.
The config yamls need to be uploaded in COS and then, deployed through razee.
"""

import argparse
import json
import os
import sys
import yaml
import logging
from typing import Any
import validate_data

rias_base_yaml = "base-featureflags-config-rias.yaml"
base_yaml = "base-featureflags-config.yaml"
genctl_base_yaml = "base-featureflags-config-genctl.yaml"
rias_base_ns_yaml = "featureflags-config-{}-ns.yaml"
namespaces = ["rias", "riaasiam", "riaasstorage", "ops", "rias-etcd"]

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(os.path.basename(__file__))


def load_yaml_file(file_path: str) -> Any:
    try:
        with open(file_path, 'r') as f:
            data = yaml.load(f, Loader=yaml.SafeLoader)
    except FileNotFoundError:
        logger.error("failed to load ", file_path)
        sys.exit(1)
    return data


def get_json_config(raw_data) -> str:
    vpc_data = raw_data['apps']['feature_flags']['vpc']
    json_str = json.dumps(vpc_data, indent=2)
    return json_str


def combine_flags(env_yaml, service_flags_path):

    logger.info(f'combining featureflags from {env_yaml} with feature flags files under {service_flags_path} directory')

    env_data = load_yaml_file(env_yaml)
    if os.path.isdir(service_flags_path) and os.listdir(service_flags_path):
        filenames = os.listdir(service_flags_path)
        service_flags = []
        for filename in filenames:
            filepath = service_flags_path + filename
            logger.info(f'reading in featureflags service file: {filepath} ')
            file_flag_data = load_yaml_file(filepath)
            service_flags.extend(file_flag_data['apps']['feature_flags']['vpc'])

        env_data['apps']['feature_flags']['vpc'].extend(service_flags)

    return env_data


def build_config(json_str: str, file_path: str, indent, block_indent) -> str:
    """
    :param indent: defines the indentation for the yaml file.
    :param block_indent: defines the block indentation based on the indentation for the `data` field of default yaml
    """
    config = adjust_indentation(json_str, indent, block_indent)
    with open(file_path, "r") as yaml_file:
        default_yaml = yaml_file.read()
    return default_yaml + "\n" + config


def validate_configmap_size(file_path):
    """
    Double-checking if the size of the configmaps don't exceed the limit, similar
    check exists for the yaml files
    """
    if not os.path.isfile(file_path):
        raise FileNotFoundError(f"no file found at {file_path}")
    if os.path.getsize(file_path) == 0:
        raise ValueError(f"the file is empty")
    file_size_kb = os.path.getsize(file_path) / 1024
    if file_size_kb > validate_data.max_size_kb:
        raise ValueError(
            f'{file_path} is of size {file_size_kb} KB and exceeds the maximum file size limit of {validate_data.max_size_kb} KB.')
    logger.info(f'size of {file_path} is valid')


def write_config(configmap, export_path: str) -> None:
    if os.path.exists(export_path):
        os.remove(export_path)
    with open(export_path, 'w') as configmap_yaml:
        configmap_yaml.write(configmap)

    validate_configmap_size(export_path)
    logger.info(f'successfully exported feature flags\' configmap to {export_path}')


def export_configmap(json_str: str, genctl_ci_path: str):
    pwd = genctl_ci_path + "/scripts/configure_featureflags/"
    rias_config = build_config(json_str, pwd + rias_base_yaml, 2, 10) + "\n    {{/each}}"
    genctl_config = build_config(json_str, pwd + genctl_base_yaml, 2, 4)
    write_config(rias_config, pwd + rias_base_yaml.replace("base-", ""))
    write_config(genctl_config, pwd + genctl_base_yaml.replace("base-", ""))
    
    #Separating each namespace
    rias_yamls_full_path =  pwd + rias_base_ns_yaml
    rias_base_path = pwd + base_yaml
    
    rias_config = build_config(json_str, rias_base_path, 2, 4)

    for namespace in namespaces:
        data = rias_config.replace("namespace:", "namespace: " + namespace)
        write_config(data, rias_yamls_full_path.format(namespace))


def adjust_indentation(json_str: str, indent, block_indent):
    indented_json = json.dumps(json.loads(json_str), indent=indent)
    indented_lines = "\n".join(spaces(block_indent) + line for line in indented_json.split("\n"))
    return indented_lines


def spaces(num_spaces):
    return " " * num_spaces


def main(env_yaml, genctl_ci_path, featureflag_groups_path):
    config_data = combine_flags(env_yaml, featureflag_groups_path)
    export_configmap(get_json_config(config_data), genctl_ci_path)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-yaml-path", help="Path to the environment.yaml file",
                        default="workspace-repo/environment.yaml")
    parser.add_argument("--path-to-genctl-ci", help="Path to genctl-ci repo", default="genctl-ci-repo")
    parser.add_argument("--service-flags-path", help="Path to the service flags directory",
                        default="workspace-repo/service-flags/")
    args = parser.parse_args()
    main(args.env_yaml_path, args.path_to_genctl_ci, args.service_flags_path)
