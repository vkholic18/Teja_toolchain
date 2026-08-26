#! /usr/bin/env python3

# 1- Parse only mustache templates
# 2- Check duplicates only in configMapKeyref
# 3- Validation success with same key but from different resource
# 4- Should validate yaml with multiple sections with --- separator

import argparse
import yaml

def validate_mtp(fp):
    """
    Checks duplicate configmap key references in a mtp file
    """
    print("Checking for duplicate keys in", fp)
    try:
        fn = fp.split("/")[-1]
        with open(fp, "r") as f:
            doc = yaml.safe_load(f)
        return parse_for_duplicates_in_mtp(doc, fn)
    except yaml.composer.ComposerError:
        print(
            "INFO: {} has multiple documents. Checking for duplicate keys...".format(fn)
        )
        status = True
        with open(fp, "r") as f:
            docs = yaml.load_all(f, Loader=yaml.FullLoader)
            for doc in docs:
               s = parse_for_duplicates_in_mtp(doc, fn)
               if not s:
                   status = False
        return status
    except Exception as e:
        print("Error occurred while checking duplicates.\nError:", e)


def parse_for_duplicates_in_mtp(doc, fileName):
    status = True 
    if doc["kind"] == "MustacheTemplate":
        namedict = {}
        dict = {}
        if "env" in doc["spec"].keys():
            for entry in doc["spec"]["env"]:
                if "configMapKeyRef" in entry["valueFrom"].keys():
                    cm = entry["valueFrom"]["configMapKeyRef"]
                    entryName = entry["name"]
                    try:
                        valueType = cm["type"]
                    except:
                        status = False
                        print(
                            "\n{:<70} {:<50}\n".format(
                                "WARNING: Missing type in configMapKeyRef of entry: {}".format(entryName),
                                "File name: {}".format(fileName),
                             )
                        )

                    if cm["key"] not in dict.keys():
                        dict[cm["key"]] = cm["name"]
                        namedict[cm["key"]] = entryName
                    elif dict[cm["key"]] == cm["name"]:
                        status = False
                        print(
                            "\n{:<70} {:<50} {:<70}\n".format(
                                "WARNING: Duplicate key: {}".format(cm["key"]),
                                "File name: {}".format(fileName),
                                "Previously used by entry {}".format(namedict[cm["key"]])
                            )
                        )
    return status



def get_data(path):
    f = open(path)
    data = f.read().splitlines()
    f.close()
    return data

def main():
    parser = argparse.ArgumentParser(
        usage=(
            """
            (Example) Use command below to check for duplicate keys and missing types in mtp files in a directory

            python3 scripts/razee_check_duplicate_keys/razee_check_duplicate_keys.py --list=<file name containing new line delimited razee mtp file names>
            """
        ),
    )

    parser.add_argument(
        "--list", help="file name containing new line delimited razee mtp file names"
    )
    args = parser.parse_args()
    file_list = args.list
    try:
        files = get_data(file_list)
        status = True
        for f in files:
            if not validate_mtp(f):
                status = False
        if status:
            print("Validation successful - No problems found")
        else:
            print("WARNING: Validation failed")
    except FileNotFoundError:
        print("Could not find file with name:'{}'".format(file_list))
    except Exception as e:
        print(e)

if __name__ == "__main__":
    main()
