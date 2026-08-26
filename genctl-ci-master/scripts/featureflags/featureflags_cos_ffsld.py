#! /usr/bin/env python3
## ==============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2025
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## ==============================================================================================
"""
This script is used for ffsld related activities such as reading, comparing, validating against a desired ffsld from the cluster.
"""
import argparse
import json
import os
import re
import sys
import urllib.request
import urllib.parse
from kubernetes import client, config
from github import Github
import time
import subprocess

# Constants
GITHUB_BASE_URL = 'https://github.ibm.com/api/v3'
API_RATE_LIMIT_ERROR = 429
NAMESPACES_BY_CLUSTER_TYPE = {
    'rias': ['rias', 'jaeger', 'riaascore', 'riaasiam','riaasstorage', 'rias-etcd', 'rias-flink', 'sysdig'], 
    'genctl': ['genctl']
}

CLUSTERS = ["rias", "genctl"]
SKIP_API_RESOURCES_PATTERN_LIST = [ 'genesis.ibm.com', 'rias.ibm.com', 'operators.coreos.com']

class CurrentDeployment:
    def __init__(self,flag,version):
        self.flag = flag
        self.version = version

def connect_to_cluster():
    contexts, active_context = config.list_kube_config_contexts()
    if not contexts:
        print("Cannot find context in kube config file")
        return
    config.load_kube_config(context=active_context['name'])
    print("Using {0} as the context to check for the secrets".format(active_context['name']))
    return active_context

def check_status(current_deployments,desired_deployments):
    report = {"idx": ["feature-flag", "desired-version", "current-version", "status", "comment"]}
    idx = 1
    for x in current_deployments:
        feature_flag = x.flag
        desired_version = desired_deployments[feature_flag]
        current_version = ""
        status = ""
        comment = ""
        if len(x.version) > 1:
            status="NOT-OK"
            comment = "deployed multiple versions"
            current_version = ""
            for version in x.version:
                current_version += version + " "
        elif len(x.version) == 1:
            current_version = list(x.version)[0]
            if current_version != desired_version:
                status="NOT-OK"
                comment = "not equal"
            else:
                status="OK"
        else:
            status = "NOT-OK"
            comment = "not deployed"
        s = [feature_flag, desired_version, current_version, status, comment ]
        report.update({idx: s})
        idx += 1

    printReport(report, "validate_promotion.txt")

def get_ff_resource_version(api_resources_list, feature_flag):
    print(f"-------------------    evaluate version for {feature_flag}    ------------------")

    api_resources_str = ','.join(api_resources_list)
    cmd = "kubectl get -A --ignore-not-found {} --selector=workspace_tag={} -o=json ".format(api_resources_str, feature_flag) + \
          "| jq -r '.items[] | select ((.kind == \"ReplicaSet\" and .specreplicas > 0) or (.kind != \"ReplicaSet\" ))" + \
          "| select((.kind == \"DaemonSet\" and .status.currentNumberScheduled > 0) or (.kind != \"DaemonSet\"))" + \
          "| if .metadata.labels.version != null then .metadata.labels.version else empty end  ' "

    try:
        return_code = subprocess.run(cmd, shell=True, text=True, stdout=subprocess.PIPE)
        if return_code.returncode == 1:
            print(f"Return code for {cmd} : {return_code.returncode}")
    except:
        print(f"Exception on {cmd}")
    resource_versions_list = return_code.stdout.splitlines()
    # the resource_versions_list is not empty
    if resource_versions_list:
        print(f"Execute: {cmd}")
        print(f"The versions: {resource_versions_list} are found for FF: {feature_flag} in api-resources: {api_resources_str}")
    else:
        print(f"Nothing found for FF: {feature_flag} in api-resources: {api_resources_str}")
    return set(resource_versions_list)

def get_cluster_context():
    cmd = "kubectl config current-context"
    try:
        print(f"Execute: {cmd}")
        return_code = subprocess.run(cmd, shell=True, text=True, stdout=subprocess.PIPE)
        print(f"Result: {return_code.stdout}")
        if return_code.returncode == 1:
            print(f"Return code for {cmd} : {return_code.returncode}")
            exit(1)
    except:
        print(f"Exception on {cmd}")
        exit(1)

def is_skip_api_resourse(api_resource, skip_list):
    for pattern in skip_list:
        if pattern in api_resource:
            print(f"API Resource is a part of {pattern}, skip API Resource: {api_resource} ")
            return True
        else:
            continue

    return False

def get_current_deployment_versions(desired_deployments, cluster_type="rias"):
    """gets a list of 'CurrentDeployment' objects"""
    current_deployment_list = []
    api_resources_list = get_cluster_api_resources_list()
    print(f"API Resources list: {api_resources_list} ")
    for feature_flag in desired_deployments:
        # skip if the feature_flag is not a member of cluster-remote-resource
        if is_ff_in_cluster_remote_resource(cluster_type, feature_flag):
            start_time = time.time()
            ff_version_set = get_ff_resource_version(api_resources_list, feature_flag)
            resource_versions_set_time = '{0:.2f}'.format(time.time() - start_time)
            print(f"********   Feature flag: {feature_flag} took {resource_versions_set_time} sec to evaluate.  *********")
            current_deployment_list.append(CurrentDeployment(feature_flag,ff_version_set))
        else:
            print(f"Feature flag: {feature_flag} is not a member of Remote Resource of rias or genctl, skip {feature_flag} evaluation ")
            continue

    return current_deployment_list

def get_cluster_api_resources_list():
    cmd = "kubectl api-resources --verbs=list --namespaced -o name"
    try:
        print(f"Execute: {cmd}")
        return_code = subprocess.run(cmd, shell=True, text=True, stdout=subprocess.PIPE)
        if return_code.returncode == 1:
            print(f"Return code for {cmd} : {return_code.returncode}")
    except:
        print(f"Exception on {cmd}")
    cluster_api_resources_list = return_code.stdout.splitlines()
    remove_from_list = ['controllerrevisions.apps']
    for res in cluster_api_resources_list:
        for skip in SKIP_API_RESOURCES_PATTERN_LIST:
            if res.endswith(skip):
                remove_from_list.append(res)
    for res in remove_from_list:
        cluster_api_resources_list.remove(res)
    print(f"api-resources running on the cluster:")
    print(f"{return_code.stdout}")
    return cluster_api_resources_list


def is_ff_in_cluster_remote_resource(namespace, feature_flag):
    cmd = "kubectl get -n {} mtp/cluster-remote-resource -ojson 2>/dev/null | jq --arg FF \"{}\" '.spec.env[] | select(.valueFrom.genericKeyRef.key == \"{}\" )' ".format(namespace, feature_flag, feature_flag)
    try:
        print(f"Execute: {cmd}")
        return_code = subprocess.run(cmd, shell=True, text=True, stdout=subprocess.PIPE)
        if return_code.returncode == 1:
            print(f"Return code for {cmd} : {return_code.returncode}")
            exit(1)
    except:
        print(f"Exception on {cmd}")
        exit(1)
    if return_code.stdout == "":
        if namespace == "rias":
            ops_namespace = "ops"
            ops_cluster_remote_resource = "ops-cluster-remote-resource"
        elif namespace == "genctl":
            ops_namespace = "genctl"
            ops_cluster_remote_resource = "ops-genctl-cluster-remote-resource"
        else:
            print(f"Feature flag {feature_flag} is not member of {namespace} cluster.")
            return False

        cmd = "kubectl get -n {} mtp/{} -ojson 2>/dev/null | jq --arg FF \"{}\" '.spec.env[] | select(.valueFrom.genericKeyRef.key == \"{}\" )' ".format(ops_namespace, ops_cluster_remote_resource, feature_flag, feature_flag)
        try:
            print(f"Execute: {cmd}")
            return_code = subprocess.run(cmd, shell=True, text=True, stdout=subprocess.PIPE)
            if return_code.returncode == 1:
                print(f"Return code for {cmd} : {return_code.returncode}")
                exit(1)
        except:
            print(f"Exception on {cmd}")
            exit(1)
        if return_code.stdout == "":
            print(f"Feature flag {feature_flag} is not member of {namespace} cluster.")
            return False
        else:
            print(f"Feature flag {feature_flag} is a member of {namespace} cluster.")
            return True
    else:
        print(f"Feature flag {feature_flag} is a member of {namespace} cluster.")
        return True

def validate_promotion_func_desired_from_file(file_location, cluster_type):
    "validates if the promote command ran correctly"
    
    # Instead of actually going to launchdarkly, take from file
    # The file should contain the expected from launchdarkly
    with open(file_location) as json_file:
        desired_deployments = json.load(json_file)

    # Get from cluster (By default use current context)
    current_deployments = get_current_deployment_versions(desired_deployments,cluster_type=cluster_type)

    # Compare
    check_status(current_deployments, desired_deployments)

def validate_promotion_by_targetrule(source_context,target_context):
    "validates if the rule_promote command ran correctly"
    config.load_kube_config(context=source_context)
    source_deployments = get_current_deployment_versions(False)
    config.load_kube_config(context=target_context)
    target_deployments = get_current_deployment_versions(False)
    print('{:<30} {:<60} {:<60} {:<10}\n'.format("Deployment name",get_cluster_name_from_context(source_context)+" (Source)",get_cluster_name_from_context(target_context)+" (Target)","Status"))
    for x in source_deployments:
        for y in target_deployments:
            if x.deployment == y.deployment:
                if x.version == y.version:
                    status = "Updated"
                else:
                    status = "Not updated"
                print('{:<30} {:<60} {:<60} {:<10}'.format(x.deployment,x.version,y.version,status))

def get_cluster_name_from_context(context):
    result = context
    if '/' in context:
        result = context.split("/")[0] 
    elif '@' in context:
        result = context.split("@")[1]
    return result

def printReport(report, fileName):
    "writes the report to a file"
    with open(fileName, "w") as f:
        for k, v in report.items():
            s = ""
            if k == 'idx':
                s += " "*5
                s += "{:<32}".format(v[0])
            else:
                s += "{:<5}".format(k)
                s += "{:<32}".format(v[0])
            for i in range(1,len(v)):
                s += "{:<42}".format(v[i])
            print(s)
            s += '\n'
            f.write(s)

# returng git tag by coressponded to the commit sha. If tag does not exist return sha
def get_git_tag_by_commit_sha(github_repo, commit_sha):
    tags = github_repo.get_tags()
    for tag in tags:
        if tag.commit.sha == commit_sha:
            print(f"SUCCESS: Commit {commit_sha} has corresponded tag {tag}")
            return tag.name

    print(f"Could not find corresponded tag for commit {commit_sha}.")
    return commit_sha

def show_active_variation_cos_ffsld(feature_flag, feature_flag_current_variation, git_token, git_repo):
    github = Github(base_url=GITHUB_BASE_URL, login_or_token=git_token)
    # git_repo="genctl-cicd/compute-billing-lifecycle-mgmt"
    try:
        github_repo = github.get_repo(git_repo)
        dev_integration_branch = github_repo.get_branch('dev-integration')
        commit_sha = dev_integration_branch.commit.sha
        print(f"Git Hash: {git_repo} on dev-integration branch has commit hash: {commit_sha}")
        print(f"Featureflag: {feature_flag_current_variation}")
        if commit_sha == feature_flag_current_variation:
            print(f"SUCCESS: dev-integration head is pointing at same commit hash as the current active variation of launch darkly {feature_flag}")
        else:
            tags = github_repo.get_tags()
            for tag in tags:
                if tag.commit.sha == commit_sha and tag.name == feature_flag_current_variation:
                    print(f"SUCCESS: dev-integration head is pointing at same commit hash as the current active variation of launch darkly {feature_flag}")
                    break
            else:
                print(f"FAILURE: the current active variation of {feature_flag}: {feature_flag_current_variation} and dev-integration head of the workspace: ${commit_sha} don't match.")

    except Exception as e:
        print(f"Error: {e}")
        raise SystemExit(e)


def pretty_json(obj):
    return json.dumps(obj, sort_keys=True, indent=4)


#end: bulk import rules 

def check_secrets(filePath):
    try:
        connect_to_cluster()
    except Exception as e:
        print("could not connect to cluster, error", e)
        return
    v1 = client.CoreV1Api()
    with open(filePath, "r") as reader:
        print("reading secrets file to compare")
        jsonSecrets = json.load(reader)
        for key, value in jsonSecrets.items():
            for innerKey, innerValue in value.items():
                try:
                    secret = v1.read_namespaced_secret(innerKey, key)
                    print("Secret " + innerKey + " found in namespace " + key)
                except client.exceptions.ApiException:
                    print("Secret " + innerKey + " could not be found in namespace " + key)
                    return 0
                except Exception as e:
                    print("some other error", e)
                    return 0
    return 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="manipulate featureflags"
    )

    parser.add_argument(
        "featureflag",
        default='',
        help=(
            "the feature flag you wish to read or modify; e.g."
            " regional-geography-version"
        ),
    )

    # subcommands
    subcmd = parser.add_subparsers(
        title="subcommands",
        description="valid subcommands",
        help="use one of these subcommands",
        required=True,
        dest="subcommand",
    )



    # show_active_variation_cos_ffsld -- show_active_variation equivalent for cos remote resource
    p_show_active_variation_cos_ffsld = subcmd.add_parser(
        "show_active_variation_cos_ffsld",
        description="searches the rules for given rule_tag and prints the active variation, if it fails to find a matching rule, it prints fall through (default rule) variation",
        usage=(
            """
            Report Only.... (Example) Use command below to show active variation in a given rule_tag (mascd-1) and given ld environment (development) for rgw-image-version featureflag:
            python3 scripts/featureflags.py rgw-image-version show_active_variation_cos_ffsld 1.30.0-dev.8 git_token git_repo
            """
        ),
    )

    p_show_active_variation_cos_ffsld.add_argument(
        "feature_flag",
        help=(
            "feature flag under testing"
        ),
    )
    p_show_active_variation_cos_ffsld.add_argument(
        "feature_flag_current_variation",
        help=(
            "feature flag current vaiation"
        ),
    )
    p_show_active_variation_cos_ffsld.add_argument(
        "git_token",
        help=(
            "git token to connect to github"
        ),
    )
    p_show_active_variation_cos_ffsld.add_argument(
        "git_repo",
        help=(
            "git repo"
        ),
    )

    # validate_promotion with file - Similar to validate_promotion but the ld config comes as an input with a file
    p_validate_promotion_by_ld_with_file = subcmd.add_parser(
        "validate_promotion_by_ld_with_file",
        description="validate if the promote command ran correctly (Using a file as LD status) - Assumes that the cluster we want to test against is the current kubectl config",
        usage=("""
        Example: python3 featureflags.py --auth-token=api-<REDACTED> featureflag validate_promotion_by_ld development rias-ng-us-south-dal-dev73-etcd/bqt25v6d06o529j5h3fg
        """)
    )
    p_validate_promotion_by_ld_with_file.add_argument(
        "file_location",
        help=("Path to the file containing the desired configuration (Retrieved from ld)"),
    )
    p_validate_promotion_by_ld_with_file.add_argument(
        "cluster_type",
        help=(
             "The type of cluster"
            "(e.g genctl)"
        ),
    )

    # check_secrets - check if all the secrets are loaded into an environment
    p_check_secrets = subcmd.add_parser(
        "check_secrets", description="check if the secrets in the provided file are there in the cluster"
    )
    p_check_secrets.add_argument(
        "path_to_secrets",
        help=(
            "Complete path to the file that has the secrets listed in json format."
            "Typically it should be the the path to genesis_deploy_artifacts/hack/deploy/rias-ng/secrets.json."
            "You will need to log into the IBM cloud cli and set the context to the cluster that you want to check the secrets for before running the script."
            "The script will use the current active context to check for the secrets."
        ),
    )
    # end of subcommands

    # parse args and run the subcommand
    args = parser.parse_args()

    sub = args.subcommand

    if sub == "check_secrets":
        path_to_secrets = args.path_to_secrets.split('=')[1]
        ret = check_secrets(path_to_secrets)
        if ret == 1:
            print("All the secrets are there in the selected cluster")
        else:
            print("Some secrets are missing from the selected cluster")

    elif sub == "show_active_variation_cos_ffsld":
        show_active_variation_cos_ffsld(
                args.feature_flag,
                args.feature_flag_current_variation,
                args.git_token,
                args.git_repo
        )
    elif sub == "validate_promotion_by_ld_with_file":
        validate_promotion_func_desired_from_file(
            args.file_location,
            args.cluster_type
            
        )            
    elif sub == "validate_promotion_by_target_rule":
        validate_promotion_by_targetrule(args.source_context,args.target_context)