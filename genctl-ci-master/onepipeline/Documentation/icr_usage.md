# IBM Cloud Container Registry (ICR) Migration Guide

## Introduction
As part of the migration from Artifactory to IBM Cloud Container Registry (ICR), this guide provides step-by-step instructions on accessing ICR, viewing available namespaces, logging in, listing images, and pushing images to the sandbox. Following these steps will ensure proper usage of ICR.

## Getting Access to ICR
There is no specific access required to get access to ICR. Gaining access to the toolchains will grant you access to ICR.
You can follow this [documentation](https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/onepipeline/Documentation/OnePLMigrationGuide.md#getting-access-to-the-toolchains) to get access to toolchains/ICR.

## Available Namespaces
You will have access to two namespaces in the `us-south` region:
- **genctl-cicd-onepipeline** - You have **read-only** access to this namespace.
- **vpc-sandbox-docker-local** - You have **read and write** access to this namespace.

## Logging into IBM Cloud Container Registry (ICR)
You can log in to ICR using the following commands:
```sh
ibmcloud login --sso #Login to IBM Cloud and select OnePipeLineCloud account
ibmcloud cr region-set us.icr.io #Set the container registry region to us.icr.io
ibmcloud cr login #Login to ICR
```

### To View the Namespaces:
1. Login to IBM Cloud:
   ```sh
   ibmcloud login --apikey $user_ibmcloud_apikey -r us-south
   ```
2. Get the list of namespaces:
   ```sh
   ibmcloud cr namespaces
   ```

## Viewing Docker Images
### List all images under a namespace:
```sh
ibmcloud cr images --restrict genctl-cicd-onepipeline
```
### List all images under a specific repository name:
```sh
ibmcloud cr images --restrict genctl-cicd-onepipeline/rias/compute-billing-lifecycle-mgmt
```

## Pushing Images to the Sandbox
1. Login to ICR:
   ```sh
   docker login -u iamapikey -p ${USER_IBMCLOUD_APIKEY} us.icr.io
   ```
2. Push an image:
   ```sh
   docker push us.icr.io/vpc-sandbox-docker-local/<your-image>
   ```
