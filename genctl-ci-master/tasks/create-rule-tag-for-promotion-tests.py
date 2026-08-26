# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# Description:
#
#Arguments:
#      $1: directory with promotion environment branch
#      $2: promotion branch name to match mzone
#      $3: file to save RULE_TAG
#

import logging
import sys
import yaml
import os

# Constants
PROMOTION_BRANCH_BASE_NAME = 'PROMOTION-BRANCH-'  # works with both PROMOTION-BRANCH-* and OPS-PROMOTION-BRANCH-*

def load_yaml(file_path):
    with open(file_path) as f:
        dictionary = yaml.safe_load(f)

    return dictionary

def get_env_from_branch(promotion_branch_name):
    try:
        branch_name = promotion_branch_name.split(PROMOTION_BRANCH_BASE_NAME, 1)[1].split('-', 1)[0]
    except:
        print("Failed to split branch name {} based on promotion branch prefix {} ".format(promotion_branch_name,PROMOTION_BRANCH_BASE_NAME))
        print("PR is not based on promotion branches. Exiting ...")
        sys.exit(1)
    return branch_name

def create_rule_tag(promotion_yaml_branch_file, rule_tag_file, promotion_repo_master_environment_yaml, single_rias_cluster_file):
    promotion_environment_name = ""
    rule_tag = ""
    single_rias_cluster_rule = False

    promotion_branch_name = sys.argv[3]
    promotion_zone = get_env_from_branch(promotion_branch_name)
    
    promotion_branch_yaml = load_yaml(promotion_yaml_branch_file)

    if "test_environments" not in promotion_branch_yaml:
      print("Workspace repo's promotion yaml is missing the required 'test_environments' definition.")
      sys.exit(1)

    for promotion_environment in promotion_branch_yaml["test_environments"]:
        promotion_environment_name = str(promotion_environment["name"])

        if promotion_environment_name == promotion_zone:
            cluster_names = []

            providers = promotion_repo_master_environment_yaml["infrastructure"]["providers"]

            iks_clusters = providers["ibm_cloud"]["resources"]["ibm_container_cluster"]

            for cluster in iks_clusters:
              if "vars" in cluster:
                if cluster["name"] not in cluster_names: # prevent dup with single mzone
                    cluster_names.append(cluster["name"])
              elif "globals" in cluster:
                if cluster["name"] not in cluster_names: # prevent dup with single mzone
                    cluster_names.append(cluster["name"])

            # At this point we have all rias/rias-etcd clusters 
            # with no dups in cluster_names, check length to 
            # decide if it is a single cluster env
            if len(cluster_names) == 1:
               single_rias_cluster_rule = True

            # Temporary restriction for staging/production mzones in promotion validation.
            if "staging" not in promotion_environment_name and "prod" not in promotion_environment_name:
              for mzone in providers["ibm_onprem"]["mzones"]:
                cluster_names.append(mzone["name"])
              # Check if zonelets are present and append their names to cluster_names
              if "zonelets" in providers["ibm_onprem"]:
                for zonelet in providers["ibm_onprem"]["zonelets"]:
                  cluster_names.append(zonelet["name"])

            rule_tag = ','.join(cluster_names)

    if promotion_environment_name == "":
        print("Failed to find a promotion zone: {} from branch name: {} in promotion configuration. Exiting ..." .format(promotion_zone, promotion_branch_name))
        sys.exit(1)

    file = open(rule_tag_file, "w")
    file.write(str(rule_tag))
    file.close()

    rias_rule_file = open(single_rias_cluster_file, "w")
    rias_rule_file.write(str(single_rias_cluster_rule))
    rias_rule_file.close()

def main():
    promotion_yaml_file_name = sys.argv[1]
    promotion_branch_repo = sys.argv[2]
    rule_tag_file = sys.argv[4]
    single_rias_cluster_file = sys.argv[6]
    promotion_yaml_branch_file = promotion_branch_repo + "/hack/ci/" + promotion_yaml_file_name
    promotion_repo_master_environment_yaml = load_yaml(sys.argv[5])
    create_rule_tag(promotion_yaml_branch_file, rule_tag_file, promotion_repo_master_environment_yaml, single_rias_cluster_file)

if __name__ == "__main__":
    main()

