#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020, 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#     To support integration of system z (s390x), z nodes have to be added to each CI mzone.
#
#     At first(2020), there are only z SSC nodes. About 2 years later, z Linux nodes are used
#     to replace z SSC nodes gradually. And they may coexist in some CI mzones for a long time.
#
#     HostOS release bundles did not support z from the start. In the case of hotfix pipelines,
#     old versions of HostOS release bundles may be used; HostOS 2.x and 3.x only support z SSC
#     nodes but not z Linux nodes; HostOS 5.x and 6.x only support z Linux nodes but not
#     z SSC nodes; HostOS 4.x and 10.x don't support any type of z nodes. If HostOS release 
#     bundles do not match the z nodes in the mzone, deployment may fail.
#
#     To fix the problem, this script would check vetted-versions-file to see if the listed
#     HostOS release bundles can support z Linux node, or z SSC node, or none of them.
#     It would add '--node-list' flag in the .hjson input file of ddtool to only deploy non-z
#     nodes and the supported z nodes.
#
#     An example to show how to use '--node-list' in a .hjson file.
#
#         components: {
#           hostos: {
#             packages: {
#               hostos-boot-release: {
#                 tag: 0.0.0-1111
#                 forcereboot: yes
#                 flags: [
#                   --node-list dal0-rk0-s0-a100,dal1-rk1-s1-a100
#                 ]
#         ...
#
# Arguments:
#      $1: input hjson file
#      $2: output hjson file
#      $3: inventory file
#      $4: vetted version file
#


import sys
import yaml
import hjson
import re
import copy
from enum import Enum
from packaging import version
from collections import OrderedDict


z_support_initial_versions = { 'hostos-base-net-sw-release': '2.0.3', 
                               'hostos-base-os-sw-release': '2.1.3',
                               'hostos-boot-release': '2.1.0', 
                               'hostos-config-release': '2.1.1', 
                               'hostos-kernel-patch-release': '2.1.0', 
                               'hostos-nextgen-os-sw-release': '2.1.1' }

class NodeType(Enum):
    ALL = 1
    NO_Z = 2
    NO_Z_SSC = 3
    NO_Z_LINUX = 4

HOSTOS_2_X_MAJOR = 2
HOSTOS_3_X_MAJOR = 3
HOSTOS_FIPS_MAJOR = 4
HOSTOS_5_X_MAJOR = 5
HOSTOS_6_X_MAJOR = 6
HOSTOS_REDHAT_MAJOR = 10

def get_flags(inv_file, support_node_type):
    """Filter out nodes from inventory file according to support_node_type.

    When support_node_type is NodeType.ALL:
        return None
    When support_node_type is NodeType.NO_Z:
        return -node-list flag, which includes all nodes in inv_file except z nodes.
    When support_node_type is NodeType.NO_Z_SSC:
        return -node-list flag, which includes all nodes in inv_file except z SSC nodes.
    When support_node_type is NodeType.NO_Z_LINUX:
        return -node-list flag, which includes all nodes in inv_file except z Linux nodes.
    """

    # All kinds of nodes are supported by HostOS release bundles. There is no need to
    # filter out the supported nodes from inventory file. Just keep .hjson file the same.
    if support_node_type == NodeType.ALL:
        return None

    try:
        with open(inv_file, 'r') as inv_data:
            inv_dict  = yaml.safe_load(inv_data)
    except IOError as ioe: 
        print("Failed to open {} in read mode".format(inv_file))
        print(ioe)
        sys.exit(1)
    except yaml.YAMLError as ye:
        print("Failed to load {} as yaml".format(inv_file))
        print(ye)
        sys.exit(1)

    nodes = inv_dict["master_node"] + inv_dict["compute_node"]

    non_z_nodes = []
    z_ssc_nodes = []
    z_linux_nodes = []
    support_node_list = []

    ip_prefix_pattern = re.compile(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.)')

    for node in nodes:
        if "arch" in node and node["arch"] == "s390x":
            # "ipmi" of z SSC node is IP address of Hosting Manager, which manages z SSC
            # nodes. Hosting Manager and the z SSC nodes it manages are in the rack.
            # "ipmi" of z Linux node is IP address of HMC, which can be used to manage
            # several z racks, and it doesn't belong to any z rack.
            # In the VPC environment, nodes in the same rack share the same IP prefix.
            if "ipmi" in node and "hostIP" in node and \
                ip_prefix_pattern.search(node["ipmi"])[0] == \
                ip_prefix_pattern.search(node["hostIP"])[0]:
                z_ssc_nodes.append(node["hostname"])
            else:
                z_linux_nodes.append(node["hostname"])
        else:
            non_z_nodes.append(node["hostname"])

    if support_node_type == NodeType.NO_Z_SSC:
        # mzone inventory doesn't contain z SSC nodes. No need to filer out unsupported nodes.
        if not z_ssc_nodes:
            return None
        else:
            support_node_list = non_z_nodes + z_linux_nodes
    elif support_node_type == NodeType.NO_Z_LINUX:
        if not z_linux_nodes:
            return None
        else:
            support_node_list = non_z_nodes + z_ssc_nodes
    elif support_node_type == NodeType.NO_Z:
        if  not z_ssc_nodes and not z_linux_nodes:
            return None
        else:
            support_node_list = non_z_nodes

    nodelist_str  = "--node-list "

    for i, n in enumerate(support_node_list):
        if i < len(support_node_list) - 1:
            nodelist_str = nodelist_str + n + ","
        else:
            nodelist_str = nodelist_str + n

    flags = []
    flags.append(nodelist_str) 

    return flags


def update_hjson_for_hostos_5_x(data):
    """Insert hostos-z-boot-release into OrderedDict of mzone hjson file

        Example of mzone hjson file for HostOS 5.x :
            {
                components: {
                    hostos: {
                        packages: {
                            hostos-boot-release: {
                                tag: 5.0.X-yyyymmddT123456Z_abcdefg
                                forcereboot: yes
                            }
                            hostos-z-boot-release: {
                                tag: 5.0.X-yyyymmddT123456Z_abcdefg
                                forcereboot: yes
                            }
                    ...
            }
    """

    try:
        if data["components"]["hostos"]["packages"]["hostos-boot-release"]["tag"].startswith("5."):
            pkgs = OrderedDict()

            for rb, dt in data["components"]["hostos"]["packages"].items():
                pkgs[rb]=dt
                if rb == "hostos-boot-release":
                    pkgs["hostos-z-boot-release"] = copy.deepcopy(dt)

            data["components"]["hostos"]["packages"] = pkgs

    # This function is expected to take effect only for HostOS 5.x release bundles.
    # Don't terminate the program in case something changes in the future.
    except KeyError as e:
        print("Key {} is missing in OrderedDict, which generated from mzone hjson file".format(e))
    except Exception as e:
        print(e)

def update_eyaml_for_hostos_5_x(data):
    """Insert hostos-z-boot-release into OrderedDict of mzone eyaml file
        Example of mzone hjson file for HostOS 5.x :
            apps
                release_bundles:
                    - name: hostos-boot-release:
                                version: 5.0.X-yyyymmddT123456Z_abcdefg
                    - name: hostos-z-boot-release:
                                version: 5.0.X-yyyymmddT123456Z_abcdefg
                    ...
    """
    z_boot_release = {
        'name': "hostos-z-boot-release",
        'version': "XXXX",
        'flags': [ "--simpleboot" ]
    }
    for bundle in data['apps']['release_bundles']:
        if bundle['name'] == "hostos-boot-release" and bundle['version'].startswith("5."):
                z_boot_release['version'] = bundle['version']
                data['apps']['release_bundles'].append(z_boot_release)

def add_flags_ddt(infile, outfile, nodelist):
    """Add --node-list flag to HostOS components in .hjson file."""

    try:
        with open(infile, 'r') as orig_file:
            data = hjson.load(orig_file)
    except IOError as ioe: 
        print("Failed to open {} in read mode".format(infile))
        print(ioe)
        sys.exit(1)
    except hjson.scanner.HjsonDecodeError as hde:
        print("Failed to load {} as hjson".format(infile))
        print(hde)
        sys.exit(1)

    update_hjson_for_hostos_5_x(data)

    if nodelist != None:
        for rb, dt in data["components"]["hostos"]["packages"].items():
            if rb != "hostos-z-boot-release":
                dt["flags"] = nodelist
            else:
                dt["flags"] = nodelist + ["--simpleboot"]
        for rb, dt in data["components"]["kube"]["packages"].items():
            dt["flags"] = nodelist

    try:
        with open(outfile, 'w') as new_file:
            hjson.dump(data, new_file, indent=4)
    except IOError as ioe: 
        print("Failed to open {} for dumping hjson".format(outfile))
        print(ioe)
        sys.exit(1)

def add_flags_mds(eyaml, nodelist_flags):
    """Add --node-list flag to HostOS and Kube components in EYAML file."""
    update_eyaml_for_hostos_5_x(eyaml)
    if nodelist_flags:
        nodelist_str = " ".join(nodelist_flags)
        for bundle in eyaml['apps']['release_bundles']:
            if bundle['name'].startswith("hostos") or bundle['name'].startswith("kube") or \
                bundle['name'].startswith("etcd-base-release"):
                if bundle['name'] != "hostos-z-boot-release":
                    bundle['flags'] = ['"' + nodelist_str + '"']
                else:
                    bundle['flags'] = ['"' + nodelist_str + '"'] + ["--simpleboot"]



def check_releasebundles_support_z(versionfile):
    """Check versions of HostOS release bundles in vetted-version-file.
    If they support all kinds of nodes:
        return NodeType.ALL
    If they don't support z SSC nodes:
        return NodeType.NO_Z_SSC
    If they don't support z Linux nodes:
        return NodeType.NO_Z_LINUX
    If they don't support both z Linux and SSC nodes:
        return NodeType.NO_Z
    """
    try:
        with open(versionfile, 'r') as version_data:
            vetted_versions = yaml.safe_load(version_data)
    except IOError as ioe: 
        print("Failed to open {} in read mode".format(versionfile))
        print(ioe)
        sys.exit(1)
    except yaml.YAMLError as ye:
        print("Failed to load {} as yaml".format(versionfile))
        print(ye)
        sys.exit(1)

    not_support_z_node = False
    not_support_z_ssc_node = False
    not_support_z_linux_node = False

    for versions, bundles in vetted_versions.items():
        for bundle_name, bundle_ver in bundles.items():
            if bundle_name in z_support_initial_versions:
                cur_ver = bundle_ver[0:bundle_ver.find('-')]
                if version.parse(cur_ver) < version.parse(z_support_initial_versions[bundle_name]) \
                    or version.Version(cur_ver).major in (HOSTOS_FIPS_MAJOR, HOSTOS_REDHAT_MAJOR, HOSTOS_5_X_MAJOR):
                    not_support_z_node = True
                elif version.Version(cur_ver).major == HOSTOS_6_X_MAJOR:
                    not_support_z_ssc_node = True
                elif version.Version(cur_ver).major in (HOSTOS_2_X_MAJOR, HOSTOS_3_X_MAJOR):
                    not_support_z_linux_node = True

    if not_support_z_node or (not_support_z_ssc_node and not_support_z_linux_node):
        print("No z nodes would be deployed")
        return NodeType.NO_Z
    elif not_support_z_ssc_node:
        print("No z SSC nodes would be deployed")
        return NodeType.NO_Z_SSC
    elif not_support_z_linux_node:
        print("No z Linux nodes would be deployed")
        return NodeType.NO_Z_LINUX

    print("All z nodes would be deployed")
    return NodeType.ALL


def main():

    if not (len(sys.argv) == 5 and sys.argv[1] == "mds") and \
        not (len(sys.argv) == 6 and sys.argv[1] == "ddtool"):
        print("""
        add_nodelist_flags.py: invalid usage
        Please use this script as below:
        For MDS:
            add_nodelist_flags.py mds <vetted_version_yaml> <inventory_yml> <eyaml>
        For ddtool:
            add_nodelist_flags.py ddtool <vetted_version_yaml> <inventory_yml> <input_hjson> <output_hjson>
        """)
        sys.exit(1)

    if sys.argv[1] == "mds":
        vetted_ver_file = sys.argv[2]
        inventory_file  = sys.argv[3]
        eyaml = sys.argv[4]
    else:
        vetted_ver_file = sys.argv[2]
        inventory_file  = sys.argv[3]
        in_hjson_file   = sys.argv[4]
        out_hjson_file  = sys.argv[5]

    support_nodes_type = check_releasebundles_support_z(vetted_ver_file)

    nodelist_flag = get_flags(inventory_file, support_nodes_type)

    if sys.argv[1] == "mds":
        add_flags_mds(eyaml, nodelist_flag)
    else:
        add_flags_ddt(in_hjson_file, out_hjson_file, nodelist_flag)


if __name__ == "__main__":
    main()

