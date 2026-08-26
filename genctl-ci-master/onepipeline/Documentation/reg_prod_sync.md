# Reg Prod sync

Currently (14/12/2023) there is a process for syncing images that we push to artifactory to reg-prod

## How does it work ?

The basic mechanism is using a repo (https://github.ibm.com/genctl-cicd/one-pipeline-marina-reg-prod-sync) as a "queue" for a Concourse job (https://concourse-tor.genctlci.com/teams/cicd/pipelines/onepl-marina-reg-prod-sync) that copy the images

Each time there is a merge pipeline in OnePipeline, we create a JSON file that has the information required by Concourse to pull the image and push it to reg-prod.

The name of the JSON file created is in the format of ORG_NAME_REPO_NAME_MERGE_SHA.json

For example:

https://github.ibm.com/genctl-cicd/one-pipeline-marina-reg-prod-sync/blob/master/genctl_telemetry-workspace_974b67dbeb281e375530ee6798b32fbaf273f87e.json

## What to do if an image is missing in reg-prod ?

If an image is missing is probable that this process went wrong at some point, however we can "re-trigger" it manually by doing the following steps:

1. First identify to which repo the image belongs
2. Find the version and also find the toolchain run that generated that version and therefore the SHA
3. Verify that for that run, the creation of the .json file for the sync was succesfull; if yes then find .json file using the ORG_NAME_REPO_NAME_SHA.json
4. On the .json file, make a commit just adding some space to the end of the file; this will re-trigger in Concourse the sync process
