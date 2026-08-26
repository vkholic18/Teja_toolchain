#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

import sys
from ruamel.yaml import YAML, SafeConstructor

yaml = YAML()  # default, if not specfied, is 'rt' (round-trip)
yaml.default_flow_style = False
yaml.allow_duplicate_keys = True
yaml.preserve_quotes = True

yaml.representer.ignore_aliases = lambda x: True
with open(sys.argv[1], "r") as myfile:
    yaml_config = yaml.load(myfile)

if 'common' in yaml_config:
    del yaml_config['common']

with open(sys.argv[2], 'w') as yaml_file :
    yaml.dump(yaml_config, yaml_file)