# Third-party images in CI

The following workspaces include third-party images in their deployment process.
The list of the third-parties images is defined in a hack/ci/third-party-images.yaml

https://github.ibm.com/genctl/infrastructure-service-workspace/blob/master/hack/ci/third-party-images.yaml

https://github.ibm.com/genctl/monitoring-workspace/blob/master/hack/ci/third-party-images.yaml

https://github.ibm.com/genctl/kerberos-workspace/blob/master/hack/ci/third-party-images.yaml

https://github.ibm.com/genctl/apigateway-workspace/blob/master/hack/ci/third-party-images.yaml

TODO: https://github.ibm.com/genctl/logging-workspace/tree/dev-integration
## How does it work ?

The dev team that needs to use third-party images is required to:

1. Pull the third-party images they plan to use for all supported platforms.
2. Create a manifest for a third-party image that includes all supported platforms.
3. Push the image manifest and images to docker-na-public.artifactory.swg-devops.com/wcp-genctl-sandbox-docker-local (deprecated).
4. Push the image manifest and images to us.icr.io/vpc-sandbox-docker-local 


### For example:

### sysdig/agent-slim:13.8.0

docker manifest create us.icr.io/vpc-sandbox-docker-local/sysdig/agent-slim:13.8.0
us.icr.io/vpc-sandbox-docker-local/sysdig/agent-slim:13.8.0-amd64
us.icr.io/vpc-sandbox-docker-local/sysdig/agent-slim:13.8.0-s390x

docker push us.icr.io/vpc-sandbox-docker-local/sysdig/sysdig/agent-slim:13.8.0-amd64

docker push us.icr.io/vpc-sandbox-docker-local/sysdig/sysdig/agent-slim:13.8.0-s390x

docker push us.icr.io/vpc-sandbox-docker-local/sysdig/sysdig/agent-slim:13.8.0

The deployment files need to support a new third-party versioning format

### CI side

In the PR to dev-integration, we pull from sandbox and we push to sandbox but we add prefix and we change
the tag to the SHA

In the merge to dev-integration, we pull from sandbox and we push to sandbox with SHA and SemVer and
in addition we push to prod with SHA and SemVer

In addition, in the merge to dev-integration we save artifacts for this images; in other words, they are treated
like regular “propietary” images and this allows them to be scanned in build-scan-artifact.
Third party images are also reflected in inventory

