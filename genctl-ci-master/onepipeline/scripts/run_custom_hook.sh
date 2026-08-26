#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2025
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

#
# This scripts exports all environment variables and secrets undre "ci_hook" in pipeline.yaml of that workspace
# Then it triggers the script they provided under path_to_script
#


REPO_YAML="${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml"
export PATH_TO_SCRIPT=$(yq -r '.ci_hook.path_to_script | select(. != null)' ${REPO_YAML})

cd ${PATH_TO_WORKSPACE_REPO}

if [[ -z "${PATH_TO_SCRIPT}" ]] || [[ ! -f "${PATH_TO_SCRIPT}" ]]; then
    echo "The script for the hook is not set / does not exists / is not executable, exiting"
    exit 1
fi

# Dynamically export environment variables
if yq -e '.ci_hook.environment | keys | length > 0' "${REPO_YAML}" >/dev/null 2>&1; then
  while IFS= read -r line; do
    eval "$line"
  done < <(yq -r '.ci_hook.environment | to_entries | .[] | "export \(.key)=$(get_env \(.value))"' "${REPO_YAML}")
else
  echo "No environment variables found in .ci_hook.environment."
fi

# Dynamically export parameters
if yq -e '.ci_hook.parameters | keys | length > 0' "${REPO_YAML}" >/dev/null 2>&1; then
  while IFS= read -r line; do
    export "$line"
  done < <(yq -r '.ci_hook.parameters | to_entries | .[] | "\(.key)=\(.value)"' "${REPO_YAML}")
else
  echo "No parameters found in .ci_hook.parameters."
fi

echo "runing custom script - ${NAME}"
source "$PATH_TO_SCRIPT"
echo "${NAME} - completed"
