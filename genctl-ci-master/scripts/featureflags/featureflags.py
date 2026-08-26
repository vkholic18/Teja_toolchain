#! /usr/bin/env python3
## ==============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2021
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## ==============================================================================================
"""
This script talks to Launch Darkly API to add/update variations and rules for featureflags.
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

class LaunchDarkly:
    def __init__(self, base_url, featureflag, auth_token):
        self.base_url = base_url
        self.featureflag = featureflag
        self.url = urllib.parse.urljoin(base_url, featureflag)
        self.auth_token = auth_token

    def get_all(self):
        "return all of the URL as a python object"
        req = self.make_json_request()
        req.method = "GET"
        return self.json_req_to_obj(req)

    def get_feature_flags(self):
        url = self.url
        self.url = self.base_url
        params = '?offset=0&summary=false'
        self.url += params
        req = self.make_json_request()
        req.method = "GET"
        res = self.json_req_to_obj(req)
        self.url = url
        return res

    def get_variations(self):
        req = self.make_json_request()
        req.method = "GET"
        try:
            res = self.json_req_to_obj(req)
            return res["variations"]
        except KeyError:
            body = pretty_json(res)
            raise LaunchDarklyException(
                f"result did not contain variations: {body}"
            )

    def save_variations(self, variations):
        "save variations, and return new variations from the result"
        save_op = self.op_replace("/variations", variations)

        req = self.make_json_request()
        req.method = "PATCH"
        self.add_ops_to_request(req, save_op)

        try:
            res = self.json_req_to_obj(req)
            return res["variations"]
        except KeyError:
            body = pretty_json(res)
            raise LaunchDarklyException(
                f"result did not contain variations: {body}"
            )

    def save_rules(self, environment, rules):
        "save variations, and return new variations from the result"
        save_op = self.op_replace(
            "/environments/" + environment + "/rules", rules
        )

        req = self.make_json_request()
        req.method = "PATCH"
        self.add_ops_to_request(req, save_op)

        try:
            res = self.json_req_to_obj(req)
            return res["environments"][environment]["rules"]
        except KeyError:
            body = pretty_json(res)
            raise LaunchDarklyException(
                f"result did not contain rules: {body}"
            )

    def add_variation(self, new_value, replace_newest, remove_oldest):
        variations = self.get_variations()

        # The launchdarkly API will not allow a duplicate value in the variations list.
        # Search for the new value and record the index where we find it, if any.
        # Search from the end of the array under the theory that if we are encountering
        # a repeated hash, it is likely due to a multi-commit PR that includes a hash
        # already recorded recently.
        l = len(variations)
        i = l - 1
        updated = True
        already_index = -1
        while i >= 0:
            if variations[i]["value"] == new_value:
                already_index = i
                break
            i = i - 1

        # If the value has to be a replacement for the previous variation, that can
        # only be done if we happen to be replacing the previous value with itself...
        if replace_newest:
            if already_index >= 0 and already_index != l - 1:
                raise LaunchDarklyException(
                    f"cannot replace newest value, new value already present elsewhere in variations"
                )
            else:
                variations[l - 1] = dict(value=new_value)
                at_index = l - 1
        else:
            # If the value is not already present append it
            if already_index < 0:
                variations.append(dict(value=new_value))
                at_index = l
            else:
                at_index = already_index
                updated = False

        if remove_oldest and l > 0:
            del variations[0]
            # If we just deleted the already present value, add it back at the end
            if already_index == 0:
                variations.append(dict(value=new_value))
                at_index = l - 1

        return variations, at_index, updated

    def get_fallthrough(self, environment):
        "get the value of fallthrough"
        req = self.make_json_request()
        req.method = "GET"
        try:
            res = self.json_req_to_obj(req)
            return res["environments"][environment]["fallthrough"]["variation"]
        except KeyError as e:
            body = pretty_json(res)
            raise LaunchDarklyException(
                f"result did not contain key '{e}': {body}"
            )

    def save_fallthrough(self, environment, fallthrough):
        "sets the value of fallthrough; returns the new value"
        save_op = self.op_replace(
            "/environments/" + environment + "/fallthrough/variation", fallthrough
        )

        req = self.make_json_request()
        req.method = "PATCH"
        self.add_ops_to_request(req, save_op)

        try:
            res = self.json_req_to_obj(req)
            return res["environments"][environment]["fallthrough"]["variation"]
        except KeyError as e:
            raise LaunchDarklyException(f"result does not contain key: {e}")

    def save_rule_variation(self, environment, variation, rule):
        "sets the value of variation into rule returns the new value"
        save_op = self.op_replace(
            "/environments/" + environment + "/rules/" + str(rule) + "/variation", variation
        )
        req = self.make_json_request()
        req.method = "PATCH"
        self.add_ops_to_request(req, save_op)

        try:
            res = self.json_req_to_obj(req)
            return res["environments"][environment]["rules"][rule]["variation"]
        except KeyError as e:
            raise LaunchDarklyException(f"result does not contain key: {e}")

    def search_rule_by_tag(self, rule_environment, rule_tag):
        "set the value of rule with a given tag"
        rule_inx = -1
        try:
            feature_flag_dict = self.get_all()
            rules = feature_flag_dict["environments"][rule_environment]["rules"]
            for rule in rules:
                rule_inx += 1
                clauses = rule["clauses"]
                if len(clauses) > 1:
                    print(f"Skip  the rule: {rule['description']} which contains more than one clause and continue as a workaround for CD-1679")
                    continue
                for clause in clauses:
                    values = clause["values"]
                    if rule_tag in values:
                        return rule_inx
            # rule not found
            return -1
        except KeyError as e:
            raise LaunchDarklyException(f"result does not contain key: {e}")

    def get_rule_variation(self, rule_environment, rule_inx):
        "get rule variation by rule index"
        try:
            feature_flag_dict = self.get_all()
            rule = feature_flag_dict["environments"][rule_environment]["rules"][rule_inx]
            return rule["variation"]
        except KeyError as e:
            raise LaunchDarklyException(f"result does not contain key: {e}")

    def get_feature_flag_git_repo(self):
        "get feature flag related git repo"
        try:
            feature_flag_dict = self.get_all()
            repos = feature_flag_dict["customProperties"]["git_repo"]["value"]
            return repos[0]
        except KeyError as e:
            raise LaunchDarklyException(f"result does not contain key: {e}")

    def search_rule_by_tag_wo_call(self, rules, rule_environment, rule_tag):
        "set the value of rule with a given tag"
        rule_inx = -1
        try:
            for rule in rules:
                rule_inx += 1
                clauses = rule["clauses"]
                for clause in clauses:
                    values = clause["values"]
                    if rule_tag in values:
                        return rule_inx
            # rule not found
            return -1
        except KeyError as e:
            raise LaunchDarklyException(f"result does not contain key: {e}")

    def json_req_to_obj(self, req):
        "take a request, parse the json, return the result"
        
        # Set the remaining attempts
        attempts_done = 0
        max_attempts = 1000

        while attempts_done < max_attempts:
            try:
                with urllib.request.urlopen(req) as res:
                    body = res.read()
                    return json.loads(body)
            except urllib.error.URLError as e:
                # if responce hit API_RATE_LIMIT_ERROR (429) error
                # wait for limit reset and retry the request
                # https://apidocs.launchdarkly.com/#section/Rate-limiting
                # https://jiracloud.swg.usma.ibm.com:8443/browse/CIGC-4122
                if  e.code == API_RATE_LIMIT_ERROR:
                    print("LD api request got API rate limit exception {0}" .format(API_RATE_LIMIT_ERROR))
                    headers=e.headers;
                    limit_reset=headers["X-Ratelimit-Reset"]
                    print("X-Ratelimit-Reset {0}" .format(limit_reset))
                    route_limit=headers["X-Ratelimit-Route-Limit"]
                    print("X-Ratelimit-Route-Limit {0}" .format(route_limit))
                    route_remaining=headers["X-Ratelimit-Route-Remaining"]
                    print("X-Ratelimit-Route-Remaining {0}" .format(route_remaining))
                    print("Retrying request ...")

                    if limit_reset != None:
                        time.sleep(self.wait_for_api_request(limit_reset))
                    
                    attempts_done += 1
                    # If we came to the maximum, raise error
                    if attempts_done == max_attempts:
                        raise LaunchDarklyException(
                            f"{req.method} on {self.url} failed",
                            reserror=e.read().decode(),
                            reqbody=req.data,
                        )
                    else:
                        print(f"Will do another attempt; up to now done {attempts_done} attempts")
                else:
                    raise e
            except json.JSONDecodeError:
                raise LaunchDarklyException(f"could not decode json: {body}")

    def wait_for_api_request(self, epoch):
        #get unix epoch from current time
        current_epoch_time = int(time.time()) * 1000
        wait_for = int(epoch) - current_epoch_time
        #convert delta to seconds 
        wait_for_sec = int(wait_for/1000) + 1
        print("Waiting for API ratelimit reset for {0} sec" .format(wait_for_sec))
        return wait_for_sec

    def add_ops_to_request(self, req, first, *rest):
        "take http request and one or more ops; add ops to request"
        # don't use list(first); it does weird things with dictionaries
        ops = [first]
        ops.extend(rest)
        req.data = bytearray(json.dumps(ops), "utf-8")

    def op_replace(self, path, value):
        "create a replace 'op' for LaunchDarkly"
        return dict(op="replace", path=path, value=value)

    def make_json_request(self):
        "make a request object suitable for json"
        headers = self.make_headers()
        req = urllib.request.Request(self.url, headers=headers)
        return req

    def make_headers(self, content_type="application/json"):
        return {
            "Authorization": self.auth_token,
            "Content-Type": content_type,
        }


class LaunchDarklyException(Exception):
    def __init__(self, message, reserror=None, reqbody=None):
        self.message = message
        self.reserror = reserror
        self.reqbody = reqbody

        if reserror:
            message = f"{message}\nError: {reserror}"
        if reqbody:
            message = f"{message}\nRequest body follows:\n{reqbody}"
        super().__init__(message)

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

def get_desired_deployment_versions(ld, env,clustername):
    "gets a dictionary of version:ld-flag"
    dict = {}
    json_res = ld.get_feature_flags()
    try:
        for item in json_res["items"]:
            flag = item["key"]
            match = re.match(r'^[a-zA-Z-]*-image-version$', flag)
            match_globals = re.match(r'^[a-zA-Z-]*-globals-version$', flag)
            if match or match_globals or flag == "rias-inception-version":
                if flag == "rias-inception-version":
                    print("found rias-inception-version")
                rules = item["environments"][env]["rules"]
                versionFound = False
                for rule in rules:
                    if len(rule["clauses"]) > 1:
                        print(f"Skip  the rule: {rule['description']} which contains more than one clause and continue as a workaround for CD-1679")
                        continue
                    for c in rule["clauses"]:
                        for v in c["values"]:
                            #print(f"Attribute: { c['attribute'] } ----- Rule tags: {v} ")
                            if v == clustername:
                                version = item["variations"][rule["variation"]]["value"]
                                versionFound = True
                                print("Feature-flag:", flag, "Desired-version:", version)
                                dict[flag]=version

                if not versionFound:
                    #for testing FF the desired version must be from the target rule and not default
                    if ld.featureflag == flag:
                        dict[flag]= "not_found"
                    else:
                        # No rule found for the cluster, find the fall-through value as our version
                        varsum = item["environments"][env]["_summary"]["variations"]
                        for vars in varsum:
                            try:
                                isdflt = item["environments"][env]["_summary"]["variations"][vars]["isFallthrough"]
                            except:
                                continue
                            if isdflt:
                                version = item["variations"][int(vars)]["value"]
                                print("Feature-flag:", flag, "Desired-version:", version)
                                dict[flag]=version
                                break
    except KeyError as ke:
        print("Property name {0} not found in LD json response".format(ke))
    except Exception as e:
        print("Error occurred while getting the feature flags data.\nError:",e)
    return dict

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

def validate_promotion_func(ld, environment, cluster_name, cluster_type):
    "validates if the promote command ran correctly"
    # Get from launchdarkly
    desired_deployments  = get_desired_deployment_versions(ld, environment, cluster_name)
    
    # Get from cluster (By default use current context)
    current_deployments = get_current_deployment_versions(desired_deployments, cluster_type=cluster_type)
    
    # Compare
    check_status(current_deployments, desired_deployments)

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

def get_desired_deployment_versions_file(ld, environment,cluster_name):
    # This is used for genctl
    "gets the desired deployments versions and dumps then into a file"
    #config.load_kube_config(context=context)
    #cluster_name = get_cluster_name_from_context(context)
    desired_deployments  = get_desired_deployment_versions(ld,environment, cluster_name)
    with open('desired_deployment_versions.json', 'w') as outfile:
        json.dump(desired_deployments, outfile)



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

def show_all(ld):
    print(pretty_json(ld.get_all()))

def get_feature_flags_all(ld):
    print(pretty_json(ld.get_feature_flags()))

def set_default_variation(ld, environment, report_only):
    "sets all the featureflags in the given environment to point to default on variation."
    feature_flags_dict = ld.get_feature_flags()
    items = feature_flags_dict["items"]
    if report_only == 'True':
        print("Not Promoting..... This is only the report!")
    print("List of featureflags that will change after setting to default:")
    report = {"idx": ["keys", "before_change", "after_change"]}
    idx = 1
    for item in items:
        key = item["key"]
        match = re.match(r'^[a-zA-Z-]*-image-version$', key)
        match_globals = re.match(r'^[a-zA-Z-]*-globals-version$', key)
        if match or match_globals or key == "rias-inception-version":
            variations = item["variations"]
            before_fall_through = item["environments"][environment]["fallthrough"]["variation"]
            after_fall_through = item["defaults"]["onVariation"]
            if before_fall_through != after_fall_through:
                s = [key, variations[before_fall_through]['value'], variations[after_fall_through]['value']]
                report.update({idx: s})
                idx += 1
                if report_only == 'False':
                    change_url(ld, key)
                    ld.save_fallthrough(environment, after_fall_through)
    printReport(report, "set_to_defaults_report.txt")

def promote(ld, source_environment, target_environment, report_only):
    "promotes all the featureflags default rule from target environment to source environment"

    # get full list of all the featureflags
    feature_flags_dict = ld.get_feature_flags()
    items = feature_flags_dict["items"]

    if report_only == 'True':
        print("Not Promoting..... This is only the report!")
    print("List of featureflags that will change after the promotion:")

    # intialize report dictionary
    report = {"idx": ["keys", "before_promotion", "after_promotion"]}
    idx = 1

    for item in items:
        defaults = item["defaults"]
        key = item["key"]
        # only want to promote feature flags rias-inception-version, rias-globals-version, and the ones that end in *-image-version
        match = re.match(r'^[a-zA-Z-]*-image-version$', key)
        match_globals = re.match(r'^[a-zA-Z-]*-globals-version$', key)
        if match or match_globals or key == "rias-inception-version":
            # parse environments and extracts variations, source_fall_through, and target_fall_through
            variations = item["variations"]
            _, source_fall_through, _ = get_var_and_rules(ld, item["environments"][source_environment], defaults, key)
            _, target_fall_through, _ = get_var_and_rules(ld, item["environments"][target_environment], defaults, key)
            if source_fall_through != target_fall_through:
                s = {idx: [key, variations[target_fall_through]['value'], variations[source_fall_through]['value']]}
                # update the report dictionary
                report.update(s)
                idx += 1
                if report_only == 'False':
                    # make the api call to save the target_environment's fall through variation (default rule) using source_fall_through
                    change_url(ld, key)
                    ld.save_fallthrough(target_environment, source_fall_through)

    # prints the report
    printReport(report, 'promote_report.txt')

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

def roll_to_default_func(ld, rule_environment, rule_tag, base_featureflag):
    "roll the hash for all the featureflags that use the same rule_tag as base_featureflag to use a default rule hash in a target rule "
    feature_flags_dict = ld.get_feature_flags()
    items = feature_flags_dict["items"]
    environment_rolled_to_default = False
    for item in items:
        key = item["key"]
        print(f"############################################")
        print(f"Feature flag: {key} ")
        match = re.match(r'^[a-zA-Z-]*-image-version$', key)
        match_globals = re.match(r'^[a-zA-Z-]*-globals-version$', key)
        if key == base_featureflag:
            print(f"Skip {base_featureflag} feature")
            continue
        if match or match_globals:
            item_ld = LaunchDarkly(args.base_url, key, args.auth_token)
            rule_idx = item_ld.search_rule_by_tag(rule_environment, rule_tag)
            if rule_idx > -1:
                print(f"Rule with tag: {rule_tag} was found in environment: {rule_environment} for Feature Flag: {item_ld.featureflag}")
                which = item_ld.get_fallthrough(rule_environment)
                print(f"Feature Flag: {item_ld.featureflag} has default variable index: {which}")
                rule_variation = item_ld.get_rule_variation(rule_environment, rule_idx)
                print(f"Rule with tag: {rule_tag} has variation index:{rule_variation}")
                if which != rule_variation:
                    res = item_ld.save_rule_variation(rule_environment, which, rule_idx)
                    environment_rolled_to_default = True
                    print(f"Variation: {which} is now used in rule: {rule_idx} in environment: {rule_environment} for Feature Flag: {item_ld.featureflag}")
                else:
                    print(f"Default variation already set for rule with tag: {rule_tag} for Feature Flag: {item_ld.featureflag}. Continue ... ")
            else:
                print(f"Tag: {rule_tag} was not found in rules for Feature Flag: {item_ld.featureflag} in the environment: {rule_environment} ")

    if environment_rolled_to_default:
        #TODO remove when RR->RRS3 razee transion is done
        print(f"{rule_tag} is a shared DEV environment. Wait for Razee to handlean issue described CIGC-7073 with transition PCW from RRS3 to RR")
        time.sleep(600)

# returng git tag by coressponded to the commit sha. If tag does not exist return sha
def get_git_tag_by_commit_sha(github_repo, commit_sha):
    tags = github_repo.get_tags()
    for tag in tags:
        if tag.commit.sha == commit_sha:
            print(f"SUCCESS: Commit {commit_sha} has corresponded tag {tag}")
            return tag.name

    print(f"Could not find corresponded tag for commit {commit_sha}.")
    return commit_sha

def rollback_to_dev_func(ld, rule_environment, rule_tag, base_featureflag, git_token):
    "restore all the featureflags that use the same rule_tag as base_featureflag to use a dev-integration hash a target rule "
    feature_flags_dict = ld.get_feature_flags()
    items = feature_flags_dict["items"]

    github = Github(base_url=GITHUB_BASE_URL, login_or_token=git_token)
    for item in items:
        key = item["key"]
        print(f"############################################")
        print(f"Feature flag: {key} ")
        #match all feature flags with -image-version suffix
        match = re.match(r'^[a-zA-Z-]*-image-version$', key)
        match_globals = re.match(r'^[a-zA-Z-]*-globals-version$', key)
        if key == base_featureflag:
            print(f"Skip {base_featureflag} feature")
            continue
        if match or match_globals or key == "rias-inception-version":
            item_ld = LaunchDarkly(args.base_url, key, args.auth_token)
            rule_idx = item_ld.search_rule_by_tag(rule_environment, rule_tag)
            if rule_idx == -1:
                print(f"Tag: {rule_tag} was not found in rules for Feature Flag: {item_ld.featureflag} in the environment: {rule_environment} ")
                continue
            git_repo = item_ld.get_feature_flag_git_repo()

            try:
                github_repo = github.get_repo(git_repo)
                dev_integration_branch = github_repo.get_branch('dev-integration')
                commit_sha = dev_integration_branch.commit.sha
                branch_version = get_git_tag_by_commit_sha(github_repo, commit_sha)
                parent_commit_sha = dev_integration_branch.commit.parents[0].sha
                parent_branch_version = get_git_tag_by_commit_sha(github_repo, parent_commit_sha)
                print(f"Feature flag: {item_ld.featureflag} from {git_repo} on dev-integration branch has commit version: {branch_version}")
                print(f"Feature flag: {item_ld.featureflag} from {git_repo} on dev-integration branch has parent commit hash: {parent_branch_version}")
            except Exception as e:
                print(f"Error: {e}")
                raise SystemExit(e)

            variations = item_ld.get_variations()
            variation_index = 0
            variation_found_and_set = False
            for variation in variations:
                variation_value = variation["value"]
                if variation_value == branch_version:
                    res = item_ld.save_rule_variation(rule_environment, variation_index, rule_idx)
                    variation_found_and_set = True
                    print(f"Rule with tag {rule_tag} was updated to use variation {variation_value} in environment: {rule_environment} for Feature Flag: {item_ld.featureflag}")
                    break
                variation_index += 1

            if variation_found_and_set:
                # continue to the next feature flag
                continue
            else:
                variation_index = 0
                variation_found_and_set = False
                for variation in variations:
                    variation_value = variation["value"]
                    if variation_value == parent_branch_version:
                        res = item_ld.save_rule_variation(rule_environment, variation_index, rule_idx)
                        variation_found_and_set = True
                        print(f"Rulewith tag {rule_tag} was updated to use variation {variation_value} in environment: {rule_environment} for Feature Flag: {item_ld.featureflag}")
                        break
                    variation_index += 1
                if variation_found_and_set:
                    # continue to the next feature flag
                    continue
                else:
                    print(f"Could not find variation to rollback for rule: {rule_idx} in environment: {rule_environment} for Feature Flag: {item_ld.featureflag}")

def update_fall_through(ld, environment, idx):
    ld.save_fallthrough(environment, idx)

def get_var_and_rules(ld, environment_json, defaults, key):
    "parses the environment_json passed in and returns offVariation, fallthrough variation and rules."
    fallthrough_var = environment_json["fallthrough"]["variation"]
    off_var = environment_json["offVariation"]
    rules = environment_json["rules"]
    return (off_var, fallthrough_var, rules)

def rule_promote(ld, environment, source_region, target_region, report_only):
    "adds/updates target_region rule's variation using source_region rule's variation"

    # initialize the report
    report = {"idx": ["keys", "before_rule_promotion", "after_rule_promotion", "rule_upated_or_added"]}
    idx = 1
    if source_region == target_region:
        raise LaunchDarklyException(f"source and target regions must be different to promote")

    # api call to get details of the featureflag and parse that to get variations and rules
    feature_flags_dict = ld.get_all()
    variations = feature_flags_dict["variations"]
    rules = feature_flags_dict["environments"][environment]["rules"]

    # get the source rule's index
    source_rule_idx = ld.search_rule_by_tag(environment, source_region)
    if source_rule_idx == -1:
        raise LaunchDarklyException(f"rule with this {source_region} tag/region not found")

    # use the source rule index to get the rule and its variation
    source_var = rules[source_rule_idx]["variation"]

    # get the target rule's index
    target_rule_idx = ld.search_rule_by_tag(environment, target_region)
    if target_rule_idx != -1:
        target_var = rules[target_rule_idx]["variation"]
        # if a rule exists with this target_region update the rule to use source_rule's variation
        report.update({idx: [ld.featureflag, variations[target_var]['value'], variations[source_var]['value'], "updated"]})
        if report_only == 'False':
            # make the api call to save the target_region's rule using source_region rule's variation
            print('Promoting.... This is not a dry run!')
            _ = ld.save_rule_variation(environment, source_var, target_rule_idx)
            print(f"updated target_region with source_region's rule variation {source_var} from {target_var}")
        else:
            # dry run
            print('Not Promoting.... This is a dry run!')
            print(f"will update target_region with source_region's rule variation {source_var} from {target_var} upon rule promotion")
    else:
        # if a rule doesnt exist with this target_region, then add a new rule to featureflag with target_region using source_rule's variation
        report.update({idx: [ld.featureflag, "", variations[source_var]['value'], "added"]})
        if report_only == 'False':
            # make the api call to add the target_region's rule using source_region rule's variation
            print('Promoting.... This is not a dry run!')
            resulting_rules = add_rule(ld, rules, environment, source_rule_idx, target_region, report_only)
            print(f"rule with this {target_region} tag/region not found thus added one using source_region's rule variation {source_var} and clauses")
            print(pretty_json(resulting_rules))
        else:
            # dry run
            print('Not Promoting.... This is a dry run!')
            print(f"rule with this {target_region} tag/region not found thus will be added using source_region's rule variation {source_var} and clauses upon promotion")

    # prints the report
    printReport(report, "rule_promote_report.txt")

def add_rule(ld, rules, environment, source_rule_idx, target_region, report_only):
    """
    adds the rule to the list of given rules on launch darkly in the given environment using target_region as
    the value and source rule's variation as the variation;

    returns the list of rules after appending the new rule
    """

    # get the source rule's variation using given source_rule_idx
    source = rules[source_rule_idx]
    variation = source["variation"]

    # use all the values from source rule except clauses.values
    # use clauses.values from the given target_region
    new_rule = {
        "clauses": [
            {
                "attribute": source["clauses"][0]["attribute"],
                "negate": source["clauses"][0]["negate"],
                "op": source["clauses"][0]["op"],
                "values": [target_region]
            }
        ],
        "variation": variation
    }

    # append the new rule to the list
    rules.append(new_rule)
    if report_only == 'False':
        # make the api call to save the updated list rules to launch darkly
        print('Promoting.... This is not a dry run!')
        resulting_rules = ld.save_rules(environment, rules)
        print(f"New rule created with target_region tag using source_region's rule variation {variation} and clauses in {environment} environment")
        return resulting_rules
    else:
        # dry run
        print('Not Promoting.... This is a dry run!')
        print(f"New rule will be created with target_region tag using source_region's rule variation {variation} and clauses in {environment} environment upon rule promotion")
        return rules

def add_rule_accross_envs(ld, source_rules, target_rules, environment, source_rule_idx, target_region, report_only):
    """
    adds the rule to the list of given target_rules on launch darkly in the given environment using target_region as
    the value and source rule's variation as the variation;

    returns the updated list of target_rules after appending the new rule
    """

    # get the source rule's variation using given source_rule_idx

    # use all the values from source rule except clauses.values
    # use clauses.values from the given target_region
    source = source_rules[source_rule_idx]
    variation = source["variation"]

    # use all the values from source rule except clauses.values
    # use clauses.values from the given target_region
    new_rule = {
        "clauses": [
            {
                "attribute": source["clauses"][0]["attribute"],
                "negate": source["clauses"][0]["negate"],
                "op": source["clauses"][0]["op"],
                "values": [target_region]
            }
        ],
        "variation": variation
    }

    # append the new rule to the target_rules list
    target_rules.append(new_rule)
    if report_only == 'False':
        # make the api call to save the updated list of target_rules to launch darkly
        print('Promoting.... This is not a dry run!')
        resulting_rules = ld.save_rules(environment, target_rules)
        print(f"New rule created with target_region tag using source_region's rule variation {variation} and clauses in {environment} environment")
        return resulting_rules
    else:
        # dry run
        print('Not Promoting.... This is a dry run!')
        print(f"New rule will be created with target_region tag using source_region's rule variation {variation} and clauses in {environment} environment upon rule promotion")
        return target_rules

def add_rule_use_variation(ld, rules, environment, variation, target_region, report_only):
    """
    adds the rule to the list of given rules on launch darkly in the given environment using target_region as
    the value and given variation as the variation;

    returns the list of rules after appending the new rule
    """

    # use all the default values of rule except clauses.values
    # use clauses.values from the given target_region
    new_rule = {
        "clauses": [
            {
                "attribute": "region",
                "negate": False,
                "op": "in",
                "values": [target_region]
            }
        ],
        "variation": variation
    }

    # append the new rule to the list
    rules.append(new_rule)
    if report_only == 'False':
        # make the api call to save the updated list of rules to launch darkly
        print('Promoting.... This is not a dry run!')
        resulting_rules = ld.save_rules(environment, rules)
        print(f"New rule created with target_region tag using source_region's rule variation {variation} and clauses in {environment} environment")
        return resulting_rules
    else:
        # dry run
        print('Not Promoting.... This is a dry run!')
        print(f"New rule will be created with target_region tag using source_region's rule variation {variation} and clauses in {environment} environment upon rule promotion")
        return rules

def change_url(ld, key):
    "changes the ld.url to point to a given key (featureflag) in launch darkly"
    ld.featureflag = key
    ld.base_url = "https://app.launchdarkly.com/api/v2/flags/vpc-ci/"
    ld.url = urllib.parse.urljoin(ld.base_url, ld.featureflag)

def rule_promote_accross_ld_envs(ld, environments, variations, defaults, key, source_environment, target_environment, source_region, target_region, report_only):
    """
    adds/updates target_region rule's variation using source_region rule's variation;
    returns the dictionary used to print report.
    """

    # parses the source and target environments to extract source and target rules
    _, _, source_rules = get_var_and_rules(ld, environments[source_environment], defaults, key)
    _, _, target_rules = get_var_and_rules(ld, environments[target_environment], defaults, key)

    # get the source rule's index
    source_rule_idx = ld.search_rule_by_tag_wo_call(source_rules, source_environment, source_region)
    if source_rule_idx == -1:
        raise LaunchDarklyException(f"rule with this {source_region} tag/region not found")

    # use the source rule index to get the rule and its variation
    source_var = source_rules[source_rule_idx]["variation"]

    # get the target rule's index
    target_rule_idx = ld.search_rule_by_tag_wo_call(target_rules, target_environment, target_region)
    if target_rule_idx != -1:
        target_var = target_rules[target_rule_idx]["variation"]
        # if a rule exists with this target_region update the rule to use source_rule's variation
        if target_var != source_var:
            s = [key, variations[target_var]['value'], variations[source_var]['value'], "updated"]
            if report_only == 'False':
                # make the api call to save the target_region's rule using source_region rule's variation
                print('Promoting.... This is not a dry run!')
                change_url(ld, key)
                _ = ld.save_rule_variation(target_environment, source_var, target_rule_idx)
                print(f"updated {target_region}'s rule in {target_environment} using {source_region}'s rule variation {source_var} in {source_environment} from {target_var}")

            else:
                # dry run
                print('Not Promoting.... This is a dry run!')
                print(f"will update {target_region}'s rule in {target_environment} with {source_region}'s rule variation {source_var} in {source_environment} from {target_var} upon rule promotion")
        else:
            # target_region's rule variation is already same as source_region's rule variation
            print(f"Not Promoting.... {target_region} and {source_region} are both pointing to the same {source_var}")
            return None
    else:
        # if a rule doesnt exist with this target_region, then add a new rule to featureflag with target_region using source_rule's variation
        s = [key, "", variations[source_var]['value'], "added"]
        if report_only == 'False':
            # make the api call to add the target_region's rule using source_region rule's variation
            print('Promoting.... This is not a dry run!')
            change_url(ld, key)
            resulting_rules = add_rule_accross_envs(ld, source_rules, target_rules, target_environment, source_rule_idx, target_region, report_only)
            print(f"rule with this {target_region} tag/region not found in {target_environment} thus added one using {source_region}'s rule variation {source_var} in {source_environment} and clauses")
            print(pretty_json(resulting_rules))

        else:
            # dry run
            print('Not Promoting.... This is a dry run!')
            print(f"rule with this {target_region} tag/region not found in {target_environment} thus will be added using {source_region}'s rule variation {source_var} in {source_environment} and clauses upon promotion")
    return s

def rule_promote_to_fall_through_across_ld_envs(ld, environments, variations, defaults, key, source_environment, target_environment, target_region, report_only):
    """
    adds/updates target_region rule's variation using source_environmnet's fallthrough variation (default rule);
    returns the dictionary used to print report.
    """

    # parses the source and target environments to extract source_fall_through and target_rules
    _, source_fall_through, _ = get_var_and_rules(ld, environments[source_environment], defaults, key)
    _, _, target_rules = get_var_and_rules(ld, environments[target_environment], defaults, key)

    # get the target rule's index
    target_rule_idx = ld.search_rule_by_tag_wo_call(target_rules, target_environment, target_region)
    if target_rule_idx != -1:
        target_var = target_rules[target_rule_idx]["variation"]
        # if a rule exists with this target_region update the rule to use source_rule's variation
        if target_var != source_fall_through:
            s = [key, variations[target_var]['value'], variations[source_fall_through]['value'], "updated"]
            if report_only == 'False':
                # make the api call to save the target_region's rule using source environment's fall through variation (default rule)
                print('Promoting.... This is not a dry run!')
                change_url(ld, key)
                _ = ld.save_rule_variation(target_environment, source_fall_through, target_rule_idx)
                print(f"updated {target_region}'s rule in {target_environment} using {source_environment}'s fall through variation {source_fall_through} from {target_var}")

            else:
                # dry run
                print('Not Promoting.... This is a dry run!')
                print(f"will update {target_region}'s rule in {target_environment} using {source_environment}'s fall through variation {source_fall_through} from {target_var} upon rule promotion")
        else:
            # target_region's rule variation is already same as source environment's fallthrough variation
            print(f"Not Promoting.... {target_region}'s rule in {target_environment} is already pointing to the {source_environment}'s fall through variation {source_fall_through}")
            return None
    else:
        # if a rule doesnt exist with this target_region, then add a new rule to featureflag with target_region using source_rule's variation
        s = [key, "", variations[source_fall_through]['value'], "added"]
        if report_only == 'False':
            # make the api call to add the target_region's rule using source environment's fallthrough rule's variation
            print('Promoting.... This is not a dry run!')
            change_url(ld, key)
            resulting_rules = add_rule_use_variation(ld, target_rules, target_environment, source_fall_through, target_region, report_only)
            print(f"rule with this {target_region} tag/region not found in {target_environment} thus added one using {source_environment}'s fall through variation {source_fall_through}")
            print(pretty_json(resulting_rules))

        else:
            # dry run
            print('Not Promoting.... This is a dry run!')
            print(f"rule with this {target_region} tag/region not found in {target_environment} thus will be added using {source_environment}'s fall through variation {source_fall_through} upon promotion")
    return s


def rule_promote_accross_ld_envs_all(ld, source_environment, target_environment, source_region, target_region, report_only):
    """
    adds/updates target_region rule's variation using source_region rule's variation
    if source_region is passed in else uses source_environmnet's fallthrough variation
    (default rule). Can be ran for one featureflag (if passed in) or for all the featureflags (if not passed in).;
    returns the dictionary used to print report.
    """

    # check to see if source and target regions are different
    if source_region:
        if source_region == target_region:
            raise LaunchDarklyException(f"source and target regions must be different to promote")

    if report_only == 'True':
        print("Not Promoting..... This is only the report!")

    # initialize the report
    report = {"idx": ["keys", "before_rule_promotion", "after_rule_promotion", "rule_upated_or_added"]}
    idx = 1

    # check to see if featureflag is passed in.
    # if not passed in then perform rule promotion for all featureflags
    if args.featureflag == "":
        # get full list of all the featureflags
        feature_flags_dict = ld.get_feature_flags()
        items = feature_flags_dict["items"]
        print("List of featureflags that will change after the promotion:")
        for item in items:
            defaults = item["defaults"]
            key = item["key"]
            variations = item["variations"]
            # only want to promote feature flags rias-inception-version, rias-globals-version, and the ones that end in *-image-version
            match = re.match(r'^[a-zA-Z-]*-image-version$', key)
            match_globals = re.match(r'^[a-zA-Z-]*-globals-version$', key)
            if match or match_globals or key == "rias-inception-version":
                environments = item["environments"]
                # if source_region is passed in use source_region rule's variation
                if source_region:
                    s = rule_promote_accross_ld_envs(ld, environments, variations, defaults, key, source_environment, target_environment, source_region, target_region, report_only)

                # else use source environment's fall through variation (default rule)
                else:
                    s = rule_promote_to_fall_through_across_ld_envs(ld, environments, variations, defaults, key, source_environment, target_environment, target_region, report_only)

                # update the report dictionary
                if s:
                    report.update({idx: s})
                    idx += 1

    # else perform rule promotion for one featureflag
    else:
        # get the specified featureflag and extract the environment and variations
        feature_flags_dict = ld.get_all()
        key = ld.featureflag
        environments = feature_flags_dict["environments"]
        variations = feature_flags_dict["variations"]
        defaults = dict() # TODO get rid of it later, not being used

        # if source_region is passed in use source_region rule's variation
        if source_region:
            s = rule_promote_accross_ld_envs(ld, environments, variations, defaults, key, source_environment, target_environment, source_region, target_region, report_only)

        # else use source environment's fall through variation (default rule)
        else:
            s = rule_promote_to_fall_through_across_ld_envs(ld, environments, variations, defaults, key, source_environment, target_environment, target_region, report_only)

        # update the report dictionary
        if s:
            report.update({idx: s})

    # prints the report
    printReport(report, "rule_promote_accross_envs_report.txt")

def show_variations(ld):
    "get all the variations and print the result"
    variations = ld.get_variations()
    print(pretty_json(variations))

def set_value(ld, new_value, replace_newest, remove_oldest, environment, use_new_value):
    """
    sets the value of fall through variation in the given environment to given new_value
    using the given replacement policy
    """
    try:
        variations, idx, updated = ld.add_variation(new_value, replace_newest, remove_oldest)
    except LaunchDarklyException as e:
        raise e

    if updated:
        variations = ld.save_variations(variations)

    if args.use:
        res = ld.save_fallthrough(environment, idx)

    if updated:
        print(f"New variation created in environment: {environment} for Feature Flag: {ld.featureflag}")
    else:
        print(f"Variation already found in environment: {environment} for Feature Flag: {ld.featureflag}")

    if args.use:
        print(f"{new_value} now selected")

def set_value_and_use_in_rule(ld, new_value, replace_newest, remove_oldest, rule_environment, rule_tag):
    """
    sets the value of fall through variation in the given environment to given new_value
    using the given replacement policy and also updates the rule's variation to use that new value
    """
    try:
        variations, idx, updated = ld.add_variation(new_value, replace_newest, remove_oldest)
    except LaunchDarklyException as e:
        raise e

    if updated:
        variations = ld.save_variations(variations)
        print(f"Variation: {idx} with value: {new_value} was created in environment: {rule_environment} for Feature Flag: {ld.featureflag}.")
    else:
        print(f"Variation: {idx} with value: {new_value} was found in environment: {rule_environment} for Feature Flag: {ld.featureflag}.")

    rule_idx = ld.search_rule_by_tag(rule_environment, rule_tag)
    if rule_idx > -1:
        res = ld.save_rule_variation(rule_environment, idx, rule_idx)
        print(f"Variation: {idx} is now used in rule: {rule_idx} in environment: {rule_environment} for Feature Flag: {ld.featureflag}")
    else:
        print(f"Tag: {rule_tag} was not found in the environment: {rule_environment} for Feature Flag: {ld.featureflag}")
        exit(1)

def use_value(ld, rule_environment, which):
    "sets the value of fall through variation in the given environment to given variation (which)"
    variations = ld.get_variations()
    res = ld.save_fallthrough(rule_environment, which)
    print(f"using variation {which}: {variations[res]}")

def use_value_in_rule(ld, which, rule_environment, rule_tag):
    """
    sets the value of fall through variation in the given environment to given variation (which)
    and also updates the rule's variation to use that given variation (which)
    """
    rule_idx = ld.search_rule_by_tag(rule_environment, rule_tag)
    if rule_idx > -1:
        res = ld.save_rule_variation(rule_environment, which, rule_idx)
        print(f"Rule: {rule_idx} was updated to use variation {which} in environment: {rule_environment} for Feature Flag: {ld.featureflag}")
    else:
        print(f"Tag: {rule_tag} was not found in the environment: {rule_environment} for Feature Flag: {ld.featureflag}")

def use_default_value_in_rule(ld, rule_environment, rule_tag):
    """
    updates the rule's variation to use the default variation
    """
    rule_idx = ld.search_rule_by_tag(rule_environment, rule_tag)
    if rule_idx > -1:
        which = ld.get_fallthrough(rule_environment)
        res = ld.save_rule_variation(rule_environment, which, rule_idx)
        print(f"Rule: {rule_idx} was updated to use variation {which} in environment: {rule_environment} for Feature Flag: {ld.featureflag}")
    else:
        print(f"Tag: {rule_tag} was not found in the environment: {rule_environment} for Feature Flag: {ld.featureflag}")

def rmvars(ld, variation_ids, dry_run):
    "removes the given variation_ids from variations dictionary on launch darkly"
    def remover(v):
        return v["_id"] not in variation_ids

    variations = ld.get_variations()
    variations = list(filter(remover, variations))
    if not dry_run:
        variations = ld.save_variations(variations)
    print(pretty_json(variations))


def which(ld, variation_environment):
    "prints the fall through variation (default rule) of the given variation_environment"
    variations = ld.get_variations()
    which = ld.get_fallthrough(variation_environment)
    print(f"active index: {which}")
    print(f"value: {variations[which]}")

def show_active_variation(ld, variation_environment, rule_tag, git_token):
    "searches the rules for given rule_tag and prints the active variation, if it fails to find a matching rule, it prints fall through (default rule) variation"
    variations = ld.get_variations()
    feature_flag_dict = ld.get_all()
    rules = feature_flag_dict["environments"][variation_environment]["rules"]
    rule_idx = ld.search_rule_by_tag(variation_environment, rule_tag)
    if rule_idx == -1:
        which = ld.get_fallthrough(variation_environment)
    else:
        which = rules[rule_idx]["variation"]
    github = Github(base_url=GITHUB_BASE_URL, login_or_token=git_token)
    git_repo = ld.get_feature_flag_git_repo()

    try:
        github_repo = github.get_repo(git_repo)
        dev_integration_branch = github_repo.get_branch('dev-integration')
        commit_sha = dev_integration_branch.commit.sha
        print(f"Git Hash: {git_repo} on dev-integration branch has commit hash: {commit_sha}")
        print(f"Featureflag: {ld.featureflag} {variations[which]['value']}")
        if commit_sha == variations[which]['value']:
            print(f"SUCCESS: dev-integration head is pointing at same commit hash as the current active variation of launch darkly {ld.featureflag}")
        else:
            tags = github_repo.get_tags()
            for tag in tags:
                if tag.commit.sha == commit_sha and tag.name == variations[which]['value']:
                    print(f"SUCCESS: dev-integration head is pointing at same commit hash as the current active variation of launch darkly {ld.featureflag}")
                    break
            else:
                print(f"FAILURE: the current active variation of launch darkly {ld.featureflag}: {variations[which]} and dev-integration head of the workspace: ${commit_sha} don't match.")

    except Exception as e:
        print(f"Error: {e}")
        raise SystemExit(e)

def pretty_json(obj):
    return json.dumps(obj, sort_keys=True, indent=4)


def envconfig(args):
    if not args.auth_token:
        args.auth_token = os.getenv("AUTH_TOKEN")

#bulk import rules : MASCD-661
def bulk_import_rules(ld,environment,tag,datapath,is_dry_run):
    data = get_data_for_rules(datapath)
    json_res = ld.get_feature_flags()
    included_flags = []
    excluded_flags = []
    rule = []
    try:
        for item in json_res["items"]:
            flag = item["key"]
            if tag in item["tags"]:
                included_flags.append(flag)
            else:
                excluded_flags.append(flag)
    except KeyError as e:
        print("Could not find key",e)
    except Exception as e:
        print("Error occurred while getting the feature flags data.\nError:",e)        
    
    rule = get_default_values_for_rule(ld,environment)
    if rule != None:
        if is_dry_run.lower() == "true":
            print("This is a dry-run!\n")
            print_bulk_import_report(included_flags, excluded_flags)
        else:
            for f in included_flags:
                ld = LaunchDarkly(ld.base_url, f, ld.auth_token)
                add_rule_for_ff(ld,environment,data,rule)
            print_bulk_import_report(included_flags, excluded_flags)


def print_bulk_import_report(included_flags,excluded_flags): 
    print('{:<30} {:<10}'.format("Included flags({0})".format(len(included_flags)),"Excluded flags({0})".format(len(excluded_flags))))
    print('{:<30} {:<10}'.format("---","---"))
    arrays = [included_flags, excluded_flags]
    max_length = 0
    for array in arrays:
        max_length = max(max_length, len(array))
    for array in arrays:
        array += [''] * (max_length - len(array))  
    i = 0
    for flag in included_flags:
        print('{:<30} {:<10}'.format(flag,excluded_flags[i]))
        i+=1
    return


def get_data_for_rules(path):
    f = open(path)
    data = f.read().splitlines()
    f.close()
    return data

def get_default_values_for_rule(ld,environment):
    feature_flags_dict = ld.get_all()
    try:
        rules = feature_flags_dict["environments"][environment]["rules"]
        default_rule = {
            "clauses": [
                {
                    "attribute": rules[0]["clauses"][0]["attribute"],
                    "negate": rules[0]["clauses"][0]["negate"],
                    "op": rules[0]["clauses"][0]["op"],
                    "values": rules[0]["clauses"][0]["values"]
                }
            ],
            "variation": rules[0]["variation"]
        }
        return default_rule  
    except TypeError as e:
        print("Please make sure to add a sample rule to the reference flag: '{0}' in launch darkly".format(ld.featureflag))
    except Exception as e:
        print("Error occurred while fetching the reference flag data.\nError:",e) 
        print("Please make sure to add a sample rule to the reference flag: '{0}' in launch darkly".format(ld.featureflag))

def create_new_rule(source,values):
    try:
        new_rule = {
            "clauses": [
                {
                    "attribute": source["clauses"][0]["attribute"],
                    "negate": source["clauses"][0]["negate"],
                    "op": source["clauses"][0]["op"],
                    "values": [values]
                }
            ],
            "variation": source["variation"]
        }
        return new_rule
    except TypeError as e:
        print("Please make sure to add a sample rule to the reference flag: '{0}' in launch darkly".format(ld.featureflag))
    except Exception as e:
        print("Error occurred while creating new rule.\nError:",e)
    

def add_rule_for_ff(ld,environment,data,rule):
    print("\nAdding rules to:",ld.featureflag)
    feature_flags_dict = ld.get_all()
    try:
        rules = feature_flags_dict["environments"][environment]["rules"]
        defaultVariation = feature_flags_dict["environments"][environment]["fallthrough"]["variation"]
        rule["variation"] = defaultVariation
        rules_len = len(rules)
        for item in data:
            try:
                duplicate = next((r for r in rules if r["clauses"][0]["values"][0] == item), None)
                if duplicate == None:
                    new_rule = create_new_rule(rule,item)
                    rules.append(new_rule)
                else:
                    print("Found duplicate rule:", item)
            except:
                new_rule = create_new_rule(rule,item)
                rules.append(new_rule)
                continue
        if len(rules) > rules_len:
            ld.save_rules(environment,rules)
    except TypeError as e:
        print("Please make sure to add a sample rule to the reference flag: '{0}' in launch darkly".format(ld.featureflag))
    except Exception as e:
        print("Error occurred while adding new rule.\nError:",e)

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
        description="manipulate featureflags via LaunchDarkly"
    )

    # global flags
    parser.add_argument(
        "--auth-token",
        help="the environment variable AUTH_TOKEN is used if this is missing",
    )
    parser.add_argument(
        "--base-url",
        default="https://app.launchdarkly.com/api/v2/flags/vpc-ci/",
        help="the URL for LaunchDarkly up to the point of the featureflag",
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

    # show -- show whole state of the featureflag
    p_show = subcmd.add_parser(
        "show", description="show whole state of featureflag"
    )

    # variations -- show variations
    p_variations = subcmd.add_parser(
        "variations", description="show all variations"
    )

    # add -- adds new variation
    p_set_value = subcmd.add_parser(
        "add", description="add a new variation to the featureflag"
    )
    p_set_value.add_argument(
        "new_value", help="the new featureflag value to add to variations"
    )
    cleanups = p_set_value.add_mutually_exclusive_group()
    cleanups.add_argument(
        "--remove-oldest",
        "-O",
        action="store_true",
        help="remove the oldest variation",
    )
    cleanups.add_argument(
        "--replace-newest",
        "-N",
        action="store_true",
        help="replaced the newest variation",
    )
    p_set_value.add_argument(
        "rule_environment",
        help="LD environment to update rule in (development, integration, staging, production)",
    )
    p_set_value.add_argument(
        "--use",
        "-u",
        action="store_true",
        help="use the new value after it's added",
    )

    # use -- use a variation
    p_use_value = subcmd.add_parser(
        "use", description="set new value into variations and use the new value"
    )
    p_use_value.add_argument(
        "rule_environment",
        help="LD environment to update rule in (development, integration, staging, production)",
    )
    p_use_value.add_argument(
        "which", help="the 0-based index of the variations to use"
    )

    # useinrule -- use a variation in rule
    p_useinrule_value = subcmd.add_parser(
        "use_in_rule", description="set new value into variations and use the new value in rule"
    )
    p_useinrule_value.add_argument(
        "which", type=int, help="the 0-based index of the variations to use"
    )

    p_useinrule_value.add_argument(
        "rule_environment",
        help="LD environment to update rule in (development, integration, staging, production)",
    )
    p_useinrule_value.add_argument(
        "rule_tag",
        help="tag to search the rule for",
    )

    # usedefaultinrule -- use a default variation in rule
    p_useinrule_value = subcmd.add_parser(
        "use_default_in_rule", description="use the default rule variation value in rule"
    )

    p_useinrule_value.add_argument(
        "rule_environment",
        help="LD environment to update rule in (development, integration, staging, production)",
    )
    p_useinrule_value.add_argument(
        "rule_tag",
        help="tag to search the rule for",
    )

    # add -- adds new variation and use it in rule
    p_set_use_in_rule_value = subcmd.add_parser(
        "add_and_use_in_rule", description="add a new variation to the featureflag and use it in rule"
    )
    p_set_use_in_rule_value.add_argument(
        "new_value", help="the new featureflag value to add to variations"
    )
    p_set_use_in_rule_value.add_argument(
        "rule_environment",
        help="LD environment to update rule in (development, integration, staging, production)",
    )
    p_set_use_in_rule_value.add_argument(
        "rule_tag",
        help="tag to search the rule for",
    )

    cleanups = p_set_use_in_rule_value.add_mutually_exclusive_group()
    cleanups.add_argument(
        "--remove-oldest",
        "-O",
        action="store_true",
        help="remove the oldest variation",
    )
    cleanups.add_argument(
        "--replace-newest",
        "-N",
        action="store_true",
        help="replaced the newest variation",
    )

    # rmvars -- remove a variation by id
    p_rmvars = subcmd.add_parser(
        "rmvars",
        description=(
            "remove one or more variations by ID; ignores IDs that aren't in"
            " the list of variations"
        ),
    )
    p_rmvars.add_argument(
        "--dry-run",
        "-n",
        action="store_true",
        help="show the result without removing",
    )
    p_rmvars.add_argument(
        "variation_ids",
        metavar="ID",
        nargs="+",
        help="IDs of variations to remove",
    )

    # which -- show which variation is active
    p_which = subcmd.add_parser(
        "which", description="show which variation is active"
    )
    p_which.add_argument(
        "variation_environment",
        help="LD environment to update rule in (development, integration, staging, production)",
    )

    # show_active_variation -- searches the rules for given rule_tag and prints the active variation, if it fails to find a matching rule, it prints fall through (default rule) variation
    p_show_active_variation = subcmd.add_parser(
        "show_active_variation",
        description="searches the rules for given rule_tag and prints the active variation, if it fails to find a matching rule, it prints fall through (default rule) variation",
        usage=(
            """
            Report Only.... (Example) Use command below to show active variation in a given rule_tag (mascd-1) and given ld environment (development) for rgw-image-version featureflag:
            python3 scripts/featureflags.py --auth-token=api-<REDACTED> rgw-image-version show_active_variation development mascd-1 git_token
            """
        ),
    )
    p_show_active_variation.add_argument(
        "variation_environment",
        help="LD environment to update rule in (development, integration, staging, production)",
    )
    p_show_active_variation.add_argument(
        "rule_tag",
        help=(
            "Which mzone/region/environment's rules you want to copy over? (mascd-1, rias-ng-us-south-dal-dev26-etcd, ....)"
        ),
    )
    p_show_active_variation.add_argument(
        "git_token",
        help=(
            "git token to connect to github"
        ),
    )

    # set_default -- sets an environment to default onVariation
    p_set_default = subcmd.add_parser(
        "set_default",
        description="sets an environment to default onVariation",
        usage=(
            """
            Report Only.... (Example) Use command below to generate a report if development (target) LD environment were to be set to all of its default onVariations:
            python3 scripts/featureflags/featureflags.py --auth-token=api-<REDACTED> "" set_default development True
            Promote and Report... (Example) Use command below to set development LD environment to all if its featureflags' default onVariations and generate a report:
            python3 scripts/featureflags/featureflags.py --auth-token=api-<REDACTED> "" set_default development False
            """
        ),
    )
    p_set_default.add_argument(
        "environment",
        help=(
            "Which LD environment should be set to default to? (development, integration, staging, production)"
        ),
    )
    p_set_default.add_argument(
        "report_only",
        help=(
            "if set to True, will only give a report of the changes if set_default command was ran"
        ),
    )

    # promote -- promote to user suggested environment
    p_promote = subcmd.add_parser(
        "promote",
        description="promote to user suggested environment",
        usage=(
            """
            Report Only.... (Example) Use command below to generate a report if promotion of integration (target) LD environment based on development (source) LD enviornment were to happen:
            python3 scripts/featureflags/featureflags.py --auth-token=api-<REDACTED> "" promote development integration True
            Promote and Report... (Example) Use command below to promote integration (target) LD environment based on development (source) LD enviornment and generate a report:
            python3 scripts/featureflags/featureflags.py --auth-token=api-<REDACTED> "" promote development integration False
            """
        ),
    )
    p_promote.add_argument(
        "source_environment",
        help=(
            "Which LD environment's flags you want to copy over? (development, integration, staging, production)"
        ),
    )
    p_promote.add_argument(
        "target_environment",
        help=(
            "Which LD environment should get the flag's values of target_environment? (development, integration, staging, production)"
        ),
    )
    p_promote.add_argument(
        "report_only",
        help=(
            "if set to True, will only give a report of the changes if set_default command was ran"
        ),
    )
    p_get_desired_deployments_file = subcmd.add_parser(
        "get_desired_deployments_file",
        description="Retrieves configuration from launchdarkly and dumps it into a file",
        usage=("""
        Example: python3 featureflags.py --auth-token=api-<REDACTED> featureflag get_desired_deployments_file development mzone7105
        """)
    )
    p_get_desired_deployments_file.add_argument(
        "environment",
        help=(
            "Which LD environment you want to test in?"
            "(development, integration, staging, production)"
        ),
    )
    p_get_desired_deployments_file.add_argument(
        "cluster_name",
        help=(
            "The cluster name"
            "(e.g mzone7105)"
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
    # validate_promotion - validate if the promote command ran correctly
    p_validate_promotion = subcmd.add_parser(
        "validate_promotion_by_ld",
        description="validate if the promote command ran correctly",
        usage=("""
        Example: python3 featureflags.py --auth-token=api-<REDACTED> featureflag validate_promotion_by_ld development rias-ng-us-south-dal-dev73-etcd/bqt25v6d06o529j5h3fg
        """)
    )
    p_validate_promotion.add_argument(
        "environment",
        help=(
            "Which LD environment you want to test in?"
            "(development, integration, staging, production)"
        ),
    )
    p_validate_promotion.add_argument(
        "cluster_name",
        help=(
            "The cluster name"
            "(e.g rias-ng-us-south-dal-dev73-etcd)"
        ),
    )
    p_validate_promotion.add_argument(
        "cluster_type",
        help=(
             "The type of cluster"
            "(e.g rias)"
        ),
    )
    p_validate_promotion_by_target_rule = subcmd.add_parser(
        "validate_promotion_by_target_rule",
        description="validate versions in source and target clusters",
        usage=("""
        Example: python3 featureflags.py --auth-token=api-<REDACTED> featureflag validate_promotion_by_target_rule rias-ng-us-south-dal-dev73-etcd/bqt25v6d06o529j5h3fg rias-ng-us-south-dal-dev15-etcd/bqt321d06o529j5h7thg
        """)
    )
    p_validate_promotion_by_target_rule.add_argument(
        "source_context",
        help=(
            "Which kubernetes context you want to test in?"
            "(e.g rias-ng-us-south-dal-dev73-etcd/bqt25v6d06o529j5h3fg)"
        ),
    )
    p_validate_promotion_by_target_rule.add_argument(
        "target_context",
        help=(
            "Which kubernetes context you want to test in?"
            "(e.g rias-ng-us-south-dal-dev73-etcd/bqt25v6d06o529j5h3fg)"
        )
    )

    # promote a rule in a enviornment from one region to another
    p_rule_promote = subcmd.add_parser(
        "rule_promote",
        description="promote a rule to user sugested value",
        usage=(
            """
            Report Only.... (Example) Use command below to generate a report if rule promotion of target_region=rias-ng-us-south-dal-dev26etcd
            were to happen based on source_region=mascd-1 for featureflag=rgw-image-version in development LD enviornment:
            python3 scripts/featureflags/featureflags.py --auth-token=api-<REDACTED> featureflag rule_promote development mascd-1 rias-ng-us-south-dal-dev26etcd True

            Promote the Rule and Report... (Example) Use command below to promote rule of target_region=rias-ng-us-south-dal-dev26etcd
            based on source_region=mascd-1 for featureflag=rgw-image-version in development LD enviornment and generate a report:
            python3 scripts/featureflags/featureflags.py --auth-token=api-<REDACTED> featureflag rule_promote development mascd-1 rias-ng-us-south-dal-dev26etcd False
            """
        ),
    )
    p_rule_promote.add_argument(
        "environment",
        help=(
            "Which LD environment's flags you want to copy over? (development, integration, staging, production)"
        ),
    )
    p_rule_promote.add_argument(
        "source_region",
        help=(
            "Which mzone/region/environment's rules you want to copy over? (mascd-1, rias-ng-us-south-dal-dev26-etcd, ....)"
        ),
    )
    p_rule_promote.add_argument(
        "target_region",
        help=(
            "Which mzone/region/environment's rules you want to copy over? (mascd-1, rias-ng-us-south-dal-dev26-etcd, ....)"
        ),
    )
    p_rule_promote.add_argument(
        "report_only",
        help=(
            "if set to True, will only give a report of the changes if rule_promote command was ran"
        ),
    )

    p_rule_promote_accross_ld_envs_all = subcmd.add_parser(
        "rule_promote_accross_ld_envs_all",
        description="validate versions in source and target clusters",
        usage=("""
        Report Only.... (Example) Use command below to generate a report if rule promotion of target_region=rias-ng-us-south-dal-dev26etcd
        were to happen based on source_region=mascd-1 for target_environment=integration source_environment=development target_environment=integration for featureflag=rgw-image-version in development LD enviornment:
        python3 featureflags.py --auth-token=api-<REDACTED> featureflag rule_promote_accross_ld_envs_all development integration mascd-1  rias-ng-us-south-dal-dev26-etcd True

        Promote the Rule and Report... (Example) Use command below to generate a report if rule promotion of target_region=rias-ng-us-south-dal-dev26etcd
        were to happen based on source_region=mascd-1 for target_environment=integration source_environment=development for featureflag=rgw-image-version in development LD enviornment:
        python3 featureflags.py --auth-token=api-<REDACTED> featureflag rule_promote_accross_ld_envs_all development integration mascd-1  rias-ng-us-south-dal-dev26-etcd False
        """)
    )
    p_rule_promote_accross_ld_envs_all.add_argument(
        "source_environment",
        help=(
            "Which LD environment's flags you want to copy over? (development, integration, staging, production)"
        ),
    )
    p_rule_promote_accross_ld_envs_all.add_argument(
        "target_environment",
        help=(
            "Which LD environment you want to change? (development, integration, staging, production)"
        ),
    )
    p_rule_promote_accross_ld_envs_all.add_argument(
        "source_region",
        help=(
            "Which mzone/region/environment's rules you want to copy over? (mascd-1, rias-ng-us-south-dal-dev26-etcd, ....)"
        ),
        default=None,
    )
    p_rule_promote_accross_ld_envs_all.add_argument(
        "target_region",
        help=(
            "Which mzone/region/environment's rules you want to change? (mascd-1, rias-ng-us-south-dal-dev26-etcd, ....)"
        ),
    )
    p_rule_promote_accross_ld_envs_all.add_argument(
        "report_only",
        help=(
            "if set to True, will only give a report of the changes if rule_promote command was ran"
        ),
    )
    # rolltodefault
    p_rolltodefault = subcmd.add_parser(
        "roll_to_default",
        description="roll feature flags target rule to default rule by given tag",
        usage=("""
        Example: python3 featureflags.py --auth-token=api-<REDACTED> "" roll_to_default development rias-ng-us-south-dal-dev26-etcd rgw-image-version
        """),
    )
    p_rolltodefault.add_argument(
        "rule_environment",
        help="LD environment to update rule in (development, integration, staging, production)",
    )
    p_rolltodefault.add_argument(
        "rule_tag",
        help="tag to search the rule for",
    )
    p_rolltodefault.add_argument(
        "base_featureflag",
        help="feature flag for blast radious test",
    )

    # Bulk import MASCD-661
    p_bulk_import_rules = subcmd.add_parser(
        "bulk_import_rules",
        description="Bulk import rules for all feature flags",
        usage=("""
        Command: python3 scripts/featureflags/featureflags.py --auth-token=<token_with_write_access> --base-url=https://app.launchdarkly.com/api/v2/flags/default/ <reference_flag> bulk_import_rules <environment> <file path of new line delimited rules> <namespace to include> <is dry run ?>
        Sample:  python3 scripts/featureflags/featureflags.py --auth-token=api-12345678-1234-1234-123456789123 --base-url=https://app.launchdarkly.com/api/v2/flags/default/ rhw-image-version bulk_import_rules integration  /Users/master-stabilization/iks_clusters_large.txt rias true
        """)
    )
    p_bulk_import_rules.add_argument(
        "environment",
        help=(
            "Which LD environment you want to test in ?"
            "(development, integration, staging, production)"
        ),
    )
    p_bulk_import_rules.add_argument(
        "data_path",
        help=(
            "path to a new line delimited file containing the rules"
        ),
    )
    p_bulk_import_rules.add_argument(
        "ld_tag",
        default="rias",
        help=(
            "feature flag matching this tag will be updated"
        ),
    )
    p_bulk_import_rules.add_argument(
        "dry_run",
        default="True",
        help=(
            "feature flag matching this tag will be updated"
        ),
    )        
    # validate_promotion - validate if the promote command ran correctly
    p_validate_promotion = subcmd.add_parser(
        "validate_promotion", description="validate if the ppromote command ran correctly"
    )
    p_validate_promotion.add_argument(
        "environment",
        help=(
            "Which LD environment you want to test in?"
            "(development, integration, staging, production)"
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
    # rollbacktodev -- roll
    p_rollbacktodev = subcmd.add_parser(
        "rollback_to_dev",
        description="roll feature flag target rule to default rule by given tag",
        usage=("""
        Example: python3 featureflags.py --auth-token=api-<REDACTED> "" rollback_to_dev development rias-ng-us-south-dal-dev26-etcd rgw-image-version <git_token>
        """),
    )
    p_rollbacktodev.add_argument(
        "rule_environment",
        help="LD environment to update rule in (development, integration, staging, production)",
    )
    p_rollbacktodev.add_argument(
        "rule_tag",
        help="tag to search the rule for",
    )
    p_rollbacktodev.add_argument(
        "base_featureflag",
        help="feature flag for blast radious test",
    )
    p_rollbacktodev.add_argument(
        "git_token",
        help="git token to connect to github",
    )
    # end of subcommands

    # parse args and run the subcommand
    args = parser.parse_args()
    envconfig(args)  # get some defaults from the environment
    ld = LaunchDarkly(args.base_url, args.featureflag, args.auth_token)
    try:
        sub = args.subcommand
        if sub == "show":
            show_all(ld)
        elif sub == "variations":
            show_variations(ld)
        elif sub == "add":
            set_value(
                ld,
                args.new_value,
                args.replace_newest,
                args.remove_oldest,
                args.rule_environment,
                args.use,
            )
        elif sub == "add_and_use_in_rule": #Using this in pipeline
            set_value_and_use_in_rule(
                ld,
                args.new_value,
                args.replace_newest,
                args.remove_oldest,
                args.rule_environment,
                args.rule_tag,
            )
        elif sub == "use":
            use_value(ld, args.rule_environment, args.which)
        elif sub == "use_in_rule":
            use_value_in_rule(ld, args.which, args.rule_environment, args.rule_tag)
        elif sub == "use_default_in_rule":
            use_default_value_in_rule(ld, args.rule_environment, args.rule_tag)
        elif sub == "rmvars":
            rmvars(ld, args.variation_ids, args.dry_run)
        elif sub == "which":
            which(ld,
                  args.variation_environment
            )
        elif sub == "check_secrets":
            path_to_secrets = args.path_to_secrets.split('=')[1]
            ret = check_secrets(path_to_secrets)
            if ret == 1:
                print("All the secrets are there in the selected cluster")
            else:
                print("Some secrets are missing from the selected cluster")
        elif sub == "show_active_variation":
            show_active_variation(ld,
                  args.variation_environment,
                  args.rule_tag,
                  args.git_token
            )
        elif sub == "set_default":
            set_default_variation(ld,
                  args.environment,
                  args.report_only
            )
        elif sub == "promote":
            promote(ld,
                  args.source_environment,
                  args.target_environment,
                  args.report_only
            )
        elif sub == "get_desired_deployments_file":
            get_desired_deployment_versions_file(
                ld,
                args.environment,
                args.cluster_name
            )
        elif sub == "validate_promotion_by_ld_with_file":
            validate_promotion_func_desired_from_file(
                args.file_location,
                args.cluster_type
                
            )            
        elif sub == "validate_promotion_by_ld":
            validate_promotion_func(
                ld,
                args.environment,
                args.cluster_name,
                args.cluster_type
            )
        elif sub == "validate_promotion_by_target_rule":
            validate_promotion_by_targetrule(args.source_context,args.target_context)
        elif sub == "rule_promote":
            rule_promote(ld,
                args.environment,
                args.source_region,
                args.target_region,
                args.report_only
            )
        elif sub == "rule_promote_accross_ld_envs_all":
            rule_promote_accross_ld_envs_all(
                ld,
                args.source_environment,
                args.target_environment,
                args.source_region,
                args.target_region,
                args.report_only
            )
        elif sub == "bulk_import_rules":
            bulk_import_rules(ld,args.environment,args.ld_tag,args.data_path,args.dry_run)

        elif sub == "roll_to_default":
            roll_to_default_func(ld,
                args.rule_environment,
                args.rule_tag,
                args.base_featureflag
            )
        elif sub == "rollback_to_dev":
            rollback_to_dev_func(ld,
                args.rule_environment,
                args.rule_tag,
                args.base_featureflag,
                args.git_token
            )

    except LaunchDarklyException as e:
        raise SystemExit(e)
