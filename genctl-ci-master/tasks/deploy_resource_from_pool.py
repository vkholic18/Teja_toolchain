#!/usr/bin/env python
#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

import os
import sys
import yaml
import subprocess

def main(argv):

    deploy_config_file = sys.argv[1]
    print "The  deployment resourse pool configuration file: %s" % deploy_config_file
    regions_config_dir = sys.argv[2]
    resource_name = sys.argv[3]
    print "The resource name for deployment: %s" % resource_name
    deploy_type = sys.argv[4]
    print "The deployment type is: %s" % deploy_type
    current_path = os.path.abspath(os.path.dirname(__file__))
    deploy_config_full_path = os.path.join(current_path, deploy_config_file)
    print "The deployment configuration full file path: %s" % deploy_config_full_path
    with open(deploy_config_full_path, 'r') as deployyaml:
        deploy_config = yaml.safe_load(deployyaml)

    for resource in deploy_config["resource_pool"]:
        if resource['name'] == resource_name:
            resource_param1 = resource['param1']
            resource_file = resource['config_file']
            print "The deployment will be on %s\n region configuration file %s" \
                  % (resource_name, resource_file)
            # get information from region config file
            region_config_full_path = os.path.join(current_path, regions_config_dir, resource_file)
            print "Region configuration file full path: %s" % region_config_full_path
            with open(region_config_full_path, 'r') as regionyaml:
                region_config = yaml.safe_load(regionyaml)
            if deploy_type == "delete_orda_dir":
                delete_orda_dir(region_config)
            elif deploy_type == "rsync":
                rsync(region_config)
            elif deploy_type == "cleanup_public_gateway":
                cleanup_public_gateway(region_config, resource_name)
            elif deploy_type == "cleanup_orda":
                cleanup_orda(region_config, resource_name)
            elif deploy_type == "cleanup_drydock":
                cleanup_drydock(region_config, resource_name)
            elif deploy_type == "deploy_drydock":
                deploy_drydock(region_config, resource_name)
            elif deploy_type == "helm_deploy_api_workspace":
                helm_deploy_api_workspace(region_config, resource_name)
            elif deploy_type == "helm_revert_deploy_api_workspace":
                helm_revert_deploy_api_workspace(region_config, resource_name)
            elif deploy_type == "deploy_orda":
                deploy_orda(region_config, resource_name)
            elif deploy_type == "deploy_public_gateway":
                deploy_public_gateway(region_config, resource_name)
            elif deploy_type == "mzone_validate":
                mzone_validate(region_config, resource_name)
            elif deploy_type == "kubectl_get_po_pv":
                kubectl_get_po_pv(region_config)
            else:
                print "Failed to validate a deployment type. Exiting..."
                exit(1)
            exit(0)

    print "Failed to find configuration for machine %s in configuration file %s . Exiting..." % (resource_name, deploy_config_file)
    exit(1)
def delete_orda_dir(region_config):
    for proto_node in region_config["proto_node"]:
        print "Found  proto_node hostname: %s" % proto_node['hostname']
        hostip_proto_node = proto_node['hostIP']
        fabricip_proto_node = proto_node['fabricIP']
        fpextip_proto_node = proto_node['FPextIP']
        print "Proto node parameters:\n hostIP: %s\n fabricIP: %s\n FPextIP: %s\n" % (hostip_proto_node, fabricip_proto_node, fpextip_proto_node)
    delete_orda_dir_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'rm -rf ./orda-repo/*' " % hostip_proto_node
    print "delete_orda_dir_command command: %s" % delete_orda_dir_command
    try:
        return_code = subprocess.call(delete_orda_dir_command, stderr=subprocess.PIPE, shell=True)
        print "rsync_command return code: %s" %return_code
        if return_code != 0:
            print "Failed to execute %s" % delete_orda_dir_command
            exit(1)
    except:
        print "Exception on %s" % delete_orda_dir_command
        exit(1)

def rsync(region_config):
    for proto_node in region_config["proto_node"]:
        print "Found  proto_node hostname: %s" % proto_node['hostname']
        hostip_proto_node = proto_node['hostIP']
        fabricip_proto_node = proto_node['fabricIP']
        fpextip_proto_node = proto_node['FPextIP']
        print "Proto node parameters:\n hostIP: %s\n fabricIP: %s\n FPextIP: %s\n" % (hostip_proto_node, fabricip_proto_node, fpextip_proto_node)
    rsync_command = "rsync -av -e \"ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key\" ./orda-repo genadm@%s:" % hostip_proto_node
    print "rsync command: %s" % rsync_command
    try:
        return_code = subprocess.call(rsync_command, stderr=subprocess.PIPE, shell=True)
        print "rsync_command return code: %s" %return_code
        if return_code != 0:
            print "Failed to execute %s" % rsync_command
            exit(1)
    except:
        print "Exception on %s" % rsync_command
        exit(1)

def cleanup_public_gateway(region_config, resource_name):
    for proto_node in region_config["proto_node"]:
        print "Found  proto_node hostname: %s" % proto_node['hostname']
        hostip_proto_node = proto_node['hostIP']
        fabricip_proto_node = proto_node['fabricIP']
        fpextip_proto_node = proto_node['FPextIP']
        print "Proto node parameters:\n hostIP: %s\n fabricIP: %s\n FPextIP: %s\n" % (hostip_proto_node, fabricip_proto_node, fpextip_proto_node)
    public_gateway_cleanup_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'cd ~/orda-repo/drydock/playbooks && ansible-playbook -i ../inventories/%s/%s.ini public_gateway_cleanup.yml --extra-vars \"automated=true snapshot_id=latest\" -e \"ansible_ssh_pass=genes1s\" ' " \
                                     % (hostip_proto_node, resource_name, resource_name)
    print "public_gateway_cleanup command: %s" % public_gateway_cleanup_command
    try:
        return_code = subprocess.call(public_gateway_cleanup_command, stderr=subprocess.PIPE, shell=True)
        print "public_gateway_cleanup_command return code: %s" %return_code
        if return_code != 0:
            print "Failed to execute %s" % public_gateway_cleanup_command
            exit(1)
    except:
        print "Exception on %s" % public_gateway_cleanup_command
        exit(1)

def cleanup_orda(region_config, resource_name):
    for proto_node in region_config["proto_node"]:
        print "Found  proto_node hostname: %s" % proto_node['hostname']
        hostip_proto_node = proto_node['hostIP']
        fabricip_proto_node = proto_node['fabricIP']
        fpextip_proto_node = proto_node['FPextIP']
        print "Proto node parameters:\n hostIP: %s\n fabricIP: %s\n FPextIP: %s\n" % (hostip_proto_node, fabricip_proto_node, fpextip_proto_node)
    orda_cleanup_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'cd ~/orda-repo/drydock/playbooks && ansible-playbook -i ../inventories/%s/%s.ini orda_cleanup.yml --extra-vars \"automated=true snapshot_id=latest\" -e \"ansible_ssh_pass=genes1s\" ' " \
                           % (hostip_proto_node, resource_name, resource_name)
    print "orda_cleanup_command command: %s" % orda_cleanup_command
    try:
        return_code = subprocess.call(orda_cleanup_command, stderr=subprocess.PIPE, shell=True)
        print "orda_cleanup_command return code: %s" %return_code
        if return_code != 0:
            print "Failed to execute %s" % orda_cleanup_command
            exit(1)
    except:
        print "Exception on %s" % orda_cleanup_command
        exit(1)

def cleanup_drydock(region_config, resource_name):
    for proto_node in region_config["proto_node"]:
        print "Found  proto_node hostname: %s" % proto_node['hostname']
        hostip_proto_node = proto_node['hostIP']
        fabricip_proto_node = proto_node['fabricIP']
        fpextip_proto_node = proto_node['FPextIP']
        print "Proto node parameters:\n hostIP: %s\n fabricIP: %s\n FPextIP: %s\n" % (hostip_proto_node, fabricip_proto_node, fpextip_proto_node)
    drydock_cleanup_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'cd ~/orda-repo/drydock/playbooks && ansible-playbook -i ../inventories/%s/%s.ini drydock_cleanup.yml --extra-vars \"automated=true snapshot_id=latest\" -e \"ansible_ssh_pass=genes1s\" ' " \
                              % (hostip_proto_node, resource_name, resource_name)
    print "drydock_cleanup_command command: %s" % drydock_cleanup_command
    try:
        return_code = subprocess.call(drydock_cleanup_command, stderr=subprocess.PIPE, shell=True)
        print "drydock_cleanup_command return code: %s" %return_code
        if return_code != 0:
            print "Failed to execute %s" % drydock_cleanup_command
            exit(1)
    except:
        print "Exception on %s" % drydock_cleanup_command
        exit(1)

def deploy_drydock(region_config, resource_name):
    for proto_node in region_config["proto_node"]:
        print "Found  proto_node hostname: %s" % proto_node['hostname']
        hostip_proto_node = proto_node['hostIP']
        fabricip_proto_node = proto_node['fabricIP']
        fpextip_proto_node = proto_node['FPextIP']
        print "Proto node parameters:\n hostIP: %s\n fabricIP: %s\n FPextIP: %s\n" % (hostip_proto_node, fabricip_proto_node, fpextip_proto_node)
    drydock_deploy_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'cd ~/orda-repo/drydock/playbooks && ansible-playbook -i ../inventories/%s/%s.ini drydock_deploy.yml --extra-vars \"automated=true snapshot_id=latest\" -e \"ansible_ssh_pass=genes1s\" && echo $? ' " \
                             % (hostip_proto_node, resource_name, resource_name)
    print "drydock_deploy_command command: %s" % drydock_deploy_command
    try:
        return_code = subprocess.call(drydock_deploy_command, stderr=subprocess.PIPE, shell=True)
        print "drydock_deploy_command return code: %s" %return_code
        if return_code != 0:
            print "Failed to execute %s" % drydock_deploy_command
            exit(1)
    except:
        print "Exception on %s" % drydock_deploy_command
        exit(1)

def deploy_orda(region_config, resource_name):
    for proto_node in region_config["proto_node"]:
        print "Found  proto_node hostname: %s" % proto_node['hostname']
        hostip_proto_node = proto_node['hostIP']
        fabricip_proto_node = proto_node['fabricIP']
        fpextip_proto_node = proto_node['FPextIP']
        print "Proto node parameters:\n hostIP: %s\n fabricIP: %s\n FPextIP: %s\n" % (hostip_proto_node, fabricip_proto_node, fpextip_proto_node)
    orda_deploy_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'cd ~/orda-repo/drydock/playbooks && ansible-playbook -i ../inventories/%s/%s.ini orda_deploy.yml --extra-vars \"apply=true automated=true snapshot_id=latest\" -e \"ansible_ssh_pass=genes1s\" && echo $? ' " \
                          % (hostip_proto_node, resource_name, resource_name)
    print "orda_deploy_command command: %s" % orda_deploy_command
    try:
        return_code = subprocess.call(orda_deploy_command, stderr=subprocess.PIPE, shell=True)
        print "orda_deploy_command return code: %s" %return_code
        if return_code != 0:
            print "Failed to execute %s" % orda_deploy_command
            exit(1)
    except:
        print "Exception on %s" % orda_deploy_command
        exit(1)

# helm deply api-workspace 
def helm_deploy_api_workspace(region_config, resource_name):
    # get all nodes ips first
    hostip_proto_node, fabricip_proto_node, fpextip_proto_node, hostip_compute_node = get_nodes_ips(region_config)
    print "Proto node parameters:\n hostIP: %s\n fabricIP: %s\n FPextIP: %s\n computeHostIP: %s\n" % (hostip_proto_node, fabricip_proto_node, fpextip_proto_node, hostip_compute_node)

    localFile = "~/orda-repo/drydock/inventories/%s/locals.yaml" % resource_name
    renameFile = "~/orda-repo/drydock/inventories/%s/.tmp.locals.yaml" % resource_name

    move_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'mv %s %s' " % (hostip_proto_node, localFile, renameFile)
    print "move_command: %s\n" % move_command
    capture_exceptions_on_commands(move_command)

    # read latest.yaml file
    with open("latest.yaml", "r") as f:
        PRImageTag = f.read()
    print "current PR githash: %s\n" % PRImageTag
    content = """
---
# Generated by the inventory generator
this_var: is_a_placeholder  # Defined because spruce requires some content.
use_helm: true
use_helm_linting: yes
components:
  - (( replace ))
  - repo_name: api-workspace
    manifest: deployment.yaml
    namespace: genctl
    helm:
      chart: integration-tests-api-workspace
      release: integration-api-ws
api_workspace: 
  image_tag: """
    content += PRImageTag

    with open("tmpFile", "w+") as f:
        f.write(content)
    scp_command = "scp -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key tmpFile genadm@%s:%s" % (hostip_proto_node, localFile)
    print "scp_command: %s\n" % scp_command
    capture_exceptions_on_commands(scp_command)

    removeFile_command = "rm -f tmpFile"
    print "removeFile_command: %s\n" % removeFile_command
    capture_exceptions_on_commands(removeFile_command)

    # cleanup api-ws helm chart
    helm_del_api_ws = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'helm delete --purge api-ws && echo $? ' " % hostip_proto_node
    print "helm delete chart command: %s\n" % helm_del_api_ws
    capture_exceptions_on_commands(helm_del_api_ws)

    # cleanup integration-api-ws helm chart
    helm_del_int_api_ws = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'helm delete --purge integration-api-ws && echo $? ' " % hostip_proto_node
    print "helm delete integration-api-ws chart command: %s\n" % helm_del_int_api_ws
    capture_exceptions_on_commands(helm_del_int_api_ws)

    # delete the existed secret in the current deploy
    delete_secret_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key root@%s 'kubectl delete secret iam-key-decoder && echo $?'" % hostip_compute_node
    print "delete_secret_command: %s\n" % delete_secret_command
    capture_exceptions_on_commands(delete_secret_command)

    configmaps = ["iam-variables", "cm-iam-rest-server", "iam-service-keys"] 
    execute_cleanup_configmap_command(configmaps, hostip_compute_node)

    deployments = ["api-rest-server", "api-grpc-server", "api-upload-server", "iam-rest-server"]
    execute_cleanup_deployment_command(deployments, hostip_compute_node)


    # deploy orda
    orda_deploy_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'cd ~/orda-repo/drydock/playbooks && ansible-playbook -i ../inventories/%s/%s.ini orda_deploy.yml --extra-vars \"apply=true snapshot_id=latest\" -e \"ansible_ssh_pass=genes1s\" && echo $? ' " \
                          % (hostip_proto_node, resource_name, resource_name)
    print "orda_deploy_command command: %s\n" % orda_deploy_command
    try:
        return_code = subprocess.call(orda_deploy_command, stderr=subprocess.PIPE, shell=True)
        print "orda_deploy_command return code: %s" %return_code
        if return_code != 0:
            print "Failed to execute %s" % orda_deploy_command
            exit(1)
    except:
        print "Exception on %s" % orda_deploy_command
        exit(1)

    # copy the kube config file to api-workspace for integration-tests use
    copy_kube_config_command = "scp -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key root@%s:/root/.kube/config ." % hostip_compute_node
    print "copy_kube_config_command: %s\n" % copy_kube_config_command
    capture_exceptions_on_commands(copy_kube_config_command)


# helm revert back the api-workspace deploy
def helm_revert_deploy_api_workspace(region_config, resource_name):
    # get all nodes ips first
    hostip_proto_node, fabricip_proto_node, fpextip_proto_node, hostip_compute_node = get_nodes_ips(region_config)
    localFile = "~/orda-repo/drydock/inventories/%s/locals.yaml" % resource_name
    renameFile = "~/orda-repo/drydock/inventories/%s/.tmp.locals.yaml" % resource_name

    copy_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'cp %s %s' " % (hostip_proto_node, renameFile, localFile)
    print "copy_command: %s\n" % copy_command
    capture_exceptions_on_commands(copy_command)


    # helm delete integration-api-ws chart  
    helm_del_int_api_ws = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'helm delete --purge integration-api-ws  && echo $? ' " % hostip_proto_node
    print "helm delete integration-api-ws chart command: %s\n" % helm_del_int_api_ws
    capture_exceptions_on_commands(helm_del_int_api_ws)
    
    # deploy orda
    orda_deploy_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'cd ~/orda-repo/drydock/playbooks && ansible-playbook -i ../inventories/%s/%s.ini orda_deploy.yml --extra-vars \"apply=true automated=true snapshot_id=latest\" -e \"ansible_ssh_pass=genes1s\" && echo $? ' " \
                          % (hostip_proto_node, resource_name, resource_name)
    print "orda_deploy_command command: %s\n" % orda_deploy_command
    try:
        return_code = subprocess.call(orda_deploy_command, stderr=subprocess.PIPE, shell=True)
        print "orda_deploy_command return code: %s" %return_code
        if return_code != 0:
            print "Failed to execute %s" % orda_deploy_command
            exit(1)
    except:
        print "Exception on %s" % orda_deploy_command
        exit(1)


def deploy_public_gateway(region_config, resource_name):
    for proto_node in region_config["proto_node"]:
        print "Found  proto_node hostname: %s" % proto_node['hostname']
        hostip_proto_node = proto_node['hostIP']
        fabricip_proto_node = proto_node['fabricIP']
        fpextip_proto_node = proto_node['FPextIP']
        print "Proto node parameters:\n hostIP: %s\n fabricIP: %s\n FPextIP: %s\n" % (hostip_proto_node, fabricip_proto_node, fpextip_proto_node)
    public_gateway_deploy_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'cd ~/orda-repo/drydock/playbooks && ansible-playbook -i ../inventories/%s/%s.ini public_gateway_deploy.yml --extra-vars \"automated=true snapshot_id=latest\" -e \"ansible_ssh_pass=genes1s\" && echo $? ' " \
                                    % (hostip_proto_node, resource_name, resource_name)
    print "public_gateway_deploy_command command: %s" % public_gateway_deploy_command
    try:
        return_code = subprocess.call(public_gateway_deploy_command, stderr=subprocess.PIPE, shell=True)
        print "public_gateway_deploy_command return code: %s" %return_code
        if return_code != 0:
            print "Failed to execute %s" % public_gateway_deploy_command
            exit(1)
    except:
        print "Exception on %s" % public_gateway_deploy_command
        exit(1)

def mzone_validate(region_config, resource_name):
    for proto_node in region_config["proto_node"]:
        print "Found  proto_node hostname: %s" % proto_node['hostname']
        hostip_proto_node = proto_node['hostIP']
        fabricip_proto_node = proto_node['fabricIP']
        fpextip_proto_node = proto_node['FPextIP']
        print "Proto node parameters:\n hostIP: %s\n fabricIP: %s\n FPextIP: %s\n" % (hostip_proto_node, fabricip_proto_node, fpextip_proto_node)
    mzone_validate_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key genadm@%s 'cd ~/orda-repo/drydock/playbooks && ansible-playbook -i ../inventories/%s/%s.ini mzone_validate.yml --extra-vars \"automated=true snapshot_id=latest\" -e \"ansible_ssh_pass=genes1s\" && echo $? ' " \
                             % (hostip_proto_node, resource_name, resource_name)

    try:
        return_code = subprocess.call(mzone_validate_command, stderr=subprocess.PIPE, shell=True)
        print "mzone_validate_command return code: %s" %return_code
        if return_code != 0:
            print "Failed to execute %s" % mzone_validate_command
            exit(1)
    except:
        print "Exception on %s" % mzone_validate_command
        exit(1)

def kubectl_get_po_pv(region_config):
    for proto_node in region_config["proto_node"]:
        print "Found  proto_node hostname: %s" % proto_node['hostname']
        hostip_proto_node = proto_node['hostIP']
        fabricip_proto_node = proto_node['fabricIP']
        fpextip_proto_node = proto_node['FPextIP']
        print "Proto node parameters:\n hostIP: %s\n fabricIP: %s\n FPextIP: %s\n" % (hostip_proto_node, fabricip_proto_node, fpextip_proto_node)

    for compute_node in region_config["compute_node"]:
        print "Found  compute_node hostname: %s" % compute_node['hostname']
        #TODO prameter which compute_node to use
        hostip_compute_node = compute_node['hostIP']
        fabricip_compute_node = compute_node['fabricIP']
        fpextip_compute_node = compute_node['FPextIP']
        print "Compute node parameters:\n hostIP: %s\n fabricIP: %s\n FPextIP: %s\n" % (hostip_compute_node, fabricip_compute_node, fpextip_compute_node)

    kubectl_get_po_pv_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key root@%s 'kubectl get po --all-namespaces -o wide' " \
                                % (hostip_compute_node)
    print "kubectl_get_po_pv_command command: %s" % kubectl_get_po_pv_command
    try:
        return_code = subprocess.call(kubectl_get_po_pv_command, stderr=subprocess.PIPE, shell=True)
        print "kubectl_get_po_pv_command return code: %s" %return_code
        if return_code != 0:
            print "Failed to execute %s" % kubectl_get_po_pv_command
            exit(1)
    except:
        print "Exception on %s" % kubectl_get_po_pv_command
        exit(1)

# get all nodes ips
def get_nodes_ips(region_config):
    for proto_node in region_config["proto_node"]:
        print "Found  proto_node hostname: %s" % proto_node['hostname']
        hostip_proto_node = proto_node['hostIP']
        fabricip_proto_node = proto_node['fabricIP']
        fpextip_proto_node = proto_node['FPextIP']
        print "Proto node parameters:\n hostIP: %s\n fabricIP: %s\n FPextIP: %s\n" % (hostip_proto_node, fabricip_proto_node, fpextip_proto_node)
    
    for compute_node in region_config["compute_node"]:
        print "Found  compute_node hostname: %s" % compute_node['hostname']
        hostip_compute_node = compute_node['hostIP']
        print "Compute node parameters:\n computeHostIP: %s\n" % hostip_compute_node
        break

    return hostip_proto_node, fabricip_proto_node, fpextip_proto_node, hostip_compute_node

# capture the exception on linux commands
def capture_exceptions_on_commands(cmd):
    try:
        return_code = subprocess.call(cmd, stderr=subprocess.PIPE, shell=True)
        print "%s return code: %s" % (cmd, return_code)
        if return_code != 0:
            print "Failed to execute %s" % cmd
    except:
        print "Exception on %s" % cmd

def execute_cleanup_configmap_command(names, hostip_compute_node):
    for n in names:
        delete_configmap_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key root@%s 'kubectl delete configmap %s && echo $?'" % (hostip_compute_node, n)
        print "delete_configmap_command: %s" % delete_configmap_command
        capture_exceptions_on_commands(delete_configmap_command)

def execute_cleanup_deployment_command(names, hostip_compute_node):
    for n in names:
        delete_deployment_command = "ssh -o StrictHostKeyChecking=no -i ~/.ssh/cloud.key root@%s 'kubectl delete deployment %s && echo $?'" % (hostip_compute_node, n)
        print "delete_deployment_command: %s" % delete_deployment_command
        capture_exceptions_on_commands(delete_deployment_command)

if __name__ == '__main__':
    main(sys.argv[1:])
