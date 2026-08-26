# Packages flow

We refer as packages flow as the flow of artifacts that are not docker images, for example: debian packages, golang binaries, etc

## Background

In previous flows (Concourse), VPC CI team was not much involved with the packages, but rather focusing on the docker images

As part of the migration to OnePipeline, we start the involvement on the packages flow, in order to make them part of the inventory

The basics of the flow are:

1. Upload the packages (Happening either in OnePipeline or in Travis)

2. Download the packages and make OnePipeline save_artifact

3. Create and upload JSON file that contains the information from the packages 

4. Move packages (And JSON with information) from pre_release to vetted

5. Move packages from vetted to final destination

6. Download JSON file, parse it and do cocoa inventory add commands based on the packages included on the JSON

## Packages definition

In order for this whole flow to work, we need an explicit definition of the packages being built

This needs to be done in the build-meta.yaml file

The structure of the build-meta.yaml section for packages is as the following:

```yaml
packages:
    <PACKAGE_TYPE>:
        <ARCH>: <PATH_IN_ARTIFACTORY_IN_FINAL_DESTINATION>/<PREFIX_OF_PACKAGE_NAME> 
```

For example:

```yaml
packages:
  debian:
    amd64: pool/compute/target-tools/cld-computetools
```

If the packages are built in OnePipeline, then this definition is used on the upload of the packages, if not then is used for the download and the moving of the packages

Important: 

PREFIX_OF_PACKAGE_NAME is considered the string after the last "/", everything that comes before is considered PATH_IN_ARTIFACTORY_IN_FINAL_DESTINATION

## Upload of packages

When uploaded, packages should be set on the following path in Artifactory:

```bash
wcp-genctl-sandbox-generic-local/vpc_packages/pre_release/<REPO_ORG>/<REPO_NAME>/<SHORT_SHA>/<PACKAGE_TYPE>/<ARCH>/<PATH_IN_ARTIFACTORY_IN_FINAL_DESTINATION>/<PACKAGE_NAME>
```

Where 

REPO_ORG: The organization of the repo (For example: genctl, cloudlab)

REPO_NAME: The name of the repository

SHORT_SHA: First 12 characters of the SHA of the current execution

PACKAGE_TYPE: The package type (For example: debian)

ARCH: The package architecture (For example: amd64, s390x)

PATH_IN_ARTIFACTORY_IN_FINAL_DESTINATION: The path in which the package will be in its final destination - Without the repository itself 

PACKAGE_NAME: The actual full package name (For example: cld-computetools_1.0.54~20230917120339.c5f6f71_amd64.deb)

PACKAGE_NAME should start with the PREFIX_OF_PACKAGE_NAME defined in the build-meta.yaml

## Download of packages

For downloading packages, CI code loops over the build-meta.yaml definitions, looking for them in the path that they are expected to be

Since the PACKAGE_NAME usually is dynamic (Ex: Might contain some timestamp) and changing between different pipeline runs, we don't know exactly the name of the file we need to download but we assume that is the only file that starts with the PREFIX_OF_PACKAGE_NAME that sits under the path we are looking for

If for some reason we can't find the relevant package, the download and save artifact script will fail, failing the pipeline


