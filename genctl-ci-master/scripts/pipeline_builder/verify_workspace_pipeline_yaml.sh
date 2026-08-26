#!/bin/bash

WORKSPACE=$1
PERFORM_CHECKS=$2

PIPELINE_YAML_FILE_LOCATION="${WORKSPACE}/hack/ci/pipeline.yaml"

if [ ! -f ${PIPELINE_YAML_FILE_LOCATION} ]; then
  echo "Failed to find pipeline.yaml at ${PIPELINE_YAML_FILE_LOCATION}"
  exit 1
fi

check_pipeline_key()
{
  YAML_PATH=$1
  KEY=$2
  PIPELINE_YAML=$3
  RETURN_VALUE=$4

  result=$(yq "${YAML_PATH} | has(\"${KEY}\")" ${PIPELINE_YAML})

  if [ "${result}" == "false" ]; then
    echo "Failed to find ${YAML_PATH}.${KEY} key in ${PIPELINE_YAML}"
    exit 1
  fi

  result=$(yq "${YAML_PATH}.${KEY} | length" ${PIPELINE_YAML})

  if [ "${result}" == "0" ]; then
    echo "Found empty value for ${YAML_PATH}.${KEY} key in ${PIPELINE_YAML}"
    exit 1
  fi

  if [[ ${RETURN_VALUE} == "true" ]]
  then
    yq -r "${YAML_PATH}.${KEY}" ${PIPELINE_YAML}
  fi
}

if [[ ${PERFORM_CHECKS} == "true" ]]
then
  # Check that deployment.feature_flag key is defined.
  check_pipeline_key ".deployment" "feature_flag" "${PIPELINE_YAML_FILE_LOCATION}" "false"

  # Check that deployment.rule_tag key is defined.
  check_pipeline_key ".deployment" "rule_tag" "${PIPELINE_YAML_FILE_LOCATION}" "false"

  # Check that deployment.iks_cluster_name key is defined.
  check_pipeline_key ".deployment" "iks_cluster_name" "${PIPELINE_YAML_FILE_LOCATION}" "false"

  # Check that deployment.mzone_name key is defined.
  check_pipeline_key ".deployment" "mzone_name" "${PIPELINE_YAML_FILE_LOCATION}" "false"

  # Check that deployment.api_key_alias key is defined.
  check_pipeline_key ".deployment" "api_key_alias" "${PIPELINE_YAML_FILE_LOCATION}" "false"

  # Check that functional_tests.cpap.integration_testing_repo.test_configs is defined.
  if [ "$(yq '.functional_tests.cpap.integration_testing_repo | has("test_configs")' ${PIPELINE_YAML_FILE_LOCATION})" == "false" ]; then
    echo "Failed to find functional_tests.cpap.integration_testing_repo.test_configs key in ${PIPELINE_YAML_FILE_LOCATION}"
    exit 1
  fi

  # Check that functional_tests.cpap.integration_testing_repo.test_configs contains at least one entry.
  if [ "$(yq '.functional_tests.cpap.integration_testing_repo.test_configs | length' ${PIPELINE_YAML_FILE_LOCATION})" == "0" ]; then
    echo "Failed to find at least one functional_tests.cpap.integration_testing_repo.test_configs entry in ${PIPELINE_YAML_FILE_LOCATION}"
    exit 1
  fi
fi
