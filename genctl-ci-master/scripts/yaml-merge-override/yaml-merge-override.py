# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Merges two yaml files where existing values in list elements are overriden
#    by second specified file, producing a third specified yaml file.
#    Source: https://stackoverflow.com/questions/58500491/merge-yaml-files-with-overriding-values-in-list-elements
#
# Inputs:
#  - base.yaml - existing yaml file
#  - new.yaml  - new yaml file to override existing values
#  - out.yaml  - output yaml file of the result

import argparse
import copy
import ruamel.yaml
yaml = ruamel.yaml.YAML()

def set_parser():
    """
    Parse the arguments passed when calling this file.
    Returns:
        parser (parser object)
    """
    parser = argparse.ArgumentParser(
        description='Merge two yaml files')
    parser.add_argument('-b', '--base-file',
                        default="base.yaml", dest="base_file",
                        help="Existing base file")
    parser.add_argument('-n', '--new-file',
                        default="new.yaml", dest="new_file",
                        help="New file that overrides the existing content")
    parser.add_argument('-o', '--out-file', dest="out_file",
                        help='The output file of merged content')
    parser.add_argument('-d', '--debug', help="When used, enables debug mode. No args", required=False,
                        dest="debug", default=False, action='store_true')
    return parser.parse_args()

def main():
    args = set_parser()

    #Load the yaml files
    with open(args.new_file) as fp:
        newyaml = yaml.load(fp)
    with open(args.base_file) as fp:
        baseyaml = yaml.load(fp)

    outyaml = copy.deepcopy(baseyaml)
    copyfabcon = False

    for nk in newyaml['payload_manifest'].keys():
        # copy/overwrite anything not in artifact_groups
        if nk != 'artifact_groups':
            outyaml['payload_manifest'][nk] = newyaml['payload_manifest'][nk]
        else:
            # within artifact_groups, just overwrite everything under group_name: fabcon
            for ags in newyaml['payload_manifest'][nk]:
                if 'fabcon' == ags['group_name']:
                    copyfabcon = True
                if copyfabcon:
                    agsindx = 0
                    for oags in outyaml['payload_manifest'][nk]:
                        if 'fabcon' == oags['group_name']:
                            outyaml['payload_manifest'][nk][agsindx] = ags
                            break
                        else:
                            agsindx += 1
                    break

    #create a new file with merged yaml
    with open(args.out_file, 'w') as yaml_file:
        yaml.dump(outyaml, yaml_file)

if __name__ == "__main__":
    main()
