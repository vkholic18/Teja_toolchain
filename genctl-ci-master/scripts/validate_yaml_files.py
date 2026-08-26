##
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
##
import oyaml as yaml
import argparse

def parseYamlFiles(yamlFile):
    with open(yamlFile, "r") as stream:
        print("Loading file:",yamlFile)
        try:
            # using a for loop because for some reason if there
            # is a multi-part yaml then safe_load_all does not
            # seem to catch yaml errors. So taking the objects
            # individually and passing them through linting.
            for data in yaml.safe_load_all(stream):
              yaml.safe_load(yaml.dump(data))
        except yaml.YAMLError as e:
            raise SystemExit(e)
    print("Validated file:", yamlFile)

def main():
    parser = argparse.ArgumentParser(
        usage=(
            """
            python3 validate_yaml_files.py --file=<filename>
            """
        ),
    )

    parser.add_argument("--file", help="input the file that needs to be linted")
    args = parser.parse_args()
    parseYamlFiles(args.file)

if __name__ == "__main__":
    main()
