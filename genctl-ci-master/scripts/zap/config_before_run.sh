#!/bin/bash

function get_cluster_public_ip() {
  # Reduce log verbosity
  echo "Searching for cluster directory."
  cluster_dir=$(find -L ${PATH_TO_RIAS_GLOBALS_REPO} -type f -name "${BRT_ENVIRONMENT_NAME}\.yaml")
  if [[ -z ${cluster_dir} ]]; then
    echo "Cluster ${BRT_ENVIRONMENT_NAME} directory was not found in globals, no op"
    exit 1
  fi
  echo "Cluster directory : ${cluster_dir}."
  template_data=$(yq -r '.spec.strTemplates[]' "${cluster_dir}")
  export PUBLIC_IP=$(echo "${template_data}" | yq -r '.data.ingress' | jq -r '.hosts[0]')
  echo "Cluster public ip : ${PUBLIC_IP}"
  echo "${PUBLIC_IP}"
}

get_cluster_public_ip
# Fetch the Mzone API key
# After sourcing this script we should have the key in environment variable MZONE_APIKEY
source ${PATH_TO_GENCTL_CI}/scripts/zap/fetch_apikey.sh

if [[ ${PIPELINE_REPO_NAME} == "resource-metadata-workspace" ]]; then

  export DYNAMICSCAN_TOOL_IP=$(curl ipconfig.org)
  export API_ENDPOINT="https://${PUBLIC_IP}"

  # cleanup the residual resources if any before we create the VSI. 
  ${PATH_TO_WORKSPACE_REPO}/hack/ci/cleanup_after_metadata_scan.sh dmscan

  # create the VSI if we are enabling metadata service for dynamic scan with the vsi named as dmscan
  source ${PATH_TO_WORKSPACE_REPO}/hack/ci/setup_for_metadata_scan.sh dmscan

  echo "${VSI_PUBLIC_IP}"

  #generating the token from instance identity for metadata serivce.
  export DYNAMIC_SCAN_ACCESS_KEY=$(curl -X PUT "http://${VSI_PUBLIC_IP}/instance_identity/v1/token?version=2022-03-01" -H "Accept:application/json" -H "Metadata-Flavor:IBM" -d '{ "expires_in": 3600  }' | jq -r ".access_token")
  API_PUBLIC_IP="http://${VSI_PUBLIC_IP}"

else

  export DYNAMIC_SCAN_ACCESS_KEY=${DYNAMIC_SCAN_ACCESS_API_KEY}
  API_PUBLIC_IP="https://${PUBLIC_IP}/v1"

fi

# Api-key for IAM authentcation
set_env "target-api-key" "${DYNAMIC_SCAN_ACCESS_KEY}"

# set ibmcloud api key
set_env "ibmcloud-api-key" "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"

# set the url of the app to scan
# reading back the param that was exported in the dynamic-scan setup stage
set_env "target-application-server-url" "${API_PUBLIC_IP}" 

npm install -g json-refs

echo "Resolving schema refs in swagger"

echo "Profiles is ${PROFILES}"

python3 -m pip install -q ${PATH_TO_GENCTL_CI}/tools/ci_python_tools
python3 ${PATH_TO_GENCTL_CI}/scripts/zap/swagger_def.py ${PROFILES}

# The path to the files containing the Swagger definitions. Can be comma separated list
set_env "swagger-definition-files" "one-pipeline-config-repo/scripts/zap/Definition.json"

# If true, tail the ZAP scanner container log. This is the node app that exposes ZAP via an API, and starts ZAP, not ZAP itself.
set_env "show-container-log" "true"

# If true, tail the ZAP log. Use this to debug swagger problems, or where the scanner hangs, etc.
set_env "show-zap-log" "false"

# SET THE WORKING
cd "${WORKSPACE}" || exit 1
echo "SET THE WORKING DIRECTORY= ${WORKSPACE}"

# SET UP A RESULTS FILTER High, Medium, Low, Informational (Optional). Recommended to filter out Informational
set_env "filter-options" "Informational"

# FLAG FOR RUNNING API SCAN AS DIND default is false
set_env "zap_dind" "true"

#set an optional custom file to modify the swagger definition before it is sent to be scan
set_env "zap-api-custom-script" "one-pipeline-config-repo/scripts/zap/custom-api-script.sh" 