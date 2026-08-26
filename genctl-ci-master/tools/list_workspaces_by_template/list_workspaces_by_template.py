# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: List workspaces that have a pipelines configured with a specific template

#   If all the properties match the expected, exit 0
#   If not, prints the properties that do not match the expected and exit 1
#
#
# Env:
#    PATH_TO_TEMPLATIZED_PIPELINES_FILE: Path to the templatized-pipelines.yaml file that will be filtered
#    TEMPLATE_TO_FILTER_BY: The template to filter by (Full name of it including .yaml extension)
#
# Use:
#
#    export PATH_TO_TEMPLATIZED_PIPELINES_FILE="genctl-ci-repo/pipelines/templatized-pipelines.yaml"
#    export TEMPLATE_TO_FILTER_BY="pr-template-workspace-dev-integration-generic.yaml"
#    python3 list_workspaces_by_template.py


import yaml
import logging
import os


def set_up_logger():
    """
    Configures logger and formatting
    Returns:
        Logger object
    """
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

    return logger


def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'PATH_TO_TEMPLATIZED_PIPELINES_FILE',
        'TEMPLATE_TO_FILTER_BY',
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args


def main():
    # Define logger and parse environment vars
    logger = set_up_logger()
    args = parse_env()

    # Load the YAML file
    if os.path.exists(args['path_to_templatized_pipelines_file']):
        with open(args['path_to_templatized_pipelines_file'], 'r') as stream:
            templatized_pipelines = yaml.safe_load(stream)

    # Iterate over the workspaces
    for workspace in templatized_pipelines:

        # Get the pipelines for that workspace
        pipelines = templatized_pipelines[workspace].keys()

        # Iterate over the pipelines
        for pipeline in pipelines:
            if os.path.basename(templatized_pipelines[workspace][pipeline]) == args['template_to_filter_by']:
                print(workspace)


if __name__ == "__main__":
    main()
