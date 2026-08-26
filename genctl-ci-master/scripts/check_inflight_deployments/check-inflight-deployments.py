# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Compares master and deployed_artifacts branches respective environment.yaml files
#    If they are the same, it means there's no in-flight merge pipeline taking place
#    If they are different, we drill down into the feature flag set only and check for differences
#    If different versions for a given feature flag is detected, we fail, otherwise continue with pipeline

# Args:
#    master branch environment.yaml path
#    deployed_artifacts environment.yaml path

#
# Use:
#    python3 <master branch environment.yaml path> <deployed_artifacts environment.yaml path>
#

import filecmp
import sys
import yaml
import time
import os
import logging
import github

def parse_yaml(filename):
  """ Parse yaml files"""
  
  with open(filename) as f:
      data = yaml.safe_load(f)
  return data

def retry_promotional_pipeline(gh, deployed_artifact_repo, parsed_master, wait_in_minutes):
    period=60
    waiting_for=0
    wait_seconds = int(wait_in_minutes) * 60
    mustend = time.time() + wait_seconds
    while True:
        print(f"in-flight deployments in place. Promotional pipeline will retry after {int(period/60)} min.")
        time.sleep(period)
        waiting_for += period/60
        print(f"cloning {deployed_artifact_repo} repo to check if still in-flight")
        repo = gh.get_repo(deployed_artifact_repo)
        env = repo.get_contents("environment.yaml",ref="deployed_artifacts")
        deployed_artifact_repo_eymal="environment.yaml"
        with open(deployed_artifact_repo_eymal, 'w') as f:
               print(env.decoded_content.decode("utf-8"), file=f)
        parsed_deployed_artifacts=parse_yaml(deployed_artifact_repo_eymal)
        if(compare_feature_flags(parsed_master, parsed_deployed_artifacts) == False or time.time() >= mustend):
          break
    if (time.time() >= mustend):
       return False
    return True

def compare_feature_flags(parsed_master, parsed_deployed_artifacts):
  """ Ccompares feature flag versions between the 2 environment.yaml files"""
  
  master_feature_flags = parsed_master['apps']['feature_flags']['vpc-ci']
  deployed_artifacts_feature_flags = parsed_deployed_artifacts['apps']['feature_flags']['vpc-ci']
  
  difference = False
  # iterate through list of arrays
  for master_ff in master_feature_flags:
    master_ff_name = master_ff["name"]
    master_ff_version = master_ff["default"]["variation_value"]
    for deployed_artifact_ff in deployed_artifacts_feature_flags:
      deployed_artifact_ff_name = deployed_artifact_ff["name"]
      deployed_artifact_ff_version = deployed_artifact_ff["default"]["variation_value"]
      if deployed_artifact_ff_name == master_ff_name:
        if deployed_artifact_ff_version == master_ff_version:
          # Values are the same, continue with next feature flag name
          continue
        else:
          difference = True
          print(f"{master_ff_name}: {master_ff_version} in master, {deployed_artifact_ff_version} in deployed_artifacts")
          
  return difference

def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'GHE_API_TOKEN',
        'GHE_API_URL',
        'DEPLOYED_ARTIFACT_REPO',
        'PIPELINE_TIMEOUT'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args

def main():
  args = parse_env()
  master_yaml = sys.argv[1]
  deployed_artifacts_yaml = sys.argv[2]
  pipeline_timeout = args['pipeline_timeout']
  deployed_artifact_repo=args['deployed_artifact_repo']
  # Do an early full file comparison first - if they match we're good, no need to drill into feature flag versions
  result = filecmp.cmp(master_yaml, deployed_artifacts_yaml, shallow=False)
  if result:
    print("No difference between master and deployed_artifacts environment.yaml files, continuing pipeline...")
  else:
    print("Differences detected between master and deployed_artifacts environment.yaml files...")
    # If the feature flags are the same we can still continue, otherwise exit
    # Parse files
    parsed_master=parse_yaml(master_yaml)
    parsed_deployed_artifacts=parse_yaml(deployed_artifacts_yaml)
    # Compare files
    if compare_feature_flags(parsed_master, parsed_deployed_artifacts) == False:
      print("No difference in version values detected between selected branches, continuing with current pipeline")
    else:
      gh = github.Github(
      login_or_token=args['ghe_api_token'],
      base_url=args['ghe_api_url']
      )
      if retry_promotional_pipeline(gh, deployed_artifact_repo, parsed_master, pipeline_timeout) == False:
        print("Looks like in-flight deployment taking place, please re-run this pipeline later.")
        sys.exit(1)

if __name__ == "__main__":
    main()
    