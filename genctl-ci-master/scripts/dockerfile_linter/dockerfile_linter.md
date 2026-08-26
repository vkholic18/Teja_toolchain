# Dockerfile linter

This linter scans all the Dockerfiles in the supplied repository and finds any Docker files that aren't compliant with the Service Framework and FedRAMP guidelines as outlined in [ARCH004](https://github.ibm.com/cloud-docs-internal/service-framework/blob/master/generated_content/ARCH.md#arch004---container-provenance).  It checks for three issues:
- Dockerfile running as root
- Dockerfile using non-trusted images
- Dockerfile using non-trusted imports

Trusted sources are listed in [config.yaml](https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/scripts/dockerfile_linter/config.yaml) based on guidance from the [CISO Public Package Repository](https://github.ibm.com/CloudEngineering/system_architecture/blob/master/docs/devops/trusted_repos.md) list

### How to fix your lint errors

#### Scan failed for root user

- If there is no `USER` defined, the linter assumes that the default user `root` is being used.
- If there is `USER` defined, make sure the last `USER` in the Dockerfile is non-root.

#### Scan failed for non-trusted images

All images must be based on either UBI or Scratch. Alpine, BusyBox, or other base images will cause the linter to fail.

The linter scans all the `FROM` lines in the dockerfile and ensures that the listed source repositories or the image names (if the source repository is absent) match the trusted sources in the [config.yaml](https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/scripts/dockerfile_linter/config.yaml#L19). For the multi-staged builds, all the layers must contain a trusted image. If there is no match, the linter would fail.

- The container images can only be UBI or scratch based. Related ticket [here](https://github.ibm.com/cloudlab/ServiceFramework/issues/312).
- The container images must be pulled from the trusted sources, as listed in [config.yaml](https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/scripts/dockerfile_linter/config.yaml#L19)

#### Scan failed for non-trusted imports

- The third-party packages must be pulled from the trusted sources, as listed in [config.yaml](https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/scripts/dockerfile_linter/config.yaml#L19)
- If you need to download from the sources not listed as `trusted_sources` in the [config.yaml](https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/scripts/dockerfile_linter/config.yaml#L19), check out the [Open Source Projects documentation](https://github.ibm.com/CloudEngineering/system_architecture/blob/master/docs/devops/trusted_repos.md#open-source-projects) to get the approval.
