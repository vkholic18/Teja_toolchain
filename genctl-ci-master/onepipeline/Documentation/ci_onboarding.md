# One Pipeline onboarding guide for CI

This document is for the new team members joining the OnePipeLine CI team.

## Get your access

You will need access to
- [genctl-cicd](https://github.ibm.com/genctl-cicd) org - To be able to access the source code.
- IBM cloud OnePipeline account - Follow [these](https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/onepipeline/Documentation/OnePLMigrationGuide.md#getting-access-to-the-toolchains) instructions to request the access and select 'One_Pipeline_Developers' role.
- [OnePipeLine Box folder](https://ibm.ent.box.com/folder/192283272657) - Request Rohit Baweja for access.
- Slack channels
  - #vpc-ci-onepipeline (Main public channel)
  - #onepipeline_ci_onboard (For coordinating with the workspaces being onboarded)
  - #vpc_ci_onepl_int (Private CI channel for internal team discussions)
  - #devops-compliance (For issues with the toolchains)


## Useful docs

These useful documents will help you get started
- [OnePipeline Docs](https://github.ibm.com/one-pipeline/docs)
- [Terraform](https://cloud.ibm.com/docs/ibm-cloud-provider-for-terraform?topic=ibm-cloud-provider-for-terraform-setup_cli)
- [DevSecOps Toolchains](https://test.cloud.ibm.com/docs/devsecops)


## Important Repositories and other information

- OnePipeLine production
  - [CI Toolchains](https://cloud.ibm.com/devops/toolchains?env_id=ibm:yp:eu-gb) - Production uses `One_Pipeline_Services` resource group in `London`.

- Source code
  - [devops-toolchains](https://github.ibm.com/genctl-cicd/devops-toolchains) contains the definitions of all production and test toolchains, along with the automation to deploy those toolchains.
  - [genctl-ci](https://github.ibm.com/genctl-cicd/genctl-ci) contains the scripts which are called by the toolchains.

- OnePipeline base image
  - [golang-cocoa image](https://github.ibm.com/genctl-cicd/golang-ci) is used as a base image in OnePipeLine (The regular goland/dind images in Concourse).

- Ticket system
  - [Github issues](https://github.ibm.com/genctl-cicd/genctl-ci/issues) are used to log tickets (JIRA in Concourse).


## Process to onboard new workspaces

When new workspaces are onboarded, this is typically the process to follow. It may slightly differ based on individual preference.
- Start the conversation in #onepipeline_ci_onboard with the workspace team.
- Request them to create a JIRA issue using the [onboarding template](https://github.ibm.com/genctl-cicd/genctl-ci/issues/new?assignees=&labels=New+Onboard+Request&template=onepipeline-onboarding.md&title=Onboard+%3Cworkspace-name%3E).
- Set up the test toolchains, coordinate with the workspace developer and test.
- Finally move the test toolchain to use the production configs and merge.
- Encourage developers to use #onepipeline_ci_onboard than direct messages.


## Limitations

- There is no test environment as of May-11-2023. Use production server to test.
- Use `One_Pipeline_Services` resource group to set up the toolchains, including the test toolchains, if you are working with a developer.
  The developers do not have access to the `One_Pipeline_Dev` resource group and will not be able to view the logs to debug.
  But if your pipeline does not need to be accessed by anyone outside CI, you can use `One_Pipeline_Dev` resource group for testing.
- We cannot use the workspace fork for testing. This is because the Secret Manager has the GHE token for the main workspace and not our forks. There is no capability at the moment to override it with your fork's token.


## Known issues

All the known issues that have been encountered during workspace migration are jotted down in [this](https://ibm.ent.box.com/file/1194149415368) box spreadsheet.
Make sure to read them while testing the pipelines and also update any new issues.


## How to set up a toolchain

### Using CI terraform automation

These instructions are from the perspective of adding new toolchains for the workspaces.
If you are setting up toolchain for anything else, some of these instructions may not apply.

- [This](https://github.ibm.com/genctl-cicd/devops-toolchains/blob/main/toolchains.tf) is the main file where all the toolchains are defined. Add your test toolchain to the file.
- Use your fork for `genctl-ci` and create a branch name `zenhub-<zenhubticketnumber>`. E.g. `zenhub-3737` for [issue 3737](https://github.ibm.com/genctl-cicd/genctl-ci/issues/3737)
- Make necessary changes on `genctl-ci` fork to test.
  This would typically include commenting out new tag creation, push/change to LD, debug statements, comment auto-merge features etc. Check out [this](https://github.ibm.com/genctl-cicd/genctl-ci/compare/master...Preeti-Verma:zenhub-3737) example.
- Test `pr-pipeline-dev-integration` and `ci-pipeline-dev-integration` first with the `onepipeline-test` branch on the workspace. Keep the master pipelines disabled.
- Get the PR reviewed and merged.
- Once the dev-integration pipelines are ready, remove them from Concourse and change to branch to use `dev-integration` in 1PL.
- Enable only the `pr-pipeline-master` and test. Ensure that the auto-merge features are commented out in `genctl-ci` branch.
- When `pr-pipeline-master` looks good, enable the `ci-pipeline-master`. Get rid of any other test parameters as well.
- Remove the pipelines from Concourse.
- Get the final toolchain PR reviewed and merged.
- Resolve any pending issues.

#### Important notes

- After the Concourse PR to remove the pipelines is merged, make sure to `fly dp -p <pipeline-name>`.
  PR only takes care of not deploying the pipeline again but doesn't actually delete the pipeline. Deletion is a manual step.
- This procedure to add the new toolchains is a general guideline. It may vary slightly based on personal preference and experience.
  The idea is to observe caution at all times and make sure that Concourse and OnePipeline never run concurrently for the same pipeline.

### Manually

Follow the [docs](https://cloud.ibm.com/docs/devsecops?topic=devsecops-tutorial-ci-toolchain) to spin up a test pipeline manually.
This must not be used for production toolchains.
