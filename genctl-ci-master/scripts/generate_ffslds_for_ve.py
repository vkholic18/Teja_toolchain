import yaml
import os
import argparse

def generate_ffslds(template_file, vetted_file, input_file, output_path, env_name, comonent_name):
    """
    Generate the featureflagsetld.yaml file based on the template provided

    :param template_file: template to use for generating the yaml
    :param vetted_file: The vetted-versions file which contains all the variation values
    :param input_file: The input ve file that contains variations specific to a given environment
    :param output_path: The location where the ffsld.yaml is written
    :param env_name: The name of the current environment (ie, mz6-dev)
    :param comonent_name: The name of the component being processed (ie, rias)

    """
    output_dir = os.path.dirname(output_path)
    os.makedirs(output_dir)
    print("output_dir is : " + output_dir)

    # Load the first YAML file
    with open(template_file, 'r') as f:
        data1 = yaml.safe_load(f)

    # Load the second YAML file
    with open(vetted_file, 'r') as f:
        data2 = yaml.safe_load(f)

    # Load the second YAML file
    with open(input_file, 'r') as f:
        data3 = yaml.safe_load(f)

    # Iterate over the feature_flags in the second file
    for entry in data2['apps']['feature_flags']['vpc-ci']:
        data1['data'][entry['name']] = entry['default']['variation_value']
    
    if comonent_name == "genctl":
        data1['data']['genctl-globals'] = env_name
    else:
        data1['data']['region-globals'] = env_name

    if 'spec' in data1 and 'identityRef' in data1['spec'] and 'env' in data1['spec']['identityRef']:
        for env in data1['spec']['identityRef']['env']:
            if env['name'] == 'mzone':
                env['value'] = env_name
                break
            elif env['name'] == 'region':
                env['value'] = env_name
                break

    if 'apps' in data3 and 'feature_flags' in data3['apps'] and 'vpc-ci' in data3['apps']['feature_flags']:
            for every_ff in data3['apps']['feature_flags']['vpc-ci']:
                name = every_ff['name']
                version = every_ff['default']['variation_value']
                data1['data'][name] = version

    # Write the result to a new YAML file
    with open(output_path, 'w') as f:
        yaml.dump(data1, f, default_flow_style=False, sort_keys=False)


components = ['rias', 'rias-etcd', 'genctl']

def get_folder_names(root_dir, ffsld_output_dir, dev_regions_loc):
    """
    Process all the environments and components for the given root directory

    :param root_dir: The location of the dev-regions repo
    :param ffsld_output_dir: The location to write the generated files to

    """
    for dirpath, dirnames, filenames in os.walk(root_dir):
        for dirname in dirnames:
            for component in components:
                print("Processing the env: " + dirname)
                print("Processing the component: " + component)
                template_file = dev_regions_loc+"/ffsld_templates/"+component+"/featureflagsetld.yaml"
                vetted_file = dev_regions_loc+"/vetted-versions.yaml"
                input_file = dev_regions_loc+"/ve/"+dirname+"/"+dirname+".yaml"
                output_file = ffsld_output_dir+"/ffsld/"+component+"/"+dirname+"/featureflagsetld.yaml"
                generate_ffslds(template_file, vetted_file, input_file, output_file, dirname, component)

def parse_args():
    """
    Parse the arguments passed when calling this file.
    :return: args
    """
    parser = argparse.ArgumentParser(description="Parser to take required and optional values for the script")
    parser.add_argument('-f', '--dev_regions_repo_path', help="Location of the dev-regions repo", required=True, dest="dev_regions_loc")
    args = parser.parse_args()
    return args


def main():
    """
    Main function, determines what the script should do when called
    """
    # Setup variables
    args = parse_args()
    dev_regions_loc = args.dev_regions_loc
    ve_path = dev_regions_loc+"/ve"
    print(dev_regions_loc)
    print(ve_path)
    ffsld_output_dir = dev_regions_loc+"/FFSLD_ARTIFACTS"
    get_folder_names(ve_path, ffsld_output_dir, dev_regions_loc)

if __name__ == "__main__":
    main()
