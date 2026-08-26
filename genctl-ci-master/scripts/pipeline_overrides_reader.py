#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Gets the appropriate yaml script to use in the template-deployer based on the given code.
#   Inputs: full-pipeline-name (this acts as the key to get the right override)
#   Output: When a override key is successfully it creates a merged yaml file in /tmp

###############################################################################
# I M P O R T S ###############################################################
###############################################################################
import os
import sys
import shutil
import ruamel.yaml

###############################################################################
# F U N C T I O N S ###########################################################
###############################################################################
def get_arg():
    """gets the override key"""
    override_key = str(sys.argv[1]).strip()
    return override_key

def make_file(override_key, dir):
    """makes an override file in /tmp
    inputs:
        override_key: str that represents the override key
        dir: directory of /pipeline_params.yaml
    returns the file path to the created overrides file"""
    
    overrides_path = dir + "/pipeline-overrides.yaml"

    found_flag = False

    #try to find the given override
    with open(overrides_path, "r") as override_file:
        all_overrides = ruamel.yaml.round_trip_load(override_file, preserve_quotes=True)
        all_overrides = all_overrides.get("pipelines")
        for pipeline in all_overrides:
            if pipeline.get("name") == override_key:
                #Check if null
                p_overrides = pipeline.get("overrides")
                if p_overrides != None:
                    overrides = ruamel.yaml.round_trip_dump(p_overrides)
                    found_flag = True

    #if an override key was found, create a temp file
    if found_flag:
        params_file_path = dir + "/pipeline-params.yaml"
        
        #make tmp folder if it doesn't exist
        tmp_file_path = "/tmp"
        if not os.path.exists(tmp_file_path):
            os.mkdir(tmp_file_path)

        temp_file_path = "/tmp/merged-" + override_key + ".yaml"
        
        #copies contents of params file to the new temp file
        shutil.copyfile(params_file_path, temp_file_path)

        #add override contents
        with open(temp_file_path, "a") as temp_file:
            temp_file.write("\n")
            temp_file.write(overrides)
        return temp_file_path
    return None

def main():
    override_key = get_arg()

    #get params path
    path = os.path.realpath(__file__)
    dir = os.path.dirname(path)
    dir = dir.replace("scripts", "params")
    make_file(override_key, dir)
    
            
###############################################################################
# M A I N #####################################################################
###############################################################################
if __name__ == "__main__":
    main()