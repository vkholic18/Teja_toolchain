#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================


# secrets used for scripts
export GIT_TOKEN_PATH="${WORKSPACE}/git-token" #from 1P environment settings?
export GITHUB_API_KEY=$(cat ${GIT_TOKEN_PATH})


env_props_secure=(

   "GITHUB_USERNAME:vault-git-config-username" 
)

env_props_text=(

)

export_env_props "${env_props_text[@]}" "text"
export_env_props "${env_props_secure[@]}" "secure"