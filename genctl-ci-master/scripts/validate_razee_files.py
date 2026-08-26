#!/usr/bin/env python3

##
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
##
"""
This script validates the razee files in a workspace's hack/deploy/razee directory using the region-globals-mtp and common-globals and workspace-level-configmap's name.

(Example) Use command below to validate razee files in cloudinit-workspace using params:
    commonGlobals=rias-globals-repo/dev-szr/common-globals.yaml
    regionGlobals=rias-globals-repo/dev-szr/mascd-1.yaml
    svcLevelConfigmap=configmap-cloudinit-service.yaml
    workspaceRazeeDir=cloudinit-workspace/hack/deploy/razee

python3 scripts/validate_razee_files.py --commonGlobals=rias-globals-repo/dev-szr/common-globals.yaml --regionGlobals=rias-globals-repo/dev-szr/mascd-1.yaml --svcLevelConfigmap=configmap-cloudinit-service.yaml --workspaceRazeeDir=cloudinit-workspace/hack/deploy/razee
"""

import argparse
import os
import re
import json
import logging
from os import path
import oyaml as yaml
from pybars import Compiler

def parseYamlFiles(yamlFile):
    """
    Purpose:
    Takes the file name of the yaml file and returns the
    yaml data in the file in the form of python data structures

    Params:
    yamlFile: name of the yaml file to safe_load
    """
    print("opening file ", yamlFile," ....")
    with open(yamlFile) as f:
        file_yaml = yaml.safe_load_all(f)
        return list(file_yaml)

class ValidateMTPException(Exception):
    """
    Purpose:
    Custom Exception class to raise and
    catch more simple and concise errors/msgs
    """
    def __init__(self, message, error=None):
        self.message = message
        self.error = error

        if error:
            message = f"{message}\nError: {error}"
        super().__init__(message)


def getRawJsonData(data):
    """
        convert all the literal blocks of the data retrieved
        from the template into json thus easier to access
    """
    fmtData = {}
    err = None
    if type(data) == str:
        data = json.loads(data)
    for k, v in data.items():
        if type(v) is str:
            if v.find("{") != -1:
                templatizedVar2 = re.match(r'^\{\{.+\}\}$', v)
                templatizedVar3 = re.match(r'^\{\{\{.+\}\}\}$', v)
                if not (templatizedVar3 or templatizedVar2):
                    # nested json literal
                    try:
                        v = json.loads(v)
                    except json.decoder.JSONDecodeError as err:
                        logging.error(f"Invalid JSON for {k} {v}: {err}")
                        return fmtData, err
        elif type(v) is dict:
            # nested json literal
            v, err = getRawJsonData(v)
        if k not in fmtData.keys():
            fmtData.update(dict({k: v}))
        else:
            err = f"Duplicate Keys for {k} {v}"
            logging.error(err)
            return fmtData, err
    return fmtData, err

def isMTP(file):
    """
    Purpose:
    Check if the input file is a MustacheTemplate

    Params:
    file: input file to check
    """
    mtpYaml = parseYamlFiles(file)
    # There will not be more than 1 template in the file if the kind is mustache.
    return mtpYaml[0]["kind"] == "MustacheTemplate"

def getKind(mtp):
    """
    Purpose:
    Checks and returns the type (kind) of kubernetes resource input MustacheTemplate file

    Params:
    file: input MustacheTemplate file to check
    """
    # again here we care only about the first one returned
    mtpYaml = (parseYamlFiles(mtp))[0]
    try:
        if type(mtpYaml["spec"]["strTemplates"][0]) is dict:
            logging.debug(f"type of parsed {mtp} is a dictionary")
            return mtpYaml["spec"]["strTemplates"][0]["kind"]
        else:
            logging.debug(f"type of parsed {mtp} is not a dictionary")
            try:
                strTemplates = yaml.safe_load(mtpYaml["spec"]["strTemplates"][0])
                return strTemplates["kind"]
            except:
                logging.debug(f"type of parsed {mtp} is not a dictionary even after the safe_load")
                strTemplates = str(mtpYaml["spec"]["strTemplates"][0].encode('utf-8'), 'utf-8')
                mat = re.search("(kind: )([a-zA-Z0-9]+)", strTemplates)
                if mat:
                    return strTemplates[mat.span()[0]:mat.span()[1]].split(": ")[1]
                else:
                    return None

    except:
        return mtpYaml["spec"]["templates"][0]["kind"]

def yamlToJson(regionGlobalJsonData):
    """
    Purpose:
    Converts each entry of region-globals data to json

    Params:
    file: input region-globals data to convert
    """
    data = {}
    for key in regionGlobalJsonData.keys():
        if regionGlobalJsonData[key] != "":
            try:
                data[key] = json.loads(regionGlobalJsonData[key])
            except:
                data[key] = regionGlobalJsonData[key]
    return data

def check(sourceMtp, configData):
    """
    Purpose:
    Checks if sourceMtp's env array has all the keys
    listed and available in source configmap data before
    script renders the mustache template configmap data

    Params:
    sourceMtp: mustache template to validate
    configData: source configmap data to validate mtp
    """
    sourceMtpYaml = (parseYamlFiles(sourceMtp))[0]
    envMtpYaml = sourceMtpYaml["spec"]["env"]
    checkPassed = True
    for i in range(len(envMtpYaml)):
        if envMtpYaml[i]["name"] not in configData.keys():
            if "configMapKeyRef" in envMtpYaml[i]["valueFrom"].keys() and \
                 envMtpYaml[i]["valueFrom"]["configMapKeyRef"]["key"] in configData.keys():
                configData[envMtpYaml[i]["name"]] = configData[envMtpYaml[i]
                                                               ["valueFrom"]["configMapKeyRef"]["key"]]
            elif "genericKeyRef" in envMtpYaml[i]["valueFrom"].keys() and \
                 envMtpYaml[i]["valueFrom"]["genericKeyRef"]["key"] in configData.keys():
                configData[envMtpYaml[i]["name"]] = configData[envMtpYaml[i]
                                                               ["valueFrom"]["genericKeyRef"]["key"]]
            else:
                raise KeyError(f"Cannot find key {envMtpYaml[i]['name']}")

    return checkPassed

def mtpToYaml(sourceMtp, configData, outputYamlFile, regionGlobalsOutputDirName, isGlobals):
    """
    Purpose:
    Method mtpToYaml renders the sourceMtp mustache template
    to yaml using configData configmap data and writes
    rendered yaml to regionGlobalsOutputDirName/outputYamlFile

    Params:
    sourceMtp: source-mtp to render
    configData: configmap's data to use while rendering source-mtp
    outputYamlFile: name of the output rendered yaml file
    regionGlobalsOutputDirName: name of the output directory to write outputYamlFile to
    isGlobals: flag used to determine how to convert the mtp to string (sourceStrTemplatesYaml)
    """
    sourceMTPYaml = (parseYamlFiles(sourceMtp))[0]

    # Convert the safe_loaded json to strings
    if isGlobals:
        try:
            sourceStrTemplates = yaml.safe_load(sourceMTPYaml["spec"]["strTemplates"][0])
            sourceStrTemplatesYaml = yaml.dump(sourceStrTemplates, allow_unicode=True)
        except:
            sourceStrTemplatesYaml = yaml.dump(sourceMTPYaml["spec"]["templates"][0], allow_unicode=True)
    else:
        sourceStrTemplatesYaml = str(sourceMTPYaml["spec"]["strTemplates"][0].encode('utf-8'), 'utf-8')

    # Compile the string template
    compiler = Compiler()
    template = compiler.compile(sourceStrTemplatesYaml)

    # Add helpers
    def _eq(this, v1, v2):
        return v1 == v2
    def _ne(this, v1, v2):
        return v1 != v2
    def _lt(this, v1, v2):
        return v1 < v2
    def _gt(this, v1, v2):
        return v1 > v2
    def _lte(this, v1, v2):
        return v1 <= v2
    def _gte(this, v1, v2):
        return v1 >= v2
    def _or(this, v1, v2):
        return v1 or v2
    def _and(this, v1, v2):
        return v1 and v2
    def _divide(this, v1, v2):
        return v1/v2
    def _add(this, v1, v2):
        return v1 + v2
    def _split(this, v1, v2):
        return v1.split(v2)
    def _substring(this, data, startIndex, endIndex):
        if endIndex is None:
            return data.substring(startIndex)
        else:
            return data.substring(startIndex,endIndex)
    def _includes(this, arr, valueToFind, fromIndex):
        if fromIndex is None:
            return arr.includes(valueToFind)
        else:
         return arr.includes(valueToFind,fromIndex)

    helpers = {
        'eq': _eq,
        'ne': _ne,
        'lt': _lt,
        'gt': _gt,
        'lte': _lte,
        'gte': _gte,
        'or': _or,
        'and': _and,
        'divide': _divide,
        'add': _add,
        'split': _split,
        'substring': _substring,
        'includes': _includes,
    }

    # Render the template
    output = template(configData, helpers=helpers)

    # Write the rendered output to out/file
    # TODO can be eliminated
    print("writing to ", regionGlobalsOutputDirName, "/", outputYamlFile)
    with open(regionGlobalsOutputDirName + "/" + outputYamlFile, "w") as f:
        f.write(output)
    return output

def validateYaml(yamlFile):
    """
    Purpose:
    Checks if handlebars rendered yaml is valid

    Params:
    renderedYaml: rendered yaml to validate
    """
    try:
        yaml.safe_load_all(yamlFile)
        return yamlFile
    except yaml.YAMLError as e:
        raise ValidateMTPException("Failed to Validate Yaml", e)

def validateRazeeFile(razeeFile, regionGlobalsYaml, regionGlobalsOutputDirName, flag):
    """
    Purpose:
    Calls yamlToJson method first to convert all the regionGlobalsYaml data to json.
    Calls the check method to validate env array of razeeFile.
    If the check passes, it calls mtpToYaml to convert razeeFile mtp to yaml.
    After the conversion validateYaml is called to check
    if the converted yaml is valid.

    Params:
    razeeFile: razeeFile mtp to validate
    regionGlobalsYaml: region-globals to use while rendering razeeFile
    regionGlobalsOutputDirName: output directory to write the rendered region-globals yaml file
    flag: flag used to determine how to convert the mtp to string (sourceStrTemplatesYaml)
    """
    regionGlobalJson = yaml.safe_load(regionGlobalsYaml)
    regionGlobalsJsonData = yamlToJson(regionGlobalJson["data"])
    return validateRazeeFileImpl(razeeFile, regionGlobalsJsonData, regionGlobalsOutputDirName, flag)

def validateRazeeFileImpl(razeeFile, dataDict, outputDirName, flag):
    """
    Purpose:
    Takes the razeeFile and checks it against it dataDict to see that all the params
    being imported to check if they are there in the dictionary. If it cannot find the keys
    it throws a KeyError excpetion. If all the data can be found, it tries to render the
    template by calling mtpToYaml.

    Params:
    razeeFile: file containing the mtp to be rendered
    dataDict: dict holding all the data to be rendered
    outputDirName: File to store the rendered yaml
    """
    try:
        if not check(razeeFile, dataDict):
            raise KeyError("cannot find keys")
    except KeyError as e:
        raise ValidateMTPException(f"Couldnt find a key in {razeeFile} in [\"spec\"][\"env\"]", e)
    outputRazeeFile = razeeFile.split(".yaml")[0].split("/")
    outputRazeeFile = outputRazeeFile[len(outputRazeeFile)-1]  + "_out.yaml"
    outputRazeeYaml = mtpToYaml(razeeFile, dataDict, outputRazeeFile, outputDirName, flag)
    try:
        return validateYaml(outputRazeeYaml)
    except yaml.YAMLError as e:
        raise ValidateMTPException(f"Failed to Validate {razeeFile} yaml file", e)

def getGlobals(regionGlobals, commonGlobals, regionGlobalsOutputDirName):
    """
    Purpose:
    Calls the check method to validate env array of regionGlobals.
    If the check passes, it calls mtpToYaml to convert mtp to yaml.
    After the conversion validateYaml is called to check
    if the converted yaml is valid.

    Params:
    regionGlobals: region-globals-mtp to validate
    commonGlobals: common-globals to use while rendering region-globals-mtp
    regionGlobalsOutputDirName: output directory to write the rendered region-globals yaml file
    """
    commonGlobalsJson = (parseYamlFiles(commonGlobals))[0]
    try:
        check(regionGlobals, commonGlobalsJson["data"])
    except KeyError as e:
        raise ValidateMTPException(f"Couldnt find a key in {regionGlobals} in [\"spec\"][\"env\"]", e)
    outputGlobalFile = regionGlobals.split(".yaml")[0].split("/")
    outputGlobalFile = outputGlobalFile[len(outputGlobalFile)-1]  + "_out.yaml"
    regionGlobalsYaml = mtpToYaml(regionGlobals, commonGlobalsJson["data"], outputGlobalFile, regionGlobalsOutputDirName, True)
    try:
        return validateYaml(regionGlobalsYaml)
    except yaml.YAMLError as e:
        raise ValidateMTPException(f"Failed to Validate {regionGlobals} yaml file", e)


def renderRazeeFilesImpl(mtpFileList, dataDict, outputDirName):
    """
    Purpose:
    Loops over all the files in mtpFileList and renders them. If the rendered yaml has a configmap,
    the data from the configmap is added to the dataDict. The rendered yaml is also written into
    outputDirName
    Params:
    mtpFileList: List of files to be rendered
    dataDict: the data that will be used to rendered the MTP
    outputDirName: File that the rendered MTP will be placed in.
    """
    numRendered = 0
    numLoops = 0
    mtpRenderedFileList = []
    while numRendered < len(mtpFileList) and numLoops < len(mtpFileList):
        numLoops += 1
        for filePath in mtpFileList:
            try:
                mtpRenderedFileList.index(filePath)
            except ValueError as e:
                pass
            else:
                continue
            try:
                kind = getKind(filePath)
                flag = kind == "RemoteResourceS3"
                renderedData = validateRazeeFileImpl(filePath, dataDict, outputDirName, flag)
                renderedYaml = list(yaml.safe_load_all(renderedData))
                for item in renderedYaml:
                    if type(item) is dict:
                        if item["kind"] == "ConfigMap":
                            data, err = getRawJsonData(item['data'])
                            if not err:
                                dataDict.update(data)
                            else:
                                logging.error(err)
                                raise err
                    else:
                        logging.error(f"The following part of the rendered mtp is not a dict, skipping its parsing", item)
            except ValidateMTPException as e:
                logging.info(str(e))
            except Exception as e:
                raise e
            else:
                numRendered += 1
                mtpRenderedFileList.append(filePath)
    return dataDict, numRendered


def renderRazeeFiles(workspaceRazeeDir, regionGlobalsYaml, regionGlobalsOutputDirName):
    """
    Purpose:
    Loops over all the files and sorts them into files that are not templates and files that
    are templates. From the files that are not templates it takes the configmaps and adds
    those to the dataDict.
    From the ones that are MTPs, the configmaps are rendered first and the output of the
    configmaps are added to the dataDict.
    Then finally, all the other MTPs are rendered.

    Params:
    workspaceRazeeDir: the workspace folder to render
    regionGlobalsYaml: the region global file that has already been rendered
    regionGlobalsOutputDirName: Folder to put the rendered files in.
    """
    files = os.listdir(workspaceRazeeDir)
    workspaceRazeeDir += "/"
    mtpFileList = []
    mtpConfigMapFileList = []
    regionGlobalJson = yaml.safe_load(regionGlobalsYaml)
    regionGlobalsJsonData = yamlToJson(regionGlobalJson["data"])
    dataDict = {}
    dataDict.update(regionGlobalsJsonData)
    for file in files:
        filePath = workspaceRazeeDir + file
        if path.isfile(filePath):
            fileYaml = parseYamlFiles(filePath)
            # first check if it is an MTP. If MTP, then we need to render it.
            # add it to the list of files that need to be rendered.
            mtpKind = isMTP(filePath)
            logging.debug(f"Current file: {file}, isMTP?: {mtpKind}")
            if mtpKind:
                kind = getKind(filePath)
                if kind == "ConfigMap":
                    mtpConfigMapFileList.append(filePath)
                else:
                    mtpFileList.append(filePath)
            else:
                for item in fileYaml:
                    if type(item) is dict:
                        if item["kind"] == "ConfigMap":
                            data, err = getRawJsonData(item['data'])
                            if not err:
                                dataDict.update(data)
                            else:
                                logging.error(err)
                                raise err
        elif path.isdir(filePath):
            #recursively load mtp files again
            logging.debug(f"{filePath} is a directory so recursing to list files")
            renderRazeeFiles(filePath, regionGlobalsYaml, regionGlobalsOutputDirName)

    # at this point we have all the config maps loaded in and the
    # files that are mtps in a list.
    # First go through the MTPs and if the kind is configmap then first
    # render that MTP.
    # then go through the other MTPs and render them.
    dataDict['image-version'] = "11"
    dataDict['cos-url'] = "https://s3.us-south.cloud-object-storage.appdomain.cloud"
    dataDict['cos-bucket-name'] = "development-workspace-artifacts"
    dataDict, numConfigMapRendered = renderRazeeFilesImpl(mtpConfigMapFileList, dataDict, regionGlobalsOutputDirName)
    if numConfigMapRendered != len(mtpConfigMapFileList):
        raise ValidateMTPException(f"Failed to validate all Configmaps total num configmaps {len(mtpConfigMapFileList)} num rendered {numConfigMapRendered}")

    dataDict, numRendered = renderRazeeFilesImpl(
        mtpFileList, dataDict, regionGlobalsOutputDirName)
    if numRendered != len(mtpFileList):
        raise ValidateMTPException(
            f"Failed to validate all mtps total num mtps {len(mtpFileList)} num rendered {numRendered}")


def main():
    parser = argparse.ArgumentParser(
        usage=(
            """
            (Example) Use command below to validate razee files in cloudinit-workspace using params:
                commonGlobals=rias-globals-repo/dev-szr/common-globals.yaml
                regionGlobals=rias-globals-repo/dev-szr/mascd-1.yaml
                workspaceRazeeDir=cloudinit-workspace/hack/deploy/razee
                outputDir=/tmp/scripts

            python3 scripts/validate_razee_files.py --commonGlobals=rias-globals-repo/dev-szr/common-globals.yaml --regionGlobals=rias-globals-repo/dev-szr/mascd-1.yaml --svcLevelConfigmap=configmap-cloudinit-service.yaml --workspaceRazeeDir=cloudinit-workspace/hack/deploy/razee -outputDir=/tmp/scripts
            """
        ),
    )
    parser.add_argument("--commonGlobals", help="input the name of the common globals file")
    parser.add_argument("--regionGlobals", help="input the name of the region globals file")
    parser.add_argument("--workspaceRazeeDir", help="input the name of the workspace's razee directory")
    parser.add_argument("--outputDir", help="output dir where rendered files are placed", default="/tmp/scripts")

    args = parser.parse_args()

    regionGlobals = args.regionGlobals
    commonGlobals = args.commonGlobals
    workspaceRazeeDir = args.workspaceRazeeDir
    outputDir = args.outputDir

    # removes and recreates regionGlobalsOutputDirName if it exists, else just creates it
    regionGlobalsOutput = regionGlobals.split(".yaml")[0].split("/")
    regionGlobalsOutputDirName = outputDir + "/" + regionGlobalsOutput[len(regionGlobalsOutput) - 1] + "_out"
    if os.path.isdir(regionGlobalsOutputDirName):
        files = os.listdir(regionGlobalsOutputDirName)
        for file in files:
            os.remove(regionGlobalsOutputDirName + "/" + file)
        os.rmdir(regionGlobalsOutputDirName)
    os.mkdir(regionGlobalsOutputDirName)

    logging.basicConfig(level=logging.INFO)

    # render region-globals using common-globals
    try:
        logging.info("Validating regionGlobals now....")
        regionGlobalsYaml = getGlobals(regionGlobals, commonGlobals, regionGlobalsOutputDirName)
        logging.info(f"Successfully Validated {args.regionGlobals} region-globals yaml file")
    except yaml.YAMLError as e:
        raise SystemExit(ValidateMTPException("Failed to Validate region-globals yaml file", e))

    renderRazeeFiles(workspaceRazeeDir, regionGlobalsYaml, regionGlobalsOutputDirName)

if __name__ == "__main__":
    main()
