---
name: OnePipeline Onboarding
about: Template to create onboarding requests to OnePipeline
title: Onboard <workspace-name>
labels: New Onboard Request
assignees: ''

---

## Which workspace is to be onboarded?
< Add your workspace GitHub URL >

## Is the workspace configured for OnePipeline?
If not, please follow these guidelines:
1. Create a separate branch `onepipeline-test` off of your master branch to push the new files required for OnePipeline.
2. Follow our [migration guide](https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/onepipeline/Documentation/OnePLMigrationGuide.md) to make the changes.
3. Once done, attach the label `Workspace Ready` to this Issue. This will enable us to schedule it as soon as we can.
4. For any questions/issues, slack us on #vpc-ci-onepipeline.
