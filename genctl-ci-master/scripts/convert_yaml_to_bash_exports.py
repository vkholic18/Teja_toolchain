# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Takes a one level key value YAML file as input and generates a .sh file with bash export commands
#              It does some formatting on the key, specifically converts lowercase to uppercase and - to _ 
#              For the value it encloses in quotes and trim spaces
#              As an example, if the entry in yaml is my-key: myvalue then, in the file it will be export MY_KEY="myvalue"

#
# Use:
#    python3 convert_yaml_to_bash_exports.py <PATH_OF_YAML_FILE> <PATH_OF_SH_FILE_TO_GENERATE>

import os
import sys
import yaml

def main():
    # First check that we have two arguments (In addition to the first argument which is the name of the script itself)
    if len(sys.argv) == 3:
        
        # Set the two args in variables for easier use
        path_to_yaml_file = sys.argv[1]
        path_of_sh_file_to_generate = sys.argv[2]

        # Check the first argument is a path to a file that exists
        if os.path.isfile(path_to_yaml_file):
            
            # Load the file
            with open(path_to_yaml_file,'r') as f:
                yaml_content = yaml.safe_load(f)

                # Declare an empty array that will hold the string with the export commands
                res = []

                # Iterate    
                for k, v in yaml_content.items():
                    
                    # Do some processing to the key (Convert to uppercase and replace - with _ )
                    # For example: my-key --> MY_KEY
                    processed_key = k.upper().replace('-','_')

                    # Set on a variable to do some processing on the value
                    processed_value = v

                    # Special processing for booleans
                    if type(v) is bool:
                        processed_value = str(v).lower()

                    # Do some processing in the value (Strip spaces and enclose everything in quotes)
                    processed_value = f"\"{str(processed_value).strip()}\""
                    
                    # Add to the list the export line
                    res.append(f"export {processed_key}={processed_value}")

                # Dump all the strings to a file
                with open(path_of_sh_file_to_generate, "w") as outfile:
                    outfile.write("\n".join(res))
        else:
            print(f"Could not find a file {path_to_yaml_file}")
            sys.exit(1)
    else:
        print("We expected to have two arguments in this script")
        sys.exit(1)

if __name__ == "__main__":
    main()
