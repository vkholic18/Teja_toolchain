# One Pipeline Adoption Guide 

This document describes the steps that each workspace owner has to
execute to adopt One Pipeline.

## Adding the One Pipeline functional user to your GitHub repo(s)

A new functional id has been created to support the One Pipeline adoption:
**OnePipeLineCI@ibm.com**

This user must be:
- a member of the organization in which your repository sits
- added as collaborator with Admin permissions on your GitHub repo(s).

This is needed because, analogously to what Concourse currently does, 
One Pipeline also uses GitHub checks, needs to create hooks...

## Configure Status Check on your GitHub repo(s)

After the first PR pipeline run, you will observe multiple checks created in your GitHub repo.

Similarly to what is currently expected to be done for [Concourse]( https://confluence.swg.usma.ibm.com:8445/display/DevOps/Repository+Preparation+for+CICD+Pipeline+creation)
you have to make these checks required:

On GitHub, navigate to the main page of the repository.
Under your repository name, click  Settings.
In the left menu, click Branches.
Next to "Branch protection rules", click Add rule.
Under "Branch name pattern", type the branch name or pattern you want to protect.
Under "Protect matching branches", select Require status checks to pass before merging.
Optionally, select Require branches to be up to date before merging. If selected, this ensures that the branch is tested with the latest code on the base branch.
Click Create.

Additionally, require squash merges for all PRs merging to protected branches but the master branch.
(see instructions [here](https://docs.github.com/en/github/administering-a-repository/configuring-commit-squashing-for-pull-requests)) 

## Adding GitHub repos

All needed GitHub repos are cloned in the ```code-setup``` stage.
By default the pipeline will be cloning your workspace repo. If you need additional repos to be cloned, 
this must be communicated to the CI team together with the information on where in the workspace you
expect to have it cloned.

## Customizable Steps  

Analogously to what is currently done in Concourse, the workspace team is reponsible for
the logic needed to run unit test, build and functional test.

Teams must convert existing yaml files to bash scripts.

For example, ```run-unit-tests.yaml``` should be converted to ```run-unit-tests.sh```

**Note:** You should set the executable permission to the converted shell scripts(run-unit-tests.sh, build.sh, run-functional-tests.sh..etc) with the command "chmod +x ```<shell file name>```"

**Attention:** until the migration to One Pipeline is completed, you need to keep both the yaml and the sh
version of the files to ensure your pipeline can still run on Concourse.

### PR to dev integration pipeline

In this pipeline, as part of the "code-unit-test" stage the files from your GitHub repo, 
```hack/ci``` folder, ```build.sh``` and ```run-unit-tests.sh``` will be executed

In addition, you can optionally run static scans in PR to dev-integration; to achieve this; add in the top level of
your ```pipeline.yaml``` file ( Under ```hack/ci``` ) the following entry:

```yaml
run_static_scan_in_pr_to_dev_int: true
```

For more information about static scan in PR to dev-integration pipeline see:

https://ibm-cloudplatform.slack.com/archives/C03981DA3HR/p1698670461121649

### CI on dev-integration pipeline

In this pipeline, as part of the "code-unit-test" stage the files from your GitHub repo, 
```hack/ci``` folder, ```build.sh``` and ```run-unit-tests.sh``` will be executed

Notice that build.sh is run in this stage ad not in the ```build-containerize``` one
because we need to ensure all needed artifacts are available for the 
```code-compliance-check``` stage to run.

### PR to master pipeline

In this pipeline, as part of the "code-unit-test" stage, your Blast Radius Tests (BRT) are run.

Due to a dependency of the test frameowrk on the Security Ops Vault, this pipeline must use TaaS workers.

For additional information about BRT and how to configure development environment and CI pipeline
to run BRT look [here](https://confluence.swg.usma.ibm.com:8445/pages/viewpage.action?spaceKey=CLD&title=Developer+Guide)


### CI on master pipeline

This pipeline is highly simplified compared to the Concourse one. It is just creating the tag on master, 
tagging appropriately the image(s)/artifact(s) that has(have) been built in the CI to dev-integration and add the appropriate label on
the Jira tickets included in the build.



## Security Scans

One pipeline includes by default multiple security scans.    
    
It is responsibility of the security rep of the workspace team to approve
any change to the scanning tool configuration and approval of false positive 
issues.
As a consequence, the configuration of the scanning tools must reside in the
workspace repo.


### Verifying Code Risk Analyzer runs correctly

One pipeline include several built-in scanning tools.
One of them is Code Risk Analyzer (CRA). It is responsible for discovering vulnerabilities in your 
dependencies, generates the Bill of Material (BOM) and verifies the compliance of your dockerfile(s).

To perform its scanning on the dockefile(s) it builds the container image stage by stage. In case your
dockerfile is expecting pre-built artifacts or special parameters to be passed to the build process, CRA
may not be able to complete successfully.
That implies your build process must be changed to allow CRA to correclty scan your dockerfile(s).
If you do not build all your artifacts directly in the dockerfile, the pipeline will have to add an
additional build stage before CRA runs and this will be impacting the performances of your pipeline.
We highly recommend to build all your artifacts directly in the dockerfile.

You can verify that CRA is able to scan your dockerfile at any time without waiting for your pipeline
to be moved to One Pipeline following the procedure below

### Run CRA on a local GitHub repo

**Prerequisites:**

- Create a [toolchain](https://cloud.ibm.com/docs/ContinuousDelivery?topic=ContinuousDelivery-toolchains_getting_started&interface=ui#creating_a_toolchain_from_an_app)
- Install [ibmcloud cli](https://cloud.ibm.com/docs/cli?topic=cli-getting-started)
- Install docker cli(Docker desktop)
- Install [ibmcloud cra plugin](https://cloud.ibm.com/docs/code-risk-analyzer-cli-plugin?topic=code-risk-analyzer-cli-plugin-cra-cli-plugin)
- Make sure tar is installed


Obtain the cocoa docker image from ```wcp-genctl-sandbox-docker-local.artifactory.swg-devops.com/genctl```, 
look for an imae named ```cocoa-op```

Run the container image mounting the directory where you extracted your workspace code and the docker socket
into it (to be able to run DIND)

Example: 

```($PWD/regional-storage is the path to the workspace on my local filesystem)

docker run -it -v $PWD/regional-storage:/regional-storage -v /var/run/docker.sock:/var/run/docker.sock --rm wcp-genctl-sandbox-docker-local.artifactory.swg-devops.com/genctl/cocoa-op:1.5
```

SSH into the container and execute the following steps to generate the BOM:

**Generate the BOM**

- Log into your IBM account via CLI (run ```ibmcloud login --sso```) and complete the 2FA login
- Export your toolchain id as an environment variable “export TOOLCHAIN_ID=XXXX” (the toolchain id can be found on the toolchain overview page)
- Run the command ```ibmcloud cra bom-generate --path <path-to-workspace> --report <bom-file-name>.json --region <tooldchain-region>``` ( ```path``` is the path to your workspace on the local file system and *report is the name of the output BOM file), for more flags and information refer to [here](https://cloud.ibm.com/docs/code-risk-analyzer-cli-plugin?topic=code-risk-analyzer-cli-plugin-cra-cli-plugin)

The command would generate a BOM on the path you specified in the ```--report``` option.

If you are using Dockerfiles, make sure to log in to your container registry from where the base images are to be pulled.

If your Dockerfile requires ARGS, set an individual ARG as an environment variable before you run the command. For example, if the Dockerfile is using an IAM_USER ARG, export an environment variable that is named IAM_USER: ```export IAM_USER='value'```. The CLI automatically passes these environment variables to the docker build command.

You can also specify the DOCKERBUILDFLAGS flag explicitly. To export DOCKERBUILDFLAGS with the ARGS Docker flag, type the following command:
```export DOCKERBUILDFLAGS=" --build-arg IAM_USER --build-arg API_KEY"```

**Run Vulnerability Scan**

The prerequisite to run the vulnerability scan is the BOM json file (see the previous step)

You must be logged in to your IBM account (run ```ibmcloud login --sso``) and complete the 2FA login

Run ```ibmcloud cra vulnerability-scan -b <bom-file>.json``` (```bom-file``` is the name of the bom file on the local filesystem)

The scan will show the CVE’s for the related version and packages

**Analyze Deployment**

You must be logged in to your IBM account (run ```ibmcloud login --sso```) and complete the 2FA login

Run ```ibmcloud cra deployment-analyze --path <path-to-workspace> --report <name-of-output-report>``` (```path-to-workspace``` is the path to the workspace on the filesystem and ```name-of-output-report``` is the name of the file the scan generates and outputs)


### Mend Scan    
    
Mend scan is turned on for repositories that use a programming language that is not supported by CRA (e.g. "C" ).
    
The enable Mend scan, the service team is required to open a "CISO Whitesource Service Request"
in Service Now (see an example [here](https://ibm.service-now.com/ciso_whitesource?id=ciso_mend_service_status&sys_id=5d58f147472ab990991b0a31516d4302) )
for Mend Unified Agent onboarding
    
Key information to provide in the Service Now request is the PSIRT ID.

Once the request would have been processed, the opener will obtain mend-org-token and mend-product token
    
Mend user key needs to be generated by user by clicking top left side in Service Now request, blue colour button, WS_USER_Key
    
All the three secrets would have to be populated in the Secret Manager instance owned by the CI team.
    
The owner of the secret is responsible for its periodic rotation as per CISO guidelines.    
    
### Static Scan
    
Static scan is run via Contrast SAST for all VPC workspaces.
        
The default scan configuration is used, so no additional work needed from the workspace teams.
    
    
    
### Dynamic Scan
    
This is new compared to what is currently done in Concourse. 
The [dynamic scan](https://cloud.ibm.com/docs/devsecops?topic=devsecops-zap-scans) works against
running code and will try to demonstrate your public APIs are vulnerable.
The built-in tool is [OWASP ZAP](https://cloud.ibm.com/docs/devsecops?topic=devsecops-cd-devsecops-ci-pipeline#devsecops-ci-pipeline-dynamic-codescan)
    
The development team is responsible to provide the following information n the pipeline.yaml file the under
hack/ci folder on the workspace repo:
- Swagger definition file in json format
- All API endpoints to be scanned
    
    
Here below there is an example of the configuration:

```
    
dynamic_scan:
 api_file_name: vpc.json // this is the name of teh file where the swagger definition is
 profiles: ['volume'] // this is the identifier of the APIs to be scanned
 endpoints: ['all'] // list of the endopints in case only a subset of the endpoints under the specified profile needs to be scanned
```
    
    

## Detect secrets

See: https://ibmcloudlab.slack.com/archives/C03981DA3HR/p1685458863511249
    
## Dealing with Security Vulnerabilities
        
### Vulnerabilities found by the PR pipelines
    
The PR to dev-integration fails if a vulnerability is found in the ```code-compliance-check``` stage.
It implies you cannot merge the code in dev-integration until the vulnerability is fixed.

Documentation on how to omit the vulnerability found by CRA is [here](https://cloud.ibm.com/docs/devsecops?topic=devsecops-cd-devsecops-cra-scans#devsecops-omit-vulnerabilities). 
    
You must set an expiration date when creating the entry in the .cveignore file.
    
See the section "Omitting Vulnerabilities" down below to get details on the process to follow when needing to omit a
vulnerability.


## Vulnerabilities found by CI on dev-integration pipeline

In the spirit of finding as many issues as early as possible, the CI pipeline on dev-integration tries to execute all
stages even if a vulnerability has been found. For each vulnerability found an issue will be open in the GitHub repository
that you are using as ```incident-repo```.
Labels are automatically added to indicate the tool that discovered the vulnerability, the severity, whether of not the fix is available...

If a vulnerability is found, the pipeline will be marked as failed, even though all stages are completed (i.e. LaunchDarkly is updated). This is to allow you to keep testing your code while addressing the security vulnerabilities and to allow
other developers to use your code while addressing the security vulnerabilities.

Once the CD pipeline will be moved to one pipeline, if you do not address the vulnerabilities, the Change Request will require 
manual approval. This will be impacting the speed with which your code progresses in staging and production.
    
## Vulnerabilities found by CI on master pipeline

In this case it is not affordable to move the code forward with known vulnerabilities. The pipeline will fail
and the code will not be moved to the next environment even if the tests are passing.
    
You must fix/disposition all the identified vulnerabilities to move your code forward.
  
## Omitting Vulnerabilities
    
One Pipeline adds a lot of focus on findinding vulnerabilities as early as possible in the development process.
    
When a vulnerability is found, you have three possibilities to disposition it:
- A fix is available for the vulnerability: you must apply the fix. 
- A fix is NOT available: configure the scanning tool to omit the vulnerability. The change must be reviewed and approved by your security focal. Use an expiration date that is compatible with the [IBM Cloud security policy](https://pages.github.ibm.com/ibmcloud/Security/policy/RA-Policy.html). You need to open a PCE of type Extension 
to track the vulnerability if you are not able to fix it within the timeframe specified in the policy.
- It is a false positive, not a real vulnerability: configure the scanning tool to omit the vulnerability. The change must be reviewed and approved by your security focal. [Here](https://pages.github.ibm.com/ibmcloud/Security/guidance/vuln-management-false-positives.html) you see the cases in which you can declare a vulnerability a false positive.
    
Issues in GitHub are automatically opened by the CI pipelines. 
    
The security focal must approve the omission of a vulnerability. 
This can be achieved tagging the issue as "exempt" and adding the appropriate explanation on why it is omitted.
If One Pipeline detects that you are omitting the vulnerability relying on a "ignore" file, it will add automatically the tag
"has-exempt" to the issue.
    
Issues that are tagged as "exempt" or "has-exempt" must be at least yearly reviewed and revalidated by the security focal.
The security focal must at least yearly revalidate the "ignore" files.
    
In some cases, One Pipeline is able to detect if a fix is available. In this case, the issue will be tagged with "fix-available" and you will be required to implement the fix and remove the omission.
    
It is your responsibility to appropriately comment on the GitHub issue when the vulnerability is dispositioned
and it is your responsibility to close the issue when the vulnerability is fixed.
    
### Omitting Vulnerabilities found by Vulnerability Advisor

The definition of ignore policies for Vulnerability Advisor is done in the Container Registry settings. You will not be entitled
to access it, only the CI team will have permission to define policies.
    
If you need a CVE to be added to a vulnerability advisor policy, your security focal needs to open an [issue](https://github.ibm.com/genctl-cicd/genctl-ci/issues) to the CI team. He needs to specify the impacted image(s) and the CVE ID.
    
The CI team will then create the needed policy. 
    
When the policy would be no longer needed, your security focal needs to open an [issue](https://github.ibm.com/genctl-cicd/genctl-ci/issues) to the CI team specifying that the policy for the specified CVE ID and image(s) is no longer needed.
    
Lack of diligence in signalling policies that have to be removed will force the CI team to remove them all once a quarter.
    
###References
Documentation on how to omit the vulnerability found at the following links:
- [CRA](https://cloud.ibm.com/docs/devsecops?topic=devsecops-devsecops-omit-vulnerabilities).
- [Detect Secret](https://w3.ibm.com/w3publisher/detect-secrets)
- [Contrast SAST](https://docs.contrastsecurity.com/en/exclude-files-and-folders.html)
- [OWASP ZAP](https://www.zaproxy.org/faq/how-do-i-handle-a-false-positive/)
- [Vulnerability Advisor](https://cloud.ibm.com/docs/Registry?topic=Registry-va_index&interface=ui#va_managing_policy)
    

CISO guidance on:
- [security vulnerability](https://pages.github.ibm.com/ibmcloud/Security/guidance/Vuln-Management.html)
- [false positives](https://pages.github.ibm.com/ibmcloud/Security/guidance/vuln-management-false-positives.html)
   

## Concourse Stages vs One Pipeline Stages
 
### PR to dev-integration

| Stage in Concourse  | Task in Concourse    | Stage In One Pipeline | Comments |
| ------------------- | ---------------------|-----------------------|----------|
|                     |                      | code-setup            | GitHub repo cloning is centralize in One Pipeline, while it is done in multiple places and multiple times in concourse |
| ALL_SCANS     | verify-repository-configuration |  | Rely on what is built-in in One Pipeline* |
| ALL_SCANS     | verify-protected-branches-configuration |  Rely on what is built-in in One Pipeline* | |
| ALL_SCANS     | check-pr-title-and-commits | code-unit-tests | |
| ALL_SCANS     | SCAN_GO_VETTING | code-unit-tests | |
| ALL_SCANS     | SCAN_GENLOG | | Removed in one pipeline, it always return true, nobody checks the report, if anything similar needed in the future it will be run on its own pipeline |
| | | code-static-scan | The static scan is done via Contrast SAST in the CI pipeline | 
| ALL_SCANS     | verify-workspace-dependencies-file | code-unit-tests | |
| ALL_SCANS     | validate_version_file | code-unit-tests | |
| ALL_SCANS     | VALIDATE_API_VERSION | code-unit-tests | | 
| ALL_SCANS     | VALIDATE_REGIONAL_VERSION | code-unit-tests | | 
| ALL_SCANS     | VALIDATE_CLIENT_API_VERSION | code-unit-tests | | 
| ALL_SCANS     | CHECK_SECRETS |  | Not done, no deployment is happening in this pipeline, this check is not needed | 
| ALL_SCANS     | CHECK_SECRET_LABEL | code-unit-tests | |
| ALL_SCANS     | anti-patterns-performance-check | | Removed in one pipeline, if anything similar needed in the future it will be run on its own pipeline | 
| ALL_SCANS     | VALIDATE_RAZEE_YAML_FILES  | code-unit-tests | |
| ALL_SCANS     | VALIDATE_RAZEE_FILES | code-unit-tests | |
| ALL_SCANS     | check-duplicate-keys-in-mustache-templates | code-unit-tests | |
| ALL_SCANS     | VALIDATE_RAZEE_REMOTE_RESOURCE | code-unit-tests | |
| ALL_SCANS     | VALIDATE_REQUIRED_DEPLOYMENT_LABELS | code-unit-tests | |
| BUILD_AND_UNITTEST  | UNIT_TEST  | code-unit-tests | |
| BUILD_AND_UNITTEST  | code-coverage  | code-unit-tests  | |
| BUILD_AND_UNITTEST  | export-pr-git-env  |  | export the git information of pull requests resourse. n/a in OnePipeline|
| BUILD_AND_UNITTEST  | inject-build-environment |  | custom image injection is not used in 1PL |
| BUILD_AND_UNITTEST  | build-and-upload | code-unit-tests | |
| release-to-COS     | check-ready-for-cos-upload-label | | code-unit-test |
| release-to-COS     | upload-razee-configs-to-cos |  | code-unit-test |
| VULNERABILITY_SCAN | vulnerability-scan | code-compliance-check | |
    
* Repository administrator should un-mark this check as required.
    
### CI on dev-integration
    
| Stage in Concourse  | Task in Concourse    | Stage in One Pipeline | Comments |
| ------------------- | ---------------------|-----------------------|----------|
|                     |                      | code-setup            | GitHub repo cloning is centralize in One Pipeline, while it is done in multiple places and multiple times in concourse |
| auto_semver         | create-git-tag        | code-unit-test | |
| build     | export-pipeline-data | | export the git information of pull requests resourse. n/a in OnePipeline |
| build     | inject-build-environment |  |custom image injection is not used in 1PL |
| build     | build-and-upload | code-unit-test | Is done in this stage to allow code-compliance-check to successfully build |
| build     | ICCR-Scan | build-scan-artifact | build-scan-artifact |
| | | code-peer-review | Opted out for now, maybe turned on in the future, stage not existing in Concourse |
| | | code-static-scan  | It was not done in Concourse, it runs Contrast SAST scan |
| | | build-containerize | Empty stage, the build is done as part as code-unit-test stage | 
| | | build-sign-artifacts | Image signing with CISO signing service |
| | | deploy-dev |  |
| | | code-dynamic-scan | Runs OWASP ZAP on the deployed code. Nothing similar is done in Concourse |
| | | deploy-acceptance-tests | Currently empty |
| release_to_COS | upload-razee-configs-to-cos | deploy-release |  |
| release_to_LaunchDarkly | update-feature-flag | deploy-release |  |
| update_environment_file | update-dev-regions-environment | deploy-release | |
    
### PR to master (work in progress )
    
| Stage in Concourse  | Task in Concourse     |Stage in One Pipeline | Comments |
| ------------------- | --------------------- |----------------------|----------|
|                     |                      | code-setup            | GitHub repo cloning is centralize in One Pipeline, while it is done in multiple places and multiple times in concourse |
| ALL_SCANS           | check-pr-title         | | |
| ALL_SCANS           | SCAN_PR_FROM_DEV_INTEG | code-unit-test | |
| ALL_SCANS           | VALIDATE_PIPELINE_YAML | code-unit-test | |
| RUN_WORKSPACE_TESTS | brt-lock-environments | code-unit-test | |
| RUN_WORKSPACE_TESTS | scale-up-ffsld-controller | code-unit-tests | |
| RUN_WORKSPACE_TESTS | roll-environment-to-default-rule | code-unit-tests | |
| RUN_WORKSPACE_TESTS | scale-down-ffsld-controller | code-unit-tests | |
| RUN_WORKSPACE_TESTS | validate-razee-cluster | code-unit-tests | |
| RUN_WORKSPACE_TESTS | validate-feature-flags | code-unit-tests | |
| RUN_WORKSPACE_TESTS | run-tests | code-unit-tests | |
| RUN_WORKSPACE_TESTS | scale-up-ffsld-controller | code-unit-tests | |
| RUN_WORKSPACE_TESTS | rollback-environment-to-dev-integration | code-unit-tests | |
| DRY_RUN_DEPLOYMENT  | inject-dry-run-environment | n/a for razee, deprecated  | |
| DRY_RUN_DEPLOYMENT  | dry-run-deployment | n/a for razee, deprecated | |
| MERGE | verify-repository-configuration | | Rely on what is built-in in One Pipeline* |
| MERGE | verify-protected-branches-configuration | |  Rely on what is built-in in One Pipeline* |
| MERGE | merge-pr | code-compliance-check | |

* Repository administrator should un-mark this check as required.
    
### CI on master 

| Stage in Concourse  | Task in Concourse     |Stage in One Pipeline | Comments |
| ------------------- | --------------------- |----------------------|----------|   
|                     |                      | code-setup            | GitHub repo cloning is centralize in One Pipeline, while it is done in multiple places and multiple times in concourse |
| auto_semver | brt-history-collector | deprecated | |
| auto_semver | create-git-tag | deploy-dev | |
| auto_semver | update-change-log | deploy-dev | |
| auto_semver | update-release-version | deploy-dev| |
| auto_semver | update-brt-stats | deprecated | |
| BUILD | export-pipeline-data | deploy-dev |  |
| BUILD | inject-build-environment | | custom image injection is not used in 1PL |
| BUILD | build-and-upload | | Not done in One Pipeline since it uses only the artifacts built on CI to dev-integration|
| BUILD | ICCR-upload | deploy-dev | |
| | | build-containerize | Empty stage, the build is done as part as code-unit-test stage | 
| | | deploy-dev | In this stage we collect compliance evidences and populate the inventory repo |
| | | deploy-acceptance-tests | Currently empty |
| VULNERABILITY_CHECK | ICCR-check | | The scan has been moved to CI to dev-integration  |
| RELEASE | check-if-genctl-component | | |
| RELEASE | copy-to-marina-prod | | Marina DB is not used in One Pipeline migration |
| RELEASE | upload-razee-config-to-cos | deploy-dev | |
| RELEASE | update-feature-flag | deploy-dev | |

    
## Getting Access To the Toolchains
    
Access is managed via [AccessHub](https://ibm-support.saviyntcloud.com/ECMv6/request/applicationRequest).
    
Select `Request New Access`. Specify `OnePipeLine` in the Search bar.  
Click on `Request New Account` (or `Manage Access` if you already have an account and you want to change your permissions).
- Select `One_Pipeline_Services_Operator` if you are a workspace developer.
- Select `ImageScan` if you are a memeber of the security team.    

    
All other roles are reserved for CI team members.

## Getting Access to Contrast Dashboard
    
Access is managed via Service-Now and AccessHub.

1) Service-now (Can be avoided if already a part of is.vpc group):
- Raise a request in https://ibm.service-now.com/ciso_contrast to create a new request
- Select 'Product' as Application Type and 'is.vpc' as PSIRT Product Name
- Wait for request to be fully approved and then raise AccessHub request

2) AccessHub:
- Raise a request in https://ibm-support.saviyntcloud.com/ECMv6/request/applicationRequest?search=Q29udHJhc3QgU2VjdXJpdHk= 
- Request for role 'is.vpc_VIEW' under SCS - Contrast Security

All other roles are reserved for CI team members.

After both requests are approved, you can access [Contrast Dashboard](https://app.contrastsecurity.com/Contrast/static/ng/index.html#/142bb017-de7e-4af7-b5b9-f0782aa6d369/dashboard) using W3id credentials.


## Slack Build Notifications

All of the OnePipeline build notifications can be located in channel [#vpc_alerts_onepl](https://ibmcloudlab.slack.com/archives/C05J0458WU9) 

Teams have the ability to have their notifications sent to a channel of their choosing. To streamline the process, please open a GH issue [here](https://github.ibm.com/genctl-cicd/genctl-ci/issues/new?assignees=eric-w-gustafson&labels=OnePipeline-Notifications&template=onepipeline-build-notifications.md&title=OnePL+Slack+Build+Notifications%3A+%3Ctoolchain-name%3E) with the channel name you wish to receive them in.

Note: the notifications for your workspace/toolchain will continue in [#vpc_alerts_onepl](https://ibmcloudlab.slack.com/archives/C05J0458WU9) but will also be sent to the channel of your choosing.
    
## Travis Workspace CRA setup
Travis workspaces build artifacts(docker images etc in travis) in this case the build artifacts (binaries) are not present during the CRA step, for this we introduced hack/ci/cra-setup.sh.
cra-setup.sh runs before CRA step executes, this takes care of few cases
1. Dockerfiles which require docker arguments
Example: to add docker arguments to the CRA dockerfile build 
`export DOCKERBUILDFLAGS="--build-arg SCRATCH_BASE_IMG --build-arg XXXX"` and export the relevant arguments, i.e export `SCRATCH_BASE_IMG`
2. In order to avoid building the binaries in the CRA stage using the cra-setup.sh, we advise creating a tar file that contains the workspace build directory and upload that into a sandbox location we provide
In build.sh we offer two new variables: `CC_ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH`, `CC_ARTIFACTORY_BASE_URL ` which adds the generic sandbox repo to upload the tar file to(to include them in the travis build add them to `TRAVIS_CC_ARGS` env variable)
In the actual travis build, usually referenced as travis.sh we create a tar file and upload to the sandbox
Example code for upload:
```
function upload_build_artifacts() {
    BUILD_DIR="build"
    BUILD_ARTIFACTS_TAR_FILE="asw-${CC_GIT_SHA}-${ENV_DOCKER_ARCH}-artifacts.tar.gz"
    echo "archive artifacts"
    tar --exclude="docker" -zvcf "${BUILD_ARTIFACTS_TAR_FILE}" -C ${BUILD_DIR} .
    echo "build artifact $(ls -ltr "${BUILD_ARTIFACTS_TAR_FILE}" 2> /dev/null | awk '{print $NF}')"

    ARTIFACTORY_WORKSPACE_PATH="genctl/${CC_REPO_NAME}/artifacts/${BUILD_ARTIFACTS_TAR_FILE}"
    ARTIFACTORY_UPLOAD_PATH="${CC_ARTIFACTORY_BASE_URL}/${CC_ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${ARTIFACTORY_WORKSPACE_PATH}"
    put_to_artifactory ${ARTIFACTORY_UPLOAD_PATH} ${BUILD_ARTIFACTS_TAR_FILE}
    echo "exit: $? uploaded artifacts to ${ARTIFACTORY_UPLOAD_PATH}"
}
```
Example code for downloading artifacts during cra-setup:
```
function download_build_artifacts() {
    ARCH=$1
    
    BUILD_DIR="build"
    REPO_NAME="acadia-storage-workspace"
    BUILD_ARTIFACTS_PATH="${BUILD_DIR}/${ARCH}"
    GIT_SHA=$(git rev-parse --verify HEAD)
    BUILD_ARTIFACTS_TAR_FILE="asw-${GIT_SHA}-${ARCH}-artifacts.tar.gz"
    mkdir -p ${BUILD_ARTIFACTS_PATH}
    
    ARTIFACTORY_WORKSPACE_PATH="genctl/${REPO_NAME}/artifacts/${BUILD_ARTIFACTS_TAR_FILE}"
    ARTIFACTORY_DOWNLOAD_PATH="${CC_ARTIFACTORY_BASE_URL}/${CC_ARTIFACTORY_GENERIC_SANDBOX_REPO_PATH}/${ARTIFACTORY_WORKSPACE_PATH}"
    download_file_from_artifactory ${ARTIF_APIKEY} ${ARTIFACTORY_DOWNLOAD_PATH} "${BUILD_DIR}/${BUILD_ARTIFACTS_TAR_FILE}"
    echo "exit: $? downloaded artifacts to ${BUILD_DIR}/${BUILD_ARTIFACTS_TAR_FILE}"

    echo "unarchive artifacts"
    tar -zvxf "${BUILD_DIR}/${BUILD_ARTIFACTS_TAR_FILE}" -C "${BUILD_ARTIFACTS_PATH}"
}
```
In this specific case we untar the dockerfiles with the binaries to the build directory, therefore we need to exclude the default dockerfile scanning path, we can achieve this by using the .cra/.fileignore file and add `/**/hack/docker/*`

references:

1. https://github.ibm.com/genctl/acadia-storage-workspace/blob/onepipeline-test/hack/ci/build.sh

2. https://github.ibm.com/genctl/acadia-storage-workspace/blob/onepipeline-test/hack/ci/travis.sh

3. https://github.ibm.com/genctl/acadia-storage-workspace/blob/onepipeline-test/hack/ci/cra-setup.sh

## References 

1.  <https://cloud.ibm.com/docs/devsecops?topic=devsecops-cd-devsecops-ci-pipeline#devsecops-ci-pipeline-dynamic-codescan>

2.  <https://us-south.git.cloud.ibm.com/open-toolchain/hello-compliance-app>
    
