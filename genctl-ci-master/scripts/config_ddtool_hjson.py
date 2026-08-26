#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

import hjson
import sys
import yaml

infile  = sys.argv[1]
outfile = sys.argv[2]
operation = sys.argv[3]

with open(infile) as orig_file:
    data = hjson.load(orig_file)

if operation == 'mzone':
    # update mzone
    mzone = sys.argv[4]
    data['mzone'] = mzone
    data['repodir'] = f'$home/{mzone}/repos'
    data['ngsecdir'] = f'$home/{mzone}/.ngsec'
    #update component versions
    version_file = sys.argv[5]
    with open(version_file, 'r') as version_data:
        vetted_versions = yaml.safe_load(version_data)
    # loop through ddt hjos template
    for comp, comp_data in data['components'].items():
        for pkg, pkg_data in comp_data['packages'].items():
            print("Package: %s/%s:%s" % (comp, pkg, pkg_data['tag']))
            if pkg == 'hostos-post-config-release':
                for versions, bundles in vetted_versions.items():
                    for bundle_name, bundle_ver in bundles.items():
                        if bundle_name == 'hostos-config-release':
                            data['components'][comp]['packages'][pkg]['tag'] = bundle_ver
            else:
                #loop through vetted versions
                for versions, bundles in vetted_versions.items():
                    for bundle_name, bundle_ver in bundles.items():
                        if bundle_name == pkg:
                            data['components'][comp]['packages'][pkg]['tag'] = bundle_ver
                            print("Package: %s/%s:%s" % (comp, pkg, pkg_data['tag']))

elif operation == 'prep-component':
    # remove other components
    component = sys.argv[4]
    comp_to_remove = [c for c in data['components'].keys() if c != component]
    for c in comp_to_remove:
        del data['components'][c]

    if len(sys.argv) == 9:
        # update release tag and indicate it is in local registry
        package = sys.argv[5]
        tag = sys.argv[6]
        data['components'][component]['packages'][package]['tag'] = tag
        if package  == 'hostos-kernel-patch-release':
            data['components'][component]['packages']['hostos-kernel-patch-release']['deploy'] = 'yes'
        if package  == 'hostos-config-release':
            data['components'][component]['packages']['hostos-post-config-release']['tag'] = tag
        # remove other pakages
        package_only = sys.argv[7]
        deploy_component_only = sys.argv[8]
        if deploy_component_only == 'true':
            pack_to_remove = [p for p in data['components'][component]['packages'].keys() if not p.startswith(component)]
            for p in pack_to_remove:
                del data['components'][component]['packages'][p]
        elif package_only == 'true':
            pack_to_remove = [p for p in data['components'][component]['packages'].keys() if p != package]
            for p in pack_to_remove:
                del data['components'][component]['packages'][p]
    # remove pakages with 'deploy=no' flag
    for comp, comp_data in data['components'].items():
        # iterate a copy of the dict as python does not allow to iterate an object and mutate it.
        for pkg, pkg_data in comp_data['packages'].copy().items():
            if pkg_data.get('deploy'):
                is_deploy = pkg_data.get('deploy')
                if is_deploy=='no':
                    print("Removing package " + pkg + " from hjson")
                    del data['components'][component]['packages'][pkg]

else:
    print(f'ERROR: unexpected operation "{operation}"')
    sys.exit(1)

with open(outfile, 'w') as new_file:
    hjson.dump(data, new_file, indent=4)
