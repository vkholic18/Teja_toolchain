#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# /usr/local/bin/python3
"""
* 1.) scan through all the pipelines
* 2.) read each 'resource'/'resource_type' block in each config
* 3.) display all 3rd party docker images and tags
* 4.) display each image/tag and its associated yaml file and aggregate them and show various versions
"""

###############################################################################
# I M P O R T S ###############################################################
###############################################################################

import logging
import os
import sys
import argparse

from concourse.user_exceptions import ConfigError
from concourse.concourse_pipeline import ConcoursePipeline

###############################################################################
# F U N C T I O N S ###########################################################
###############################################################################


def setup_logger(debug_enabled=False):
    """
    * Setup up the logger and return a handle
    """
    # set the logger to show the time/level/message
    # stdout logging is sufficient

    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.DEBUG if debug_enabled is True else logging.INFO)

    return logger


def discover_yamls(yamldir, user_specified_yamls):
    """
    * locate all the yamls to parse and send back to caller
    """
    logger = logging.getLogger()

    if yamldir is not None:
        logger.debug("changing directory to: {}".format(yamldir))
        os.chdir(yamldir)

    logger.info("Searching for pipeline configs in dir: {}".format(os.getcwd()))

    yamls = list()

    extensions = ['.yaml', '.yml']

    for artifact in os.listdir(os.getcwd()):

        logger.debug("Discovered artifact: {}".format(artifact))

        if os.path.isfile(artifact) is True:
            if user_specified_yamls:
                if os.path.basename(artifact) in user_specified_yamls:
                    logger.info("Candidate for parsing: {}".format(artifact))
                    yamls.append(artifact)
            else:
                if os.path.splitext(artifact)[1] in extensions:
                    logger.info("Candidate for parsing: {}".format(artifact))
                    yamls.append(artifact)

    return yamls


def main():
    """
    * 1.) scan through all the pipelines
    * 2.) read each 'resource'/'resource_type' block in each config
    * 3.) display all 3rd party docker images and tags
    * 4.) display each image/tag and its associated yaml file and aggregate them and show various versions
    """

    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", dest="debug", action="store_true",
                        help="Increase verbosity", default=False)
    required_args = parser.add_argument_group('required named arguments:')
    required_args.add_argument("--yamldir", required=True,
                               help=("Directory that contains the pipeline yaml's. All config found, unless --yaml is"
                                     "used, will be processed"))

    args = parser.parse_args()

    logger = setup_logger(debug_enabled=True if args.debug is True else False)

    logger.debug("options : {}".format(args))

    concourse_configs = list()

    for yaml_file in discover_yamls(args.yamldir, []):
        try:
            concourse_configs.append(ConcoursePipeline(yaml_file))
        except ConfigError as e:
            logger.error(e)
            sys.exit(1)

    inventory = dict()
    # parse each yaml, swap out vars as test, and write out the updated file (and its constituent sub vars file)
    for pipeline in concourse_configs:

        logger.debug("yaml: {}".format(pipeline.yaml_file))

        inventory[pipeline.yaml_file] = pipeline.get_docker_images(third_party_only=True)

    unique_dockers = dict()

    logger.info("")
    logger.info("Third Party Images Per Pipeline")
    logger.info("-------------------------------")
    # display all the docker images per pipeline and also collate all unique dockers and their tags
    for filename, images in inventory.items():
        logger.info("YAML: {}".format(filename))

        for image in images:
            logger.info("\tImage: {}, tag: {}".format(image[0], image[1]))

            if image[0] not in unique_dockers :
                unique_dockers[image[0]] = [image[1]]
            else:
                if image[1] not in unique_dockers[image[0]]:
                    unique_dockers[image[0]].append(image[1])

    logger.info("")
    logger.info("Unique Docker Images")
    logger.info("--------------------")
    for image, tags in unique_dockers.items():

        logger.info("image: {}".format(image))

        for tag in tags:
            logger.info("\ttag: {}".format(tag))

###############################################################################
# M A I N #####################################################################
###############################################################################
if __name__ == "__main__":
    main()
