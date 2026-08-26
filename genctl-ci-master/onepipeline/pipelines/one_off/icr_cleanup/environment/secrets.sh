
#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Secrets are ordered from the most to the least used
# In case used the same amount of time then they are ordered according to first use in pipeline

env_props_secure=(

    "IBM_CLOUD_KEY:ibmcloud-api-key"
    "GITHUB_TOKEN:git-tokenn"
    
)

env_props_text=(

    "ibm_cloud_region:ibm_cloud_region"
    "GHE_API_URL:GHE_API_URL"
)

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"