Inventory candidate files flow
===

Background
---

The inventory candidate files flow is the logic implemented in order to be able to create inventory as required per OnePipeline and still use the dev-integration/master flow defined by MASCD

## Flow

The flow has 7 steps

* Steps 1 to 4 happen in the merge to dev-integration pipeline (Note that step 1 & 2 do not actually involve the files, but are pre-requisites for the next steps, therefore we consider them part of the flow)
* Step 5 happens in the PR to master pipeline
* Steps 6 and 7 happen in the merge to master pipeline

## Step 1 (Pre-requisite for actual file flow to start) - Save artifacts 

This step happens on the merge to dev-integration pipeline, in the code-unit-tests stage. specifically, right after we run the build.

In this step we iterate over the list of images the workspace builds (Defined in build-meta.yaml), pull each of this images from artifactory, and for each image, perform the one-pipeline save_artifact command

Note that while theoretically we could, instead of pulling images, rely on the images on the local container of the execution itself (Since we just built them), this is not accurate, for example, images that are built in Travis are not available in the One-Pipeline execution, therefore we need to explicitly pull them

This step is a pre-requisite for the next step (Signing), because signing works on the one-pipeline artifacts

## Step 2 (Pre-requisite for actual file flow to start) - Signing

This step happens on the merge to dev-integration pipeline, in the build-sign-artifact stage.

This step starts on the main pipeline and triggers a sub-pipeline, the reason being, the signing process requires to run on TAAS worker, and our main pipeline runs on private worker

In this step, we call one-pipeline script that performs signing for each of the images that were saved as artifacts in the previous step

## Step 3 - File creation and upload

This step happens on the merge to dev-integration pipeline, in the build-sign-artifact stage

Specifically this happens on the same sub-pipeline than step 2, right after it (At the end of this section is a more detailed explanation of why this happens on the sub-pipeline)

In this step, we create 2 files (1 JSON file and 1 ZIP file)

### JSON file

The JSON file has the information that is required to perform the cocoa inventory add commands, specifically it has 3 sections

* images

This is an array of objects that have information of each image that the workspace builds and therefore that we need to perform cocoa inventory add with type="image"

Note that if an image is built for multiple architectures, then we will have an object for each architecture

* deployment_metadata

This is an object with information required to perform the cocoa inventory add with type="deployment"

* commons

This is an object with information that is used in both the cocoa inventory add commands (images and deployment)

Note that since this information is the same for all images, it appears only once in the JSON

### ZIP file

This is a ZIP file containing the deployment files

<ins>NOTE</ins>: The reason why this step is on the sub-pipeline is because:

A. As explained previously, the signing process runs on a sub-pipeline (Because it requires TAAS worker)

B. Since the signing runs on a sub-pipeline, the signatures on the artifacts are available only on the context of the sub-pipeline and are not visible to the parent pipeline

Therefore, we decide to create and upload the files on the subpipeline 

## Step 4 - Move from pre-release to vetted

This step happens at the end of the merge to dev-integration pipeline, in the deploy-release stage, specifically after succesfully executing Upload to COS & Update LaunchDarkly

In this step, we use Artifactory API to move the JSON and ZIP files created in step 3 to a different directory

The purpose of this step is an extra protection layer, in order to ensure we won't be using for the purpose of inventory commands a version that might have not completed the pipeline to the end

To be more detailed: Step 3 happens right after the signing; at that point we create and upload the files, however after the signing there are more stages (For example: code-dynamic-scan, build-scan-artifact, etc) if any of those stages fail, we don't want to use those files as inventory (This will be validated in Step 3 )

## Step 5 - Check vetted files

This step happens at the beginning of the PR to master pipeline, in the code-unit-tests stage, specifically, before proceeding to the whole BRT block of logic (Before even acquiring the BRT lock)

The goal of this step is to act as a "gateway" in order to not move forward with versions that didn't complete succesfully the merge to dev-integration pipeline

In this step, we check that for the SHA of the PR to master (Which is a dev-integration SHA), the relevant files exist on the vetted directory, if this is true, it means that the version succesfully passed the merge to dev-integration pipeline

Note that in the situation that we have an open PR to master and a new commit is added to dev-integration, both the merge to dev-integration and the PR to master pipelines are triggered and this might lead to some race conditions, therefore this check is executed with a retry logic, giving enough time to the merge to dev-integration pipeline to finish, and then continue with the PR to master pipeline

## Step 6 - Move ZIP file to final destination

This step happens in the merge to master pipeline, at the deploy-dev stage, specifically after succesfully executing Upload to COS & Update LaunchDarkly

In this step we move the ZIP file from the vetted directory to its final destination

## Step 7 - Download JSON file and add inventory

This step happens in the merge to master pipeline, at the deploy-dev stage, specifically after succesfully moving the ZIP file from the vetted directory to its final destination

In this step, we download the JSON file that was created in step 3 and vetted in step 4, and we process its information, generating the relevant cocoa inventory add commands and executing them

This is the actual step where the inventory gets created/updated