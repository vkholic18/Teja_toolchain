# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Parses a pipeline.yaml file and generates a text file with lines that export variables for later use
#
# Use:
#    python3 parse_pipeline_yaml_to_export.py path_to_repo_base

import sys
import logging

from pipeline_config import PipelineConfig

# List of strings where each string should be in the form of export x=y
lines_to_write = []

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


def parse_environment_section(environment_section):
    """ 
        Parses the environment section of a pipeline.yaml file
        Adds the relevant export lines to the lines_to_write according to the mapping
    """
    # This dictionary maps a key from the environment section with a name of variable to be exported
    mapping = {
        'tag': 'CC_CBUILD_IMAGE_MULTIARCH_TAG'
    }

    # Iterate over the supported keys of the environment section
    for k in mapping.keys():
        
        # If the key is in the section add the relevant line to lines_to_write
        if k in environment_section.keys():
            lines_to_write.append("export {}={}".format(mapping[k], environment_section[k]))

def main():
    # Set path to repo base
    path_to_repo_base = sys.argv[1]

    # Setup the logger
    setup_logger()

    # Get the logger
    logger = logging.getLogger()

    # Load to a dictionary the content of the pipeline.yaml file
    # If there is no file then it will be None
    pipe_config = PipelineConfig(path_to_repo_base)

    # If there is a pipeline.yaml file, parse it
    if pipe_config.config:
        logger.info("Found pipeline.yaml, proceed to parse")

        # If pipeline.yaml file contains environment section, parse it
        if pipe_config.environment:
            parse_environment_section(pipe_config.environment)

        # At this point finished parsing, verify that there is at least a line to write, if not exit
        if lines_to_write:
            with open("pipeline_yaml_vars.txt", "w") as f:
                f.write('\n'.join(lines_to_write))
        else:
            logger.error("Parsed pipeline.yaml file but resulted in no lines to write")
            sys.exit(1)

if __name__ == "__main__":
    main() 