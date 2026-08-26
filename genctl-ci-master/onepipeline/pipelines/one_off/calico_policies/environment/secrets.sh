#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Secrets are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline


env_props_secure=(
   "ONE_PIPELINE_CI_IBM_CLOUD_API_KEY:ibmcloud-api-key"
)

env_props_text=(
    "CLUSTER_ID:cluster-id"
    "CALICO_OPERATION:calico-operation"
    "CLUSTER_REGION:cluster-region"

)

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"