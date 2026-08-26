#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This step implements standard OnePipeline signing process running within csso-image-sign and call ciso/sign_artifactory.sh
# Latest image version to be used from: https://github.ibm.com/one-pipeline/compliance-commons-internal/blob/master/one-pipeline-defaults.yaml#L47
# Signing script code location: https://github.ibm.com/one-pipeline/compliance-commons-internal/blob/master/ciso/sign_artifactory.sh
# sign_artifactory.sh signs images that were saved as artifact in previous stage: https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/onepipeline/pipelines/templatized/merge_dev_integration/steps/test.sh#L68-L69
# due to the issue #  the signing script can sign only images located in artifactory and can not in ICR. This is why we need to save_artifact ICR images
# after signing stage is completed
# The following environment variables are required for sign_artifactory.sh
#  artifactory-docker-repo-name = wcp-genctl-docker-local
#  artifactory-primary-service = na
#  artifactory-sigstore-repo-name = wcp-genctl-sandbox-generic-local
#  taas-artifactory-token = Default.wcp-genctl-docker-local-artifactory-token
#  taas-artifactory-user = Default.wcp-genctl-docker-local-artifactory-username
# OnePipeline signing documenttion: https://test.cloud.ibm.com/docs/devsecops?topic=devsecops-devsecops-imagesigning

### Actual call to signing ###
/opt/commons/ciso/sign_artifactory.sh
