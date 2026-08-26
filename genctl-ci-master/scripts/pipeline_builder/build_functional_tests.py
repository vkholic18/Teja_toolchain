# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020,2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Parses functional_tests config and outputs test runs to iterate in
#    smotainer
#
# Env:
#    GLOBAL_TEST_CONFIG: path to the test config that runs on all pipelines
#    GLOBAL_META_PURPOSE: meta purpose filter string for global test config
#    OUTPUT: path to the output json file
#    WS_PATH: path to the github repository or workspace
#
# Use:
#    python3 build_functional_tests.py
#

import configparser
import json
import logging
import os
import argparse
from pipeline_config import PipelineConfig

# Constants
CPAP_TEST_FILE_EXTS = ['.py', '.go']
GENERATED_CPAP_CONF_FILE = 'ci_generated_tests.ini'
defaultProcessCount = 4

def setup_logger():
    """
    Configures logger and formatting
    Returns:
        logger: logger object
    """

    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

def set_parser():
    """
    Parse the arguments passed when calling this file.
    Returns:
        parser (parser object)
    """
    parser = argparse.ArgumentParser(
        description='Determine if smoke test should be skipped.')
    parser.add_argument('-s', '--skip-smoke', action="store_true",
                        help='Switch flag to determine if smoke tests should be skipped')
    return parser.parse_args()

def format_test_execution(config_path, meta_purposes, meta_environment, cmdline, cmdlineraw, iks_cluster_name_override, meta_features, jira_project, api_key_alias, test_plan, processes, endpoint_type, skip_test=False):
    """
    Formats config path and meta_purpose for json output
    Args:
        config_path: path to the test config file
        meta_purpose: list of meta purpose filter strings
    Returns:
        formatted dictionary
    """
    return {
        "path": config_path,
        "meta_purposes": meta_purposes,
        "meta_environment": meta_environment,
        "cmdline": cmdline,
        "cmdlineraw": cmdlineraw,
        "iks_cluster_name_override": iks_cluster_name_override,
        "meta_features": meta_features,
        "jira_project": jira_project,
        "api_key_alias": api_key_alias,
        "test_plan": test_plan,
        "processes": processes,
        "endpoint_type": endpoint_type,
        "skip_test": skip_test
    }

def should_execute_test(test_run_tracker, config_path, meta_purposes, cmdline, cmdlineraw):
    """
    Checks if a test has been previously executed by keeping track of config path and meta_purpose
    Args:
        test_run_tracker: dict of config paths and related meta purpose strings
        config_path: path to the test config file
        meta_purpose: list of meta purpose filter strings
        cmdline: 
        cmdlineraw:
    Returns
        Bool: True or False
    """
    skip_test = False
    skip_mp_test = False
    skip_cmd_test = False
    skip_clr_test = False

    if config_path in test_run_tracker:
        if meta_purposes:
            for m in meta_purposes:
                if m in test_run_tracker[config_path]["meta_purposes"]:
                    skip_mp_test = True
                    skip_test = True
                test_run_tracker[config_path]["meta_purposes"].append(m)
        if cmdline:
            for c in cmdline:
                if c in test_run_tracker[config_path]["cmdline"]:
                    skip_cmd_test = True
                    skip_test = True
                else:
                    skip_cmd_test = False
                    skip_test = False
                    break
            test_run_tracker[config_path]["cmdline"].append(c)
        if cmdlineraw:
            if cmdlineraw == test_run_tracker[config_path]["cmdlineraw"]:
                    skip_clr_test = True
                    skip_test = True
            test_run_tracker[config_path]["cmdlineraw"].append(cmdlineraw)

        if (not meta_purposes) and (not cmdline) and (not cmdlineraw):
            skip_test = True
    else:
        mp = meta_purposes.copy()
        cmd = cmdline.copy()
        clr = cmdlineraw.copy()
        test_run_tracker[config_path] = { "meta_purposes": mp,  "cmdline": cmd, "cmdlineraw": clr}

        skip_test = False

    # override if one of the parameters were passed in and not detected. 
    if (not skip_mp_test and meta_purposes) or (not skip_cmd_test and cmdline) or (not skip_clr_test and cmdlineraw):
        skip_test = False
    
    return skip_test


def build_test_executions(configs, test_run_tracker, repo_path=""):
    """
    Loops through test configurations and formats configuration to list
    Args:
        configs: list of test configurations
        repo_path: Path to the repo containing tests
    Returns:
        List of test runs with formatted configuration
    """
    executions = list()
    skip_test = False

    for config in configs:
        config_path = os.path.join(repo_path, config['path'])
        if "meta_purposes" not in config:
            config['meta_purposes'] = []
        if "meta_environment" not in config:
            config['meta_environment'] = []
        if "cmdline" not in config:
            config['cmdline'] = []
        if "cmdlineraw" not in config:
            config['cmdlineraw'] = []
        else:
            config['cmdlineraw'] = config['cmdlineraw'].split(' ')
        if "iks_cluster_name_override" not in config:
            config['iks_cluster_name_override'] = []
        if "meta_features" not in config:
            config['meta_features'] = []
        if "jira_project" not in config:
            config['jira_project'] = []
        if "api_key_alias" not in config:
            config['api_key_alias'] = []
        if "test_plan" not in config:
            config['test_plan'] = []
        if "processes" not in config:
            # default to 4
            config['processes'] = defaultProcessCount
        if test_run_tracker != None:
            skip_test = should_execute_test(test_run_tracker, config_path, config['meta_purposes'], config['cmdline'], config['cmdlineraw'])
        if "endpoint_type" not in config:
            config['endpoint_type'] = "public"
            
        executions.append(format_test_execution(config_path, config['meta_purposes'], config['meta_environment'], config['cmdline'], config['cmdlineraw'], config['iks_cluster_name_override'], config['meta_features'], config['jira_project'], config['api_key_alias'], config['test_plan'], config['processes'], config['endpoint_type'], skip_test))

    return executions

def build_cpap_suite(cpap_test_dir, ws_path):
    """
    Parses given cpap test dir and writes test suite ini with all tests
    Args:
        cpap_test_dir: the dir to search through for test files
        ws_path: the path to the workspace on disk
        file_name: the output file name of the test suite ini
    """
    logger = logging.getLogger()

    if cpap_test_dir:
        logger.info("Building cpap test ini file")

        cpap_test_dir_path = os.path.join(ws_path, cpap_test_dir)
        if os.path.exists(cpap_test_dir_path):
            logger.info(f"Parsing {cpap_test_dir} for tests")

            tests = list()
            for file_name in os.listdir(cpap_test_dir_path):
                if os.path.splitext(file_name)[-1] in CPAP_TEST_FILE_EXTS:
                    tests.append(os.path.join(cpap_test_dir_path, file_name))

            if tests:
                test_config = configparser.ConfigParser()
                test_config['nosetests'] = {
                    'tests': ', '.join(tests)
                }

                ini_file_path = os.path.join(ws_path, GENERATED_CPAP_CONF_FILE)
                with open(ini_file_path, 'w+') as f:
                    test_config.write(f)

                return format_test_execution(ini_file_path, [], [], [], [], [], [], [], [], [], [], defaultProcessCount)

            else:
                logger.warning("No tests found in the " +\
                    f"configured cpap_test_dir, {cpap_test_dir_path}")
                return None
        else:
            logger.warning("The configured cpap_test_dir, " +\
                f"{cpap_test_dir_path} does not exist")
            return None

def parse_functional_test_config(functional_test_config, ws_path, test_run_tracker):
    """
    Parses the functional test configuration from the pipeline config
    Args:
        functional_test_config: functional test configuration from pipe conf
        ws_path: the path to the workspace on disk
    Returns:
        List of test runs with formatted configuration
    """
    test_executions = list()

    if 'cpap' in functional_test_config.keys():
        cpap_config = functional_test_config['cpap']

        if 'local_repo' in cpap_config.keys():
            local_cpap_config = cpap_config['local_repo']

            if 'test_dir' in local_cpap_config.keys():
                execution = build_cpap_suite(
                    local_cpap_config['test_dir'],
                    ws_path
                )

                if execution: test_executions.append(execution)

            if 'test_configs' in local_cpap_config.keys():
                executions = build_test_executions(
                    local_cpap_config['test_configs'],
                    test_run_tracker,
                    ws_path
                )

                if executions: test_executions += executions

        if 'integration_testing_repo' in cpap_config.keys():
            itr_cpap_config = cpap_config['integration_testing_repo']

            if 'test_configs' in itr_cpap_config.keys():
                executions = build_test_executions(
                    itr_cpap_config['test_configs'],
                    test_run_tracker
                )

                if executions: test_executions += executions

    return test_executions

def parse_env(cli_args):
    """
    Parses environment variables for required and optional arguments
    Args:
        cli_args: args from command line
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = ['OUTPUT']
    optional_vars = ['WS_PATH', 'TEST_TRACKER_PATH']

    global_vars = ['GLOBAL_TEST_CONFIG', 'GLOBAL_META_PURPOSES']
    if cli_args.skip_smoke:
        optional_vars.extend(global_vars)
    else:
        required_vars.extend(global_vars)

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    for var in optional_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            args[var.lower()] = None

    return args

def main():
    setup_logger()
    arg_parser = set_parser()
    args = parse_env(arg_parser)
    test_executions = list()
    test_run_tracker = None
   
    if args['test_tracker_path']:
        test_run_tracker = dict()
        if os.path.exists(args['test_tracker_path']) and os.stat(args['test_tracker_path']).st_size != 0:
            with open(args['test_tracker_path'], 'r') as f:
                data = json.load(f)
            test_run_tracker = data

    if args['ws_path']:
        pipe_config = PipelineConfig(args['ws_path'])
        if pipe_config.functional_tests:
            executions = parse_functional_test_config(
                pipe_config.functional_tests,
                args['ws_path'],
                test_run_tracker
            )

            if executions: test_executions += executions

    if not arg_parser.skip_smoke:
        global_smoke_run = format_test_execution(
            args['global_test_config'],
            args['global_meta_purposes'].split(','), [], [], [], [], [], [], [], defaultProcessCount, [], ""
        )
        test_executions.append(global_smoke_run)

    with open(args['output'], 'w+') as f:
        json.dump(test_executions, f)
    
    if args['test_tracker_path']:
        with open(args['test_tracker_path'], 'w+') as f:
            json.dump(test_run_tracker, f)

  
if __name__ == "__main__":
    main()
