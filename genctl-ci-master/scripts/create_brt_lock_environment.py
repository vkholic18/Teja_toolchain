# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# Description:
#   The script creates new lock file in mascd-brt-lock directory to used in pr to master pipelines


# Env:
#    WS_PATH: workspace root path
#    RESOURCELOCK_PATH: path to resourcelock repo
#
# Use:
#    python3 create_brt_lock_environment.py ${repo_name} resourcelock-repo ${result_file}


import logging
import os
import yaml
import sys

# Constants
RELATIVE_PIPELINE_CONFIG_PATH = 'hack/ci/pipeline.yaml'
MASCD_LOCK_BASE_DIR = '/mascd-brt-lock'

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

def load_yaml(file_path):
    with open(file_path) as f:
        dictionary = yaml.safe_load(f)
    return dictionary

def save_yaml(file_path, yaml_dict):
    with open(file_path, 'w') as outfile:
        yaml.dump(yaml_dict, outfile, sort_keys=False)

def main():
    logger = set_up_logger()

    ws_path = sys.argv[1]
    resourcelock_path  = sys.argv[2]
    result_file  = sys.argv[3]

    infile = ws_path + "/hack/ci/pipeline.yaml"
    pipeline_environment = load_yaml(infile)
    lock_environment_name = ""
    try:
        iks_cluster_name = pipeline_environment['deployment']['iks_cluster_name']
    except KeyError:
        print(f"iks_cluster_name was not found in : {infile} Continue ... \n")
        iks_cluster_name = ""

    if iks_cluster_name != "":
        lock_environment_name = iks_cluster_name

        resource_lock_path = resourcelock_path + MASCD_LOCK_BASE_DIR
        environment_lock_exist = False
        for root, directories, filenames in os.walk(resource_lock_path):
            for filename in filenames:
                if os.path.isfile(os.path.join(root, filename)):
                    if filename == lock_environment_name:
                        environment_lock_exist = True
                        break
        # if a lock file does not exist in claimed or unclaimed create a new lock file
        if environment_lock_exist == False:
            try:
                feature_flag = pipeline_environment['deployment']['feature_flag']
            except KeyError:
                print(f"feature_flag was not found in : {infile} Continue ... \n")
                feature_flag = ""
            new_lock_env_file = os.path.join(resource_lock_path, 'unclaimed', lock_environment_name)
            lockFile = open(new_lock_env_file, "w")
            lockFile.write("Used for repo: " + ws_path + " ")
            lockFile.write("and feature flag: " + feature_flag + "\n")
            lockFile.close()

    print(f"Lock environment file: {lock_environment_name} ")
    resFile = open(result_file, "w")
    resFile.write(lock_environment_name)
    resFile.close()


if __name__ == "__main__":
    main()
