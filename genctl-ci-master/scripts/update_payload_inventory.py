#!/usr/bin/env python3

##
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2019-2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
##

"""
" this script will update a payload yaml with a new/existing package
"
" usage:
" update_payload_inventory.py <payload_yaml> <group> <package> <version>
"
" assumptions: 'artifact_types' = 'deb'
" unless we have another consumer for this functionality, we do not need to factor the above in
"""

###############################################################################
# I M P O R T S
###############################################################################
import logging
import sys

from ruamel.yaml import YAML

###############################################################################
# F U N C T I O N S
###############################################################################

def add_package_to_group(yaml_content, group_name, package, version, architecture=all):
    """
    " this function will add a package, if not found, to the yaml and include the version.
    " if the package is found, we will only modify the version.
    " the package will be inserted/edited under "group_name". if group_name does not exist,
    " that is considered an error
    "
    " see below for a sample format of the payload yamls
    """

    logger = logging.getLogger()
    ##
    # sample payload format
    ##
    # payload_manifest:
    #   payload_type: base-os-sw
    #   payload_version: 0.1.0
    #   artifact_groups:
    #   - group_name: common-tools
    #     artifact_types:
    #     - file_type: deb
    #       artifacts:
    #       - name: sudo
    #         file_location: <canonical-ppa>/main
    #         personalities:
    #         - all
    #         arch_versions:
    #           all: 1.8.21p2-3ubuntu1.2
    ##
    for group in yaml_content['payload_manifest']['artifact_groups']:

        if group['group_name'] == group_name:

            types = group['artifact_types']

            logger.debug(f"group found: {group_name}")

            for pkg_type in types:

                if pkg_type['file_type'] == 'deb':

                    artifacts = pkg_type['artifacts']

                    for artifact in artifacts:

                        if artifact['name'] == package:

                            logger.info(f"Package was found, editing version to: {version}")

                            # edit the version
                            artifact['arch_versions'][architecture] = version

                            return yaml_content

                    else:

                        logger.info(f"No package found for \"{package}\", we will add it")

                        new_package = {'name': package,
                                       'file_location': "<does_not_matter>/what_goes_here",
                                       'personalities': ['all'],
                                       'arch_versions': {architecture: version}
                                       }

                        artifacts.append(new_package)

                        return yaml_content

    logger.error(f"No group_name labeled \"{group_name}\" was found payload yaml")
    sys.exit(1)

def main():
    """
    " see mod docstring
    """

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger()

    if len(sys.argv) < 5:  # script name is element 0
        print(len(sys.argv))
        logger.error("This script only takes 4 required arguments: <payload_yaml> <group> <package> <version>, one optional <architecture>")
        sys.exit(1)

    payload_file = sys.argv[1]
    logger.debug(f"payload file: {payload_file}")

    group_name = sys.argv[2]
    logger.debug(f"group_name: {group_name}")

    package = sys.argv[3]
    logger.debug(f"package: {package}")

    version = sys.argv[4]
    logger.debug(f"version: {version}")
    
    try:
        if sys.argv[5]:
            architecture=sys.argv[5]
        else:
            architecture= 'all'
    except IndexError:
        architecture= 'all'
        
    logger.debug(f"architecture: {architecture}")    

    try:
        with open(payload_file, 'r') as yaml_f:
            yaml = YAML()

            payload_yaml = yaml.load(yaml_f)

    except FileNotFoundError:
        logger.error(f"The payload file \"{payload_file}\" does not exist")
        sys.exit(1)
    except yaml.YAMLError as err:
        logger.error("Unable to parse yaml ({}): reason: {}".format(payload_file, err))
        sys.exit(1)
    except:
        logger.error("Unable to open manifest yaml ({}): reason: {}".format(payload_file, sys.exc_info()[0]))
        sys.exit(1)

    payload_yaml = add_package_to_group(payload_yaml, group_name, package, version, architecture)

    # write the yaml back out
    try:
        with open(f"{payload_file}", 'w') as yaml_f:
            yaml.dump(payload_yaml, stream=yaml_f)

    except yaml.YAMLError as err:
        logger.error("Unable to parse yaml ({}): reason: {}".format(
            payload_file, err), file=sys.stderr)
        sys.exit(1)
    except:
        logger.error("Unable to write manifest yaml ({}): reason: {}".format(
            payload_file, sys.exc_info()[0]), file=sys.stderr)
        sys.exit(1)

###############################################################################
# M A I N
###############################################################################


if __name__ == '__main__':
    main()
