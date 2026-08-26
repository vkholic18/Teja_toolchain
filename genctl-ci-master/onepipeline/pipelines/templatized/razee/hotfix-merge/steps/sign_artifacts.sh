#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# The following environment variables are required for sign_artifactory.sh
#  artifactory-docker-repo-name = wcp-genctl-docker-local
#  artifactory-primary-service = na
#  artifactory-sigstore-repo-name = wcp-genctl-sandbox-generic-local
#  taas-artifactory-token = Default.wcp-genctl-docker-local-artifactory-token
#  taas-artifactory-user = Default.wcp-genctl-docker-local-artifactory-username
# OnePipeline signing documenttion: https://test.cloud.ibm.com/docs/devsecops?topic=devsecops-devsecops-imagesigning

### Actual call to signing ###
/opt/commons/ciso/sign_artifactory.sh