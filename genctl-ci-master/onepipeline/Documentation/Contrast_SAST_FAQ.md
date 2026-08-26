# Contrast SAST FAQs

### 1) Why are we migrating to Contrast SAST from GoSec and SonarQube for Static code analysis for VPC workspaces?
Contrast is the tool chosen (and mandated) by IBM CIO for static scan. You may have heard it also mentioned in the annual mandatory security education. The tool is of course approved as well by IBM Cloud CISO and it is integrated with one pipeline.

### 2) Will my workspace be impacted?
If you are currently using GoSec or SonarQube for static code analysis, then it will be replaced by Contrast SAST going forwards.

* SDN: The efforts are already in place to enable the scan in both CI and PR pipelines.
* Razee: You can find the schedule [here](https://ibm.box.com/s/72y9xz3qaqckd8rhqeuc0dgo6ay65y4w) for your respective workspace.
* Other Components: All new onboardings will be taken care after we remove the dependency on GoSec and SonarQube. All details will be provided in [#vpc-ci-onepipeline](https://ibm.enterprise.slack.com/archives/C03981DA3HR) slack channel.

### 3) Is line level exclusion supported in Contrast SAST?
No, currently the tool does not support line level exclusion.
The vendor is evaluating this requirement, and https://zenhub.ibm.com/workspaces/appsec-external-65f92636eb7f50000fcca50b/issues/supply-chain-security/appsec-external-docs/34, https://zenhub.ibm.com/workspaces/appsec-external-65f92636eb7f50000fcca50b/issues/supply-chain-security/appsec-external-docs/34 are the corresponding issues.

### 4) Where can I view the results of the execution?
You can view the logs in OnePipeline logs and also check all vulnerabilities in [Contrast Dashboard](https://app.contrastsecurity.com/Contrast/static/ng/index.html#/142bb017-de7e-4af7-b5b9-f0782aa6d369/dashboard).

### 5) How can I get access to the Contrast Dashboard?
Request for [Contrast SAST dashboard](https://app.contrastsecurity.com/Contrast/static/ng/index.html) using [AccessHub](https://ibm-support.saviyntcloud.com/ECMv6/request/applicationRequest?search=Q29udHJhc3QgU2VjdXJpdHk=) Request for “Product” as a category and role ‘is.vpc_VIEW’ under SCS - Contrast After the request is approved, you can view the dashboard [here](https://app.contrastsecurity.com/Contrast/static/ng/index.html#/142bb017-de7e-4af7-b5b9-f0782aa6d369/dashboard).

### 6) How can I check the report of my workspace in the dashboard?
You can click on Scans tab in the [dashboard](https://app.contrastsecurity.com/Contrast/static/ng/index.html#/142bb017-de7e-4af7-b5b9-f0782aa6d369/dashboard) and search for a project with the name of your github repository. Below is the naming convention we follow: is.vpc-${REPO_NAME}-${BRANCH_EXECUTING_SCAN}

### 7) Will Contrast create create GitHub issues based on the result of the execution?
Yes, issues will be created through CI pipeline only and not PR pipeline. CI pipeline will create as many GitHub issues as the number of issues detected in the scan.

### 8) Why is the scan running in my PR pipeline?
By design, static code analysis is only executed in the CI pipelines, (ci-dev-integration in case of Razee), but if its running in your PR pipelines, then you have opted for it by setting run_static_scan_in_pr_to_dev_int flag to true in hack/ci/pipeline.yaml

### 9) Will my PR pipeline be blocked if issues are detected?
Yes, PR pipelines will be blocked from merging if the issues are detected in case you have opted for running the scan in PR pipelines. PRs will not be blocked if you are executing the scan only in the CI pipeline.

### 10) How can I exempt an issue created already in GitHub?/How can I mark an issue as false positive?
If an issue is opened for security reasons by OnePipeLine, in order to mark it as a false positive, you need to add a comment in the issue explaining why it is a false positive and then add the exempt label. The issue would have to remain open and would have to be periodically reassessed.

### 11) How can I exclude certain files/folders from the scan?
You can create a file named .contrast-scan.json in the root of your GitHub repository below content. { "excludes": [ "**/*test.go", "**/*_test_.*" ] } You can find more info [here](https://docs.contrastsecurity.com/en/exclude-files-and-folders.html).
The list of files that are excluded must also be periodically reevaluated.

### 12) Can I have a local setup for contrast?
No. Currently it is not possible to run the scan on your local machine, we are working with the Contrast team to look for alternate solutions. We'll keep you posted on the channel about it.

### 13) Why do I get <ins> main] c.c.s.client.ClientConfiguration         : Proxy disabled </ins> error in the execution of the Contrast SAST?
This can happen if you have lot of pipelines running the scan for the same project name in Contrast. If it happens, you can rerun the pipeline run.
We are closely working with the team to get this issue resolved. Please find the issue created below:
https://github.ibm.com/one-pipeline/adoption-issues/issues/2584 
