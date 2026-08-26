#!/usr/bin/env bash

set -ex

declare -A env_lookup
env_lookup["global-dev"]="development"
env_lookup["global-integ"]="integration"
env_lookup["global-staging"]="staging"
env_lookup["global-prod"]="production"

config_type="${1}"

if ! [[ -v env_lookup["$WORKSPACE_REPO_NAME"] ]]; then
  echo "Workspace name '$WORKSPACE_REPO_NAME' does not exist. Exiting."
  exit 1
fi

COS_FF_CONFIGMAP_FOLDER=${env_lookup["$WORKSPACE_REPO_NAME"]}
if [ -n "${ENV_OVERRIDE}" ]; then
  COS_FF_CONFIGMAP_FOLDER=${ENV_OVERRIDE}
fi

upload_data_to_cos() {
  local cos_upload_filter="${1}"
  if [[ ! -z ${COS_BUCKET_LIST} ]]; then
    echo "Using provided COS bucket list"
    retry python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/upload_cos_requirements.txt
    # shellcheck disable=SC2068
    for bucket in ${COS_BUCKET_LIST[@]}; do
      bucket_region=$(echo $bucket | awk -F/ '{print $1}')
      bucket_name=$(echo $bucket | awk -F/ '{print $2}')
      endpoint_url=$(echo $COS_ENDPOINT_TEMPLATE | sed "s/REGION/${bucket_region}/")
      if [[ -d ${FEATUREFLAGS_BASE_DIR} ]]; then
        python3 ${PATH_TO_GENCTL_CI}/scripts/upload_to_cos.py ${bucket_name} ${FEATUREFLAGS_BASE_DIR} ${COS_FF_CONFIGMAP_FOLDER} --cos-upload-filter ${cos_upload_filter} --cos-endpoint-url ${endpoint_url}
      else
        echo "The directory ${FEATUREFLAGS_BASE_DIR} does not exist."
        break
      fi
    done
  else
    echo "COS bucket list is not defined"
  fi
}

source ${PATH_TO_GENCTL_CI}/scripts/retry.sh
retry python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/configure_featureflags/requirements.txt

if [ $config_type == "featureflags-config" ]; then
  retry python3 ${PATH_TO_GENCTL_CI}/scripts/configure_featureflags/configure_featureflags.py --env-yaml-path ${PATH_TO_WORKSPACE_REPO}/environment.yaml --path-to-genctl-ci ${PATH_TO_GENCTL_CI} --service-flags-path ${PATH_TO_WORKSPACE_REPO}/service-flags/
  upload_data_to_cos $COS_UPLOAD_FILES_FILTER
elif [ $config_type == "features-api-config" ]; then
  retry python3 ${PATH_TO_GENCTL_CI}/scripts/configure_featureflags/configure_features_api_data.py --env-yaml-path ${PATH_TO_WORKSPACE_REPO}/environment.yaml --path-to-genctl-ci ${PATH_TO_GENCTL_CI} --path-to-api-spec-repo ${PATH_TO_API_SPEC_REPO} --path-to-features-api-data ${PATH_TO_APISPEC_FEATURES_YAML}
  upload_data_to_cos $FEATURES_API_DATA_FILTER
fi