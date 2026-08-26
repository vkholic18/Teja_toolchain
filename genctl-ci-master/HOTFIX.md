# Genctl Hotfixes
Here is a link to slides for an overview and examples of the hotfix workflow: [Slides in Box](https://ibm.box.com/s/qy6tdhkxwvp4247ezeraya8s7pxd2f3k)
> Note: This is a tactical process until the strategic solution can be implemented.

## Example Hotfix
The following links are live and will remain as placeholders to demonstrate the
hotfix process end to end:
1. Developer delivers hotfix to stable workspace branch: [https://github.ibm.com/genctl/api-workspace/pull/865](https://github.ibm.com/genctl/api-workspace/pull/865)
2. Operations delivers hotfix to stable orda branch: [https://github.ibm.com/genctl/orda/pull/41](https://github.ibm.com/genctl/orda/pull/41)

## Add Workspace Hotfix Support
Extending the base hotfix pipeline to support an orda component includes the
following high level steps:
1. Configure workspace repo stable branch
2. Extend hotfix pr pipeline definition

### Configure workspace repo stable branch
Create the `stable` branch for your workspace, from the submodule commit
referenced by the latest stable orda branch for your workspace. Once you have
created the stable branch, you need to copy the branch restrictions to it from
what you have for master. This step needs to be done in the repo settings on
GitHub, under `Branches`.

### Extend hotfix pr pipeline definition
In this step you are going to first add the workspace's image build process to the
`build-bumped-workspace-images` job in the [orda-hotfix-pr.yaml](orda-hotfix-pr.yaml)
file in this repository. Then you'll enable pipeline builds on all PRs to your
workspace.

For the first part, here is the PR that added api-workspace hotfix pipeline support:
[https://github.ibm.com/genctl-cicd/genctl-ci/pull/172](https://github.ibm.com/genctl-cicd/genctl-ci/pull/172)
Not everything in this PR is required for this first part, the main parts are the:
- [Additional pipeline resources for your workspace](https://github.ibm.com/genctl-cicd/genctl-ci/pull/172/files#diff-eb01bf2bfd72bb425a3ffec04a4f128bR478)
- [Adding your workspace image builds](https://github.ibm.com/genctl-cicd/genctl-ci/pull/172/files#diff-eb01bf2bfd72bb425a3ffec04a4f128bR93)

To enable pipeline builds on all PRs to your workspace, you need to find your
workspace's PR pipeline definition in this repository. For example the
network-workspace's PR pipeline definition is [network-pr.yaml](network-pr.yaml)
Once you have that, locate the pull request resource under the `resources` section
that pertains to your workspace. Continuing along with the network example, their
PR resource is called `network-workspace-pr`. In order to enable pipeline builds
on all PRs to this workspace, simply remove the line under this resource that has
the key `base`. Here is the PR for the network workspace example removal [Enable all PR Builds](https://github.ibm.com/genctl-cicd/genctl-ci/pull/167/files#diff-a721c0677dfc87326322784ec8582415L226)
