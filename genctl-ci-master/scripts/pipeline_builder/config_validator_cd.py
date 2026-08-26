# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#   Validator for pipeline configuration file
#   See pipeline.yaml.sample for configuration examples
#
# Use:
#   python3 config_validator.py <path to config>
#

import yaml
import re
import sys
import logging

#General acceptable values
pipe_types = ['pr', 'merge']
statuses = ['start', 'success', 'failure', 'abort']

#Notifcation config acceptable values
recipient_types = ['author', 'w3ids', 'channels']

#Build env acceptable values
params = ['image', 'tag','customtag','ignoremultiarch']

#Deployment env acceptable values
deployment_params = ['rule_tag', 'feature_flag', 'iks_cluster_name', 'mzone_name', 'api_key_alias']

#Functional tests acceptable values
repos = ['local_repo', 'integration_testing_repo']

_cvERRORS = { 'invalid_yaml' : "ERROR: pipeline yaml appears to be empty/invalid" }

def validate_notif_conf(conf):
    """
    Parses notification config dictionary and validates keys and value types
    Args:
        config: dictionary containing the notification config
    Raises:
        SystemExit: if configuration is invalid
    """
    for status, configs in conf.items():
        if status not in statuses:
            raise SystemExit(
                "ERROR: Unexpected status type: {}".format(status)
            )

        for recipient_type, recipient in configs.items():
            if recipient_type not in recipient_types:
                raise SystemExit(
                    "ERROR: Unexpected notification recipient type: {}".\
                        format(recipient_type)
                )

            if recipient_type == 'author':
                if not isinstance(recipient, bool):
                    raise SystemExit(
                        "ERROR: Boolean value expected for author key"
                    )

            if recipient_type == 'channels':
                if not isinstance(recipient, list):
                    raise SystemExit(
                        "ERROR: List value expected for channels key")

            if recipient_type == 'w3ids':
                if not isinstance(recipient, list):
                    raise SystemExit(
                        "ERROR: List value expected for w3ids key")

                pattern = re.compile(r'^.*@.*ibm\.com$')
                for w3id in recipient:
                    if not pattern.match(w3id):
                        raise SystemExit(
                            "ERROR: Invalid w3 id {}".format(w3id))

def validate_environment_conf(conf):
    """
    Parses environment config dictionary and validates keys and value types
    Args:
        config: dictionary containing the environment config
    Raises:
        SystemExit: if configuration is invalid
    """
    if 'customtag' not in conf.keys():
        if 'tag' not in conf.keys():
            raise SystemExit(
                "ERROR: {} required for env config".format('tag')
            )


    for param, value in conf.items():
        if param not in params:
            print(
                "WARNING: Unexpected build env param: {}".format(param)
            )

def validate_deployment_conf(conf):
    """
    Parses environment config dictionary and validates keys and value types
    Args:
        config: dictionary containing the environment deployment
    Raises:
        SystemExit: if configuration is invalid
    """
    if 'feature_flag' not in conf.keys():
        raise SystemExit(
            "ERROR: {} required for env config".format('feature_flag')
        )

    for param, value in conf.items():
        if param not in deployment_params:
            print(
                "WARNING: Unexpected deployment env param: {}".format(param)
            )

def validate_funct_tests_conf(conf):
    """
    Parses functional_test config dictionary and validates keys and value types
    Args:
        config: dictionary containing the functional_tests config
    Raises:
        SystemExit: if configuration is invalid
    """
    for framework, framework_config in conf.items():
        if framework == 'cpap':
            for repo, repo_config in framework_config.items():
                if repo not in repos:
                    raise SystemExit(
                        "ERROR: Unexpected repo, {}".format(repo)
                    )

                if repo != 'local_repo' and 'test_dir' in repo_config.keys():
                    raise SystemExit(
                        "ERROR: test_dir config only allowed in local_repo"
                    )

                for test_key, test_config in repo_config.items():
                    if test_key == 'test_dir':
                        if not isinstance(test_config, str):
                            raise SystemExit(
                                "ERROR: Str value expected for test_dir"
                            )

                    elif test_key == 'test_configs':
                        if not isinstance(test_config, list):
                            raise SystemExit(
                                "ERROR: List value expected for test_configs"
                            )

                    else:
                        print(
                            "WARNING: Unexpected test key, {}".format(test_key)
                        )

        else:
            print(
                "WARNING: Unexpected testing framework, {}".format(framework)
            )
def validate_feature_flags_conf(conf):
 
    for config, ff_config in conf.items():
        print(config) # vpc-ci
        for ff in ff_config:
            validate_funct_tests_conf(ff["functional_tests"])



def validate(config_path):
    """
    Loads pipeline config yaml file as a dictionary and
    validates keys and value types
    Args:
        config_path: path to the pipeline config yaml file
    Raises:
        SystemExit: if configuration is invalid
    """
    with open(config_path, 'r') as stream:
        cd = yaml.safe_load(stream)

    if not isinstance(cd, dict):
        raise SystemExit(f"{_cvERRORS['invalid_yaml']} : {config_path}")

    logger = logging.getLogger()
    logger.info(f"Parsing cd {cd}")
    for config_type, conf in cd.items():
        print("cd config_type: " + config_type)
        if config_type in pipe_types:
            for sub_type, sub_conf in conf.items():
                if sub_type == 'notification':
                    validate_notif_conf(sub_conf)
                elif sub_type == 'check_commits':
                    print("sub_type ok but not checked: {}". format(sub_type))
                else:
                    raise SystemExit(
                        "ERROR: Unexpected config type: {}".format(sub_type)
                    )

        elif config_type == 'environment':
            validate_environment_conf(conf)

        elif config_type == 'deployment':
            validate_deployment_conf(conf)

        elif config_type == 'functional_tests':
            validate_funct_tests_conf(conf)

        elif config_type == 'feature_flags':
            validate_feature_flags_conf(conf)

        else:
            print(
                "WARNING: Unexpected config type: {}".format(config_type)
            )

def main():
    """
    Checks if path to configuration file was passed and calls validate function
    Raises:
        SystemExit: if configuration file path not passed in from command line
    """
    try:
        config_path = sys.argv[1]
    except IndexError:
        raise SystemExit("ERROR: Path to config file not specified")

    validate(config_path)
    print("Configuration is valid!")

if __name__ == "__main__":
    main()