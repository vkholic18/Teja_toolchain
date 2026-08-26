# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# Description:
#     Runs razee readiness check loop to evaluate that all requested MTP in razee deployment files are actually deployed on the cluster
#     and healthy

# Arguments:
#      $1: release bundle for mtps readiness check {rias | rias-etcd}

import logging
import sys
import subprocess
import time
import yaml

# Constants
RECONCILE_TIMEOUT = 1800
RECONCILE_TIMEOUT_SLEEP = 30
MUSTACHE_TEMPLATE = "mtp"
REMOTE_RESOURCE = "rr"
RIAS_RELEASE_BUNDLE = "rias"
RIAS_ETCD_RELEASE_BUNDLE = "rias-etcd"
GENCTL_RELEASE_BUNDLE = "genctl"
RETRY_ERRORS = ["Unable to connect to the server: dial tcp", "connect ECONNRESET"]

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

def load_yaml_string(yaml_str):
    logger = logging.getLogger()
    try:
        dictionary = yaml.safe_load(yaml_str)
        return dictionary
    except yaml.YAMLError:
        logger.info(f"yaml {yaml_str} is not valid, exiting")
        exit(1)

def retry_cmd(cmd,return_code):
    for i in range(0,5):
        time.sleep(10)
        print(f"Execute {cmd}, {i} attempt")
        if "Unable to connect to the server: dial tcp" in return_code.stdout:
            return_code = subprocess.run(cmd, shell=True, text=True, stdout=subprocess.PIPE)
        else:
            break
    return return_code

def get_cluster_context():
    cmd = "kubectl config current-context"
    try:
        print(f"Execute: {cmd}")
        return_code = subprocess.run(cmd, shell=True, text=True, stdout=subprocess.PIPE)
        print(f"Result: {return_code.stdout}")
        if any(err in return_code.stdout for err in RETRY_ERRORS):
            return_code = retry_cmd(cmd, return_code)
        if return_code.returncode == 1:
            print(f"Return code for {cmd} : {return_code.returncode}")
            exit(1)
    except:
        print(f"Exception on {cmd}")
        exit(1)

def get_resource_yaml(namespace, resource, resource_name):
    cmd = "kubectl -n {} get {} {} -o yaml".format(namespace, resource, resource_name)
    try:
        print(f"Execute: {cmd}")
        return_code = subprocess.run(cmd, shell=True, text=True, stdout=subprocess.PIPE)
        if any(err in return_code.stdout for err in RETRY_ERRORS):
            return_code = retry_cmd(cmd, return_code)
        if return_code.returncode == 1:
            print(f"Return code for {cmd} : {return_code.returncode}")
            exit(1)
    except:
        print(f"Exception on {cmd}")
        exit(1)
    return load_yaml_string(return_code.stdout)

def get_cluster_status_log():
    cmd = "kubectl get -A mtp,rr -o=json " + "| jq '.items[] | select(.status.\"razee-logs\".error) | .metadata.name + \" \" + .metadata.namespace + \" \" + .kind,.status.\"razee-logs\"  ' "
    try:
        print(f"Execute: {cmd}")
        return_code = subprocess.run(cmd, shell=True, text=True, stdout=subprocess.PIPE)
        if any(err in return_code.stdout for err in RETRY_ERRORS):
            return_code = retry_cmd(cmd, return_code)
        if return_code.returncode == 1:
            print(f"Return code for {cmd} : {return_code.returncode}")
            exit(1)
    except:
        print(f"Exception on {cmd}")
        exit(1)
    print (f"-------------   Cluster MTPs and RR/RRS3 status  ---------------")
    print (f" {return_code.stdout}")
    if ("error" in return_code.stdout):
        exit(1)

def evaluate_rr_mtp_child(name):
    child_url_list = name.split("/")
    if "remoteresources" in child_url_list:
        print (f"RR was found in a MTP children: {child_url_list[-3]}/{child_url_list[-1]}")
        #return namespace and name of remoteresources
        return child_url_list[-3], child_url_list[-1]
    else:
        print (f"Stop on MTP child: {child_url_list[-3]}/{child_url_list[-2]}/{child_url_list[-1]}")
        print (f"Continue with the next RR child.")
        return "",""

def evaluate_rr_child(name):
    child_url_list = name.split("/")
    if "mustachetemplates" in child_url_list:
        print (f"MTP was found in a RR child: {child_url_list[-3]}/{child_url_list[-1]}")
        return child_url_list[-3], child_url_list[-1]
    else:
        print (f"Skiping on RR: {child_url_list[-3]}/{child_url_list[-2]}/{child_url_list[-1]}")
        return "", ""


def wait_until(function, timeout, period=0.25, *args, **kwargs):
    mustend = time.time() + timeout
    waiting_for = 0
    while time.time() < mustend:
        if function(*args, **kwargs): return True
        time.sleep(period)
        waiting_for += period
        print(f"Waiting for {waiting_for} sec. {RECONCILE_TIMEOUT - waiting_for } sec left for readiness waiting timeout")
    return False

def is_mtp_reconcile(mtp_namespace, mtp_name):
    try:
        mtp_yaml = get_resource_yaml(mtp_namespace, MUSTACHE_TEMPLATE, mtp_name)
        mtp_razee_logs_error = mtp_yaml["status"]["razee-logs"]["error"]
        print (f"Error found in MTP rendering: {mtp_razee_logs_error}")
        return False
    except KeyError:
        print (f"MTP {mtp_namespace}/{mtp_name} successfully reconciled, no errors found.")
        return True

def is_mtp_has_children(mtp_namespace, mtp_name):
    try:
        mtp_yaml = get_resource_yaml(mtp_namespace, MUSTACHE_TEMPLATE, mtp_name)
        mtp_children = mtp_yaml["status"]["children"]
        print (f"MTP {mtp_namespace}/{mtp_name} children found")
        return True
    except KeyError:
        print (f"MTP {mtp_namespace}/{mtp_name} children not found")
        return False

def is_rr_reconcile(rr_namespace, rr_name):
    rr_yaml = get_resource_yaml(rr_namespace, REMOTE_RESOURCE, rr_name)

    try:
        requests_size = len(rr_yaml["spec"]["requests"])
        if 'requests' in rr_yaml["spec"] and len(rr_yaml["spec"]["requests"]) > 0:
            children_size = len(rr_yaml["status"]["children"])
            if requests_size > children_size:
                print (f"RR {rr_name} requested objects number ({requests_size}) is greater than the number of children ({children_size}).")
                return False

            print (f"RR {rr_name} requested objects number ({requests_size})")
            print (f"RR {rr_name} children number ({children_size})")
        else:
            print (f"RR {rr_name} No requests found on RR. Continue ...")
    except KeyError:
        print (f"RR {rr_name} error in key")
        return False
    '''
    try:
        rr_razee_logs_error = rr_yaml["status"]["razee-logs"]["error"]
        print (f"Error found in RR rendering: {rr_razee_logs_error}")
        return False
    except KeyError:
        print (f"RR {rr_name} successfully reconciled, no errors found.")
        return True
    '''
    return True

def is_pod_exist(pod_namespace, pod_name):
    cmd = "kubectl -n {} get pod | grep {}".format(pod_namespace, pod_name)
    try:
        print(f"Execute: {cmd}")
        return_code = subprocess.run(cmd, shell=True, text=True, stdout=subprocess.PIPE)
        if any(err in return_code.stdout for err in RETRY_ERRORS):
            return_code = retry_cmd(cmd, return_code)
        if return_code.returncode == 1:
            print(f"Return code for {cmd} : {return_code.returncode}")
            return False
    except:
        print(f"Exception on {cmd}")
        return False
    print(f"Pod exist: {pod_namespace}/{pod_name}")
    return True

def is_mtp_exist(mtp_namespace, mtp_name):
    cmd = "kubectl -n {} get mtp {}".format(mtp_namespace, mtp_name)
    try:
        print(f"Execute: {cmd}")
        return_code = subprocess.run(cmd, shell=True, text=True, stdout=subprocess.PIPE)
        if any(err in return_code.stdout for err in RETRY_ERRORS):
            return_code = retry_cmd(cmd, return_code)
        if return_code.returncode == 1:
            print(f"Return code for {cmd} : {return_code.returncode}")
            return False
    except:
        print(f"Exception on {cmd}")
        return False
    print(f"Pod exist: {mtp_namespace}/{mtp_name}")
    return True

def cluster_mtps_report(mtp_namespace):
    cmd = "kubectl get -n {} mtp --no-headers -o custom-columns=':metadata.namespace,:metadata.name'".format(mtp_namespace)
    try:
        print(f"Execute: {cmd}")
        return_code = subprocess.run(cmd, shell=True, text=True, stdout=subprocess.PIPE)
        if any(err in return_code.stdout for err in RETRY_ERRORS):
            return_code = retry_cmd(cmd, return_code)
        if return_code.returncode == 1:
            print(f"Return code for {cmd} : {return_code.returncode}")
    except:
        print(f"Exception on {cmd}")
    mtp_list = return_code.stdout.splitlines()
    print(f"Mustache templates running on the cluster:")
    print(f"{return_code.stdout}")
    return len(mtp_list)

def wait_for_pod(pod_namespace, pod_name):
    if wait_until(is_pod_exist, RECONCILE_TIMEOUT, RECONCILE_TIMEOUT_SLEEP, pod_namespace, pod_name) == False:
        print (f"Failed to wait for pod {pod_namespace}/{pod_name} in {RECONCILE_TIMEOUT} sec")
        get_cluster_status_log()
        sys.exit (1)

def wait_for_mtp(mtp_namespace, mtp_name):
    if wait_until(is_mtp_exist, RECONCILE_TIMEOUT, RECONCILE_TIMEOUT_SLEEP, mtp_namespace, mtp_name) == False:
        print (f"Failed to wait for mtp {mtp_namespace}/{mtp_name} in {RECONCILE_TIMEOUT} sec")
        get_cluster_status_log()
        sys.exit (1)

def discover_razee_mtp(mtp_namespace, mtp_name, mtps_list):
    print (f"------EVALUATE {mtp_name}  -------")
    mtps_list.append(mtp_name)
    if wait_until(is_mtp_reconcile, RECONCILE_TIMEOUT, RECONCILE_TIMEOUT_SLEEP, mtp_namespace, mtp_name) == False:
        mtp_yaml = get_resource_yaml(mtp_namespace, MUSTACHE_TEMPLATE, mtp_name)
        print (f"Failed to reconcile {mtp_namespace}/{mtp_name} in {RECONCILE_TIMEOUT} sec")
        print (f"------------{mtp_namespace}/{mtp_name} yaml ----------------")
        print (yaml.dump(mtp_yaml, default_flow_style=False))
        get_cluster_status_log()
        sys.exit (1)

    if wait_until(is_mtp_has_children, RECONCILE_TIMEOUT, RECONCILE_TIMEOUT_SLEEP, mtp_namespace, mtp_name) == False:
        mtp_yaml = get_resource_yaml(mtp_namespace, MUSTACHE_TEMPLATE, mtp_name)
        print (f"Failed to find children for {mtp_namespace}/{mtp_name} in {RECONCILE_TIMEOUT} sec")
        print (f"------------{mtp_namespace}/{mtp_name} yaml ----------------")
        print (yaml.dump(mtp_yaml, default_flow_style=False))
        get_cluster_status_log()
        sys.exit (1)

    mtp_yaml = get_resource_yaml(mtp_namespace, MUSTACHE_TEMPLATE, mtp_name)
    mtp_children = mtp_yaml["status"]["children"]

    for mtp_child_name in mtp_children:
        rr_namespace, rr_name = evaluate_rr_mtp_child(mtp_child_name)
        if rr_name == "":
            continue
        else:
            if wait_until(is_rr_reconcile, RECONCILE_TIMEOUT, RECONCILE_TIMEOUT_SLEEP, rr_namespace, rr_name) == False:
                rr_yaml = get_resource_yaml(rr_namespace, REMOTE_RESOURCE, rr_name)
                print (f"Failed to reconcile {rr_namespace}/{rr_name} in {RECONCILE_TIMEOUT} sec")
                print (f"------------{rr_namespace}/{rr_name} yaml ----------------")
                print (yaml.dump(rr_yaml, default_flow_style=False))
                get_cluster_status_log()
                sys.exit (1)
            rr_yaml = get_resource_yaml(rr_namespace, REMOTE_RESOURCE, rr_name)
            if 'children' in rr_yaml["status"]:
                rr_children = rr_yaml["status"]["children"]
                for rr_child_name in rr_children:
                    next_mtp_namespace, next_mtp_name = evaluate_rr_child(rr_child_name)
                    if next_mtp_name == "":
                        continue
                    else:
                        discover_razee_mtp(next_mtp_namespace, next_mtp_name, mtps_list)

def main():
    release_bundle = sys.argv[1]
    razee_requested_mtps_list = list()
    get_cluster_context()

    wait_for_pod("razee", "mustachetemplate-controller")
    if release_bundle == RIAS_RELEASE_BUNDLE:
        wait_for_mtp("rias", "inception-remote-resource")
        wait_for_mtp("ops", "ops-inception-remote-resource")
        discover_razee_mtp("rias", "inception-remote-resource", razee_requested_mtps_list)
        discover_razee_mtp("ops", "ops-inception-remote-resource", razee_requested_mtps_list)
        cluster_mtp_rias_num = cluster_mtps_report("rias")
        cluster_mtp_riaascore_num = cluster_mtps_report("riaascore")
        cluster_mtp_riaasiam_num = cluster_mtps_report("riaasiam")
        cluster_mtp_riaasstorage_num = cluster_mtps_report("riaasstorage")
        cluster_mtp_ops_num = cluster_mtps_report("ops")
        cluster_mtp_num = cluster_mtp_rias_num + cluster_mtp_riaascore_num + cluster_mtp_riaasiam_num + cluster_mtp_riaasstorage_num + cluster_mtp_ops_num
    elif release_bundle == RIAS_ETCD_RELEASE_BUNDLE:
        wait_for_mtp("rias-etcd", "inception-remote-resource")
        discover_razee_mtp("rias-etcd", "inception-remote-resource", razee_requested_mtps_list)
        cluster_mtp_riasetcd_num = cluster_mtps_report("rias-etcd")
        cluster_mtp_riasflink_num = cluster_mtps_report("rias-flink")
        cluster_mtp_rias_num = cluster_mtps_report("rias")
        cluster_mtp_num = cluster_mtp_riasetcd_num + cluster_mtp_riasflink_num + cluster_mtp_rias_num
    elif release_bundle == GENCTL_RELEASE_BUNDLE:
        wait_for_mtp("genctl", "inception-remote-resource")
        wait_for_mtp("genctl", "ops-inception-remote-resource")
        discover_razee_mtp("genctl", "inception-remote-resource", razee_requested_mtps_list)
        discover_razee_mtp("genctl", "ops-inception-remote-resource", razee_requested_mtps_list)
        cluster_mtp_num = cluster_mtps_report("genctl")
    else:
        print (f"Wrong release bundle for mtp readiness check: {release_bundle} ")
        sys.exit (1)

    get_cluster_status_log()
    if cluster_mtp_num == len(razee_requested_mtps_list):
        print (f"Requested MTP list number and the actual number of cluster MTPs are equal {len(razee_requested_mtps_list)} ")
        print (f"Razee deployment readiness check successfully PASSED! ")
    else:
        print (f"WARNING: Requested MTP list number: {len(razee_requested_mtps_list)} and the actual number of cluster MTPs {cluster_mtp_num} are not the same")
        print (f"MTPs list {razee_requested_mtps_list} ")

if __name__ == "__main__":
    main()
