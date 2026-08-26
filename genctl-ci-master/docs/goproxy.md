# How to pull the go packages using GOPROXY
As part of the Service Framework requirement ARCH014 we need to make sure that all the go packages are pulled from the GOPROXY configured in the Artifactory.
More details [here](https://github.ibm.com/cloudlab/ServiceFramework/issues/319).

## Configure GOPROXY in Artifactory
GOPROXY needs 3 Artifactory repositories set up:
- Local
- Remote
- Virtual = Local + Remote

The workspace will be referencing the 'Virtual' repository which combines the trusted URLs in the local and the remote repositories.
These repositories have already been configured and are managed by the CI team under `legacy-wcp-genctl-artifactory` resource.
Detailed steps are [here](https://github.ibm.com/BSS/Deliverables/issues/1643#issuecomment-28474332).

## Prerequisites
The workspace must use the :exclamation: **Go Modules** :exclamation: to switch over to GOPROXY.

## Configure GOPROXY in developer workspace
1. Define the following variables in the Makefile or the script which builds the components.
    ```
    export GOPROXY="https://${CC_ARTIFACTORY_READER}:${CC_ARTIFACTORY_READER_APIKEY}@na.artifactory.swg-devops.com/artifactory/api/go/wcp-genctl-go-virtual"
    export GOPRIVATE=github.ibm.com
      # CC_ARTIFACTORY_READER = Artifactory user with read-only access to GOPROXY
      # CC_ARTIFACTORY_READER_APIKEY = Artifactory API key for the user
    ```

2. Do **NOT** set the following variables, they will need to be removed.
    ```
    export GOPROXY=direct
    export GOSUMDB=off
    ```

3. CI pipelines pull the `Artifactory User` and the `Artifactory API Key` from the vault and pass them to the workspace when building. For a local build, the developers can use their personal Artifactory credentials. GOPROXY needs a read-only access.

## Example
CI changes \
https://github.ibm.com/genctl-cicd/genctl-ci/pull/1698 \
https://github.ibm.com/genctl-cicd/genctl-ci/pull/1719

Developer workspace changes \
https://github.ibm.com/genctl/regional-vpe-workspace/pull/91
