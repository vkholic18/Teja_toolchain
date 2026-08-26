# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# Description:
#     For each feature flag that has changed in the pr create a single test configuration in a separate file
#Arguments:
#      $1: directory with promotion environment branch
#      $2: directory with promotion environment master
#      $3: promotion branch name to match mzone
#      $4: base directory for dump pipeline.yaml files for promotion tests
#

import logging
import sys
import yaml
import os

# Constants
PROMOTION_BRANCH_BASE_NAME = 'PROMOTION-BRANCH-'  # works with both PROMOTION-BRANCH-* and OPS-PROMOTION-BRANCH-*
ALWAYS_RUN_FEATURE_FLAG = 'always-run'
COMPONENTS_ORDERED_LIST_FILE_NAME = 'components-ordered-list'
RELEASE_BUNDLE = '-RB-'

def load_yaml(file_path):
    with open(file_path) as f:
        dictionary = yaml.safe_load(f)

    return dictionary

def load_yaml_string(yaml_str):
    logger = logging.getLogger()
    try:
        dictionary = yaml.safe_load(yaml_str)
        return dictionary
    except yaml.YAMLError:
        logger.info(f"yaml {yaml_str} is not valid, exiting")
        sys.exit(1)

def save_yaml(file_path, yaml_dict, printout=False):
    with open(file_path, 'w') as outfile:
        yaml.dump(yaml_dict, outfile, default_flow_style=False)
    if printout:
        print (yaml.dump(yaml_dict, default_flow_style=False))

def get_env_from_branch(promotion_branch_name):
    try:
        branch_name = promotion_branch_name.split(PROMOTION_BRANCH_BASE_NAME, 1)[1].split('-', 1)[0]
    except:
        print("Failed to split branch name {} based on promotion branch prefix {} ".format(promotion_branch_name,PROMOTION_BRANCH_BASE_NAME))
        print("PR is not based on promotion branches. Exiting ...")
        sys.exit(1)
    return branch_name

def dump_pipeline_yaml_test_config(promotion_branch_yaml, ff_name):

    api_key_alias = ""
    mzone_name = ""
    rule_tag = ""
    rias_url = ""
    
    promotion_branch_name = sys.argv[4]
    promotion_zone = get_env_from_branch(promotion_branch_name)

    rule_tag = sys.argv[6]
    print("Processing name= " + ff_name)

    for promotion_environment in promotion_branch_yaml["test_environments"]:
        promotion_environment_name = str(promotion_environment["name"])

        if promotion_environment_name == promotion_zone:
            mzone_name = promotion_environment_name
            rias_url = promotion_environment["rias_url"]
            api_key_alias = promotion_environment["api_key_alias"]
            break

    if mzone_name == "":
        print("Failed to find a promotion zone: {} from branch name: {} in promotion configuration. Exiting ..." .format(promotion_zone, promotion_branch_name))
        sys.exit(1)

    print("promotion_branch_name= " + promotion_branch_name)
    if RELEASE_BUNDLE not in promotion_branch_name: 
        promotion_feature_flags = promotion_branch_yaml["feature_flags"]["vpc-ci"]
    else:
        promotion_feature_flags = promotion_branch_yaml["release_bundles"]

    is_ff_found_in_promotion_config = False
    for promotion_ff in promotion_feature_flags:
        if promotion_ff["name"] == ff_name:
            #create pipeline.yaml format file
            promtion_pipeline_yaml = {'deployment':{}, 'functional_tests':{}}

            ff_object = {"feature_flag": ff_name}
            promtion_pipeline_yaml["deployment"].update(ff_object)

            if RELEASE_BUNDLE in promotion_branch_name: 
                ff_object_temp = {"release_bundles": ff_name}
                promtion_pipeline_yaml["deployment"].update(ff_object_temp)

            rule_tag_object = {"rule_tag": rule_tag}
            promtion_pipeline_yaml["deployment"].update(rule_tag_object)

            rias_url_object = {"rias_url": rias_url}
            promtion_pipeline_yaml["deployment"].update(rias_url_object)
            
            api_key_alias_object = {"api_key_alias": api_key_alias}
            promtion_pipeline_yaml["deployment"].update(api_key_alias_object)

            mzone_name_object = {"mzone_name": mzone_name}
            promtion_pipeline_yaml["deployment"].update(mzone_name_object)

            functional_tests_object = promotion_ff["functional_tests"]
            promtion_pipeline_yaml["functional_tests"].update(functional_tests_object)

            jira_project_object = {"jira_project": promotion_ff["jira_project"]}
            promtion_pipeline_yaml.update(jira_project_object)

            base_dump_dir = sys.argv[5]
            dump_directory = base_dump_dir + ff_name + "/hack/ci/"
            if not os.path.exists(dump_directory):
                os.makedirs(dump_directory)
            save_yaml(dump_directory +"pipeline.yaml", promtion_pipeline_yaml, True)
            is_ff_found_in_promotion_config = True
            break
    if not is_ff_found_in_promotion_config:
        print("Feature flag version {} was updated in pr but not found in promotion yaml configuration." .format(ff_name))

def create_components_ordered_list_file(promotion_branch_yaml, not_ordered_promotion_tests_list):
    base_file_dir = sys.argv[5]
    components_ordered_list_file = os.path.join(base_file_dir, COMPONENTS_ORDERED_LIST_FILE_NAME)
    ordered_list_File = open(components_ordered_list_file, "a")

    promotion_branch_name = sys.argv[4]
    if RELEASE_BUNDLE not in promotion_branch_name: 
        promotion_feature_flags = promotion_branch_yaml["feature_flags"]["vpc-ci"]
    else:
        promotion_feature_flags = promotion_branch_yaml["release_bundles"]

    for promotion_ff in promotion_feature_flags:
        if promotion_ff["name"] in not_ordered_promotion_tests_list:
            ordered_list_File.write(promotion_ff["name"] + " ")
    ordered_list_File.close()

def create_test_environments(environment_branch_yaml, environment_master_yaml, promotion_yaml_branch_file):
    promotion_branch_name = sys.argv[4]
    if RELEASE_BUNDLE not in promotion_branch_name: 
        feature_flags_branch = environment_branch_yaml["apps"]["feature_flags"]["vpc-ci"]
        feature_flags_master = environment_master_yaml["apps"]["feature_flags"]["vpc-ci"]
    else:
        feature_flags_branch = environment_branch_yaml["apps"]["release_bundles"]
        feature_flags_master = environment_master_yaml["apps"]["release_bundles"]

    # Build a mapping for quick lookup when processing branch flags.
    feature_flags_master_index = {}
    for idx, flag in enumerate(feature_flags_master):
        name = flag["name"]
        feature_flags_master_index[name] = idx

    promotion_branch_yaml = load_yaml(promotion_yaml_branch_file)
    is_new_test_environment_created = False
    not_ordered_promotion_tests_list = []

    # Iterate over branch flags to compare against master environment.yaml.
    # Where there are version changes, add the corresponding tests to be run.
    for ff_branch in feature_flags_branch:
        ff_branch_name = ff_branch["name"]

        #TO-DO add hostos support, skip hostos release bundles for now
        if "hostos" in ff_branch_name:
            print("Skipping hostos release bundle {} ".format(ff_branch_name))
            continue
        
        # If the flag name wasn't found in master environment.yaml then we
        # have nothing to compare against.
        if ff_branch_name not in feature_flags_master_index.keys():
            print("Pr FF {} doesn't exist in master environment.yaml".format(ff_branch_name))
            continue

        idx = feature_flags_master_index[ff_branch_name]

        # Simply compare the flag entries between branch and master, if they are
        # the same, then no need to run tests.
        if ff_branch == feature_flags_master[idx]:
            print("Pr FF versions and master for {} are identical. Skip this feature flag and continue".format(ff_branch_name))
            continue

        print("Create configuration for {} feature flag".format(ff_branch_name))
        dump_pipeline_yaml_test_config(promotion_branch_yaml, ff_branch_name)
        not_ordered_promotion_tests_list.append(ff_branch_name)

        # If we generate at least one test environment, then set this flag so we
        # also append always run tests to the context.
        is_new_test_environment_created = True

    if is_new_test_environment_created:
        print("Create configuration for {} feature flag".format(ALWAYS_RUN_FEATURE_FLAG))
        dump_pipeline_yaml_test_config(promotion_branch_yaml, ALWAYS_RUN_FEATURE_FLAG)
        not_ordered_promotion_tests_list.append(ALWAYS_RUN_FEATURE_FLAG)
    else:
        print("No changes were found in feature flag versions and no test environment was created. Exiting ...")

    #if not_ordered_promotion_tests_list not empty
    if not_ordered_promotion_tests_list:
        create_components_ordered_list_file(promotion_branch_yaml, not_ordered_promotion_tests_list)

def main():
    promotion_yaml_file_name = sys.argv[1]
    promotion_branch_repo = sys.argv[2]
    promotion_master_repo = sys.argv[3]
    environment_yaml_branch_file = promotion_branch_repo + "/environment.yaml"
    promotion_yaml_branch_file = promotion_branch_repo + "/hack/ci/" + promotion_yaml_file_name
    environment_yaml_master_file = promotion_master_repo + "/environment.yaml"
    environment_branch_yaml = load_yaml(environment_yaml_branch_file)
    environment_master_yaml = load_yaml(environment_yaml_master_file)
    create_test_environments(environment_branch_yaml, environment_master_yaml, promotion_yaml_branch_file)

if __name__ == "__main__":
    main()
