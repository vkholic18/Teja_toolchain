# Migrating Travis CI Pipelines to OnePipeline

> **Note:** All examples and references in this documentation are based on the compute-workspace repository.
You can refer to the implementation in this PR: [compute-workspace#5433](https://github.ibm.com/genctl/compute-workspace/pull/5433)

This document outlines the steps and required changes for teams migrating their CI pipelines from **Travis CI** to **OnePipeline**.

---

## 1. Remove Travis Environment Variables from `build.sh`

Remove all Travis-specific environment variables from your `build.sh` script.

🔗 [Reference](https://github.ibm.com/genctl/compute-workspace/blob/travis-migration-v11/hack/ci/build.sh)

---

## 2. Remove Common Repo Cloning

Previously, workspaces cloned the `common` repo from the `genctl-cicd` organization. This logic should be removed.

All common scripts are now available in the `genctl-ci` repository under:

```bash
onepipeline/scripts/common
```

Update all `source` commands to use the `PATH_TO_GENCTL_CI` environment variable:

For example:
```bash
# From:
source cicd-common/general_utils.sh

# To:
source ${PATH_TO_GENCTL_CI}/onepipeline/scripts/common/general_utils.sh
```
**🆕 Function Name Changes:**  
If you're using functions from the old common repo, note that some function names have been updated.

travis_check_error --> check_last_cmd_error

Make sure to replace such function calls accordingly throughout your scripts.

🔗 [Reference](https://github.ibm.com/genctl/compute-workspace/blob/2e05e765c539ea24f19b10764355a4c3819e8864/hack/ci/build.sh#L240)

---

## 3. Use `BUILD_ARTIFACT_TYPE` to Control Build Logic

Use the `BUILD_ARTIFACT_TYPE` environment variable to conditionally invoke logic for building images or packages:

- If `BUILD_ARTIFACT_TYPE=images` → Run image build logic  
- If `BUILD_ARTIFACT_TYPE=packages` → Run package build logic

🔗 [Reference](https://github.ibm.com/genctl/compute-workspace/blob/2e05e765c539ea24f19b10764355a4c3819e8864/hack/ci/build.sh#L320-L324)

---

## 4. Remove Push and Manifest Logic

In OnePipeline, image **push and manifest creation** are handled by CI.  
You should **remove** these steps from your workspace scripts.

---

## 5. Copy Build Artifacts to Upload Path

After building packages, copy the artifacts to the directory specified by CI for uploading to Artifactory.  
CI will only scan and upload artifacts from the directory defined in the `CI_ARTIFACTS_TO_UPLOAD_DIR` environment variable.

🔗 [References]  
- [Line 134-135](https://github.ibm.com/genctl/compute-workspace/blob/2e05e765c539ea24f19b10764355a4c3819e8864/hack/ci/build.sh#L134-L135)  
- [Line 297](https://github.ibm.com/genctl/compute-workspace/blob/2e05e765c539ea24f19b10764355a4c3819e8864/hack/ci/build.sh#L297)

---

## 6. Container Runtime for Builds

- Use **Docker** for building **amd64** images/packages.  
- Use **Podman** for building **s390x** images/packages.
    > **Note:** An alias has been added so that **podman** can be invoked using the **docker** command.
---

## 7. Use `docker_build_v2` for Image Builds

Due to Podman limitations, use the updated `docker_build_v2` function when building images for both amd64 and s390x

🔗 [Function Reference](https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/onepipeline/scripts/common/docker_utils.sh#L107-L139)
🔗 [Usage Reference](https://github.ibm.com/genctl/compute-workspace/blob/2e05e765c539ea24f19b10764355a4c3819e8864/hack/ci/build.sh#L269)

---

## 8. Podman Limitations

Podman comes with several limitations compared to Docker:

- ❌ **Secrets via `env=` Not Supported**  
  Podman does **not support** `env=` formatting for secrets (e.g. `--secret id=xxx,env=YYY`). This is supported in Docker with `buildx`, but not in Podman.

  ✅ **Solution:**  
  Create a file with the secret value and reference it in the `--secret` flag:

  ```bash
  echo "$TR_ARTIFACTORY_LOGIN" > /tmp/artif_user_secret
  echo "$TR_ARTIFACTORY_ACCESS_TOKEN" > /tmp/artif_apikey_secret

  podman build \
    --secret id=artif_user,src=/tmp/artif_user_secret \
    --secret id=artif_apikey,src=/tmp/artif_apikey_secret \
    .
  ```
  🔗 [References]
  - [Line 243-248](https://github.ibm.com/genctl/compute-workspace/blob/2e05e765c539ea24f19b10764355a4c3819e8864/hack/ci/build.sh#L243-L248)  
  - [Line 258](https://github.ibm.com/genctl/compute-workspace/blob/2e05e765c539ea24f19b10764355a4c3819e8864/hack/ci/build.sh#L258)
  🔐 Don’t forget to clean up temporary secret files after the build.

- 📦 **`podman manifest inspect` Limitation**  
  Only works for **multi-arch** images. It does **not** support regular single-arch manifests.

- 🚫 **No BuildKit / buildx Support**  
  Podman does not support Docker’s `BUILD_KIT`, `buildx`, or related advanced build features.

- 📥 **Requires Pull for Remote Image Inspection**  
  Podman must **pull a remote image locally** before inspecting it. Docker can inspect remote images directly.

---

## 9. No Need to Set Up Build Environment

CI runs each build in a dedicated container environment:
- **Ubuntu 22/24** for image and package builds

You do **not** need to manually configure the build environment in your scripts.

---

## 10. CRA Compliance Check is Handled by CI

Previously, artifacts were uploaded to Artifactory for CRA BOM checks.  
Now, **you don’t need to upload artifacts** for CRA.  
The compliance checks are automatically performed by CI during the image build task.

🔗 [References]
  - [cra-setup.sh](https://github.ibm.com/genctl/compute-workspace/blob/2e05e765c539ea24f19b10764355a4c3819e8864/hack/ci/cra-setup.sh)
---

## Support

If you have any questions, please reach out in the **`#vpc-ci-onepipeline`** Slack channel.