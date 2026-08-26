#!/bin/bash

# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# DEFINITION_FILE represents the json definition as listed in swagger-definition-files 
# json-refs is sensitive to the file extension. If you give it a .yaml file, it will output yaml. Use .json.
# The file must be in the right dir to resolve relative schema refs in other files
# API_DATA_FILE is the expected file location for the modified data that will be sent to the scan. 
SWAGGER_DIR="$(dirname "${DEFINITION_FILE}")"
echo "SWAGGER_DIR: $SWAGGER_DIR"
echo "DEFINITION_FILE: $DEFINITION_FILE"
SWAGGER_JSON_FILE="${SWAGGER_DIR}/_temp.json"
cp "${DEFINITION_FILE}" "${SWAGGER_JSON_FILE}"

echo "Print SWAGGER_JSON_FILE"
cat "${SWAGGER_JSON_FILE}"

echo "Category name is ${CATEGORY_NAME}"
echo "API file name is ${API_FILE_NAME}"
echo "Profiles is ${PROFILES}"
echo "Endpoint is ${ENDPOINTS}"
echo "Exclude entries is ${EXCLUDE_ENTRIES}"

# resolve any schema $refs to form a complete all-in-one swagger doc
echo "Installing json-refs"
npm install -g json-refs
echo "Resolving schema refs in swagger"
json-refs resolve "${SWAGGER_JSON_FILE}" > _resolved.json

echo "Print _resolved"

# Add a global exclusion to prevent a false positive issue with this sample application like:
# Unexpected Content-Type was returned
# A Content-Type of text/html was returned by the server.This is not one of the types expected to be returned by an API.
# Raised by the 'Alert on Unexpected Content Types' script
echo "Target application server url is: $TARGET_APPLICATION_SERVER_URL"
APP_URL_REGEX=$(echo $TARGET_APPLICATION_SERVER_URL | sed 's:/*$::')
app_url_regex="^${APP_URL_REGEX//\//\\\/}\$"

export EST="[]"
# # export ATS=$(jq -Rn --arg v "$ENDPOINTS" '($v | split(",") | map(select(. != "")))')
# export ATS=$(jq -Rn --arg v "$ENDPOINTS" '$v | split(",") | map(select(. != ""))')

clean=${ENDPOINTS//[“”]/}

export ATS=$(jq -r \
  --arg profiles "$PROFILES" \
  --arg endpoints "$ENDPOINTS" \
  --argjson exclude_entries "${EXCLUDE_ENTRIES:-[]}" '
  # Get all paths from swagger
  .paths | to_entries as $all_paths |
  
  if $profiles == "all" and $endpoints == "all" then
    # Scan everything - all paths with all methods
    $all_paths | map(
      .key as $path |
      .value | to_entries |
      map(select(.key != "parameters") | {
        path: $path,
        method: .key
      })
    ) | flatten
    
  elif $endpoints == "all" then
    # Scan all paths under specific profiles
    ($profiles | split(",") | map(select(. != ""))) as $profile_list |
    $all_paths | map(
      .key as $path |
      # Check if path starts with any of the profiles
      if ($profile_list | map("/" + .) | map($path | startswith(.)) | any) then
        .value | to_entries |
        map(select(.key != "parameters") | {
          path: $path,
          method: .key
        })
      else
        empty
      end
    ) | flatten
    
  elif $profiles == "all" then
    # Scan specific endpoint patterns across all paths
    ($endpoints | split(",") | map(select(. != ""))) as $endpoint_list |
    $all_paths | map(
      .key as $path |
      # Match endpoint patterns (e.g., "list" matches "/account_namespaces")
      if ($endpoint_list | map($path | contains(.)) | any) then
        .value | to_entries |
        map(select(.key != "parameters") | {
          path: $path,
          method: .key
        })
      else
        empty
      end
    ) | flatten
    
  else
    # Specific profiles and endpoints
    ($profiles | split(",") | map(select(. != ""))) as $profile_list |
    ($endpoints | split(",") | map(select(. != ""))) as $endpoint_list |
    
    $all_paths | map(
      .key as $path |
      # Check if path starts with profile AND contains endpoint pattern
      if (
        ($profile_list | map("/" + .) | map($path | startswith(.)) | any) and
        ($endpoint_list | map($path | contains(.)) | any)
      ) then
        .value | to_entries |
        map(select(.key != "parameters") | {
          path: $path,
          method: .key
        })
      else
        empty
      end
    ) | flatten
  end |
  # Apply exclusions: remove any entry that exactly matches an excluded {path, method} pair
  if ($exclude_entries | length) > 0 then
    map(select(
      . as $entry |
      ($exclude_entries | map(
        .path == $entry.path and .method == $entry.method
      ) | any) | not
    ))
  else
    .
  end
' "$(pwd)/_resolved.json")

echo "printing ats json"
echo $ATS
if [[ ${PIPELINE_REPO_NAME} == "resource-metadata-workspace" ]]; then
    export authtype="Bearer"
else   
    export authtype="ApiKey"
fi

jq --argjson ats "${ATS}" \
--arg est "${EST}" \
--arg at "${authtype}" \
'{excludeScanTypes: $est,
    apisToScan: $ats,
    authenticationType: $at,
    globalExcludeUrls: [ ".*\/cdn-cgi.*" ],
    apiDefinitionJson: .
}' "$(pwd)/_resolved.json" > "${API_DATA_FILE}"


cat "${API_DATA_FILE}" | jq --arg servers "${TARGET_APPLICATION_SERVER_URL}" '.apiDefinitionJson.servers = [{"url":$servers}]' > api_data_temp.json
mv api_data_temp.json "${API_DATA_FILE}"
# end  - added custom "servers url" property for ghost
# clean up
rm "${SWAGGER_JSON_FILE}"
rm _resolved.json
