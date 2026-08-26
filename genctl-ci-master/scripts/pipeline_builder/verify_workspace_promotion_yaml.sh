#!/bin/bash

PROMOTION_YAML_FILE_NAME=$1
WORKSPACE=$2
PERFORM_CHECKS=$3

PROMOTION_YAML_FILE_LOCATION="${WORKSPACE}/hack/ci/${PROMOTION_YAML_FILE_NAME}"

if [ ! -f ${PROMOTION_YAML_FILE_LOCATION} ]; then
  echo "Failed to find promotion yaml at ${PROMOTION_YAML_FILE_LOCATION}"
  exit 1
fi

check_promotion_key()
{
  YAML_PATH=$1
  KEY=$2
  PROMOTION_YAML=$3
  RETURN_VALUE=$4

  result=$(yq "${YAML_PATH} | has(\"${KEY}\")" ${PROMOTION_YAML})

  if [ "${result}" == "false" ]; then
    echo "Failed to find ${YAML_PATH}.${KEY} key in ${PROMOTION_YAML}"
    exit 1
  fi

  result=$(yq "${YAML_PATH}.${KEY} | length" ${PROMOTION_YAML})

  if [ "${result}" == "0" ]; then
    echo "Found empty value for ${YAML_PATH}.${KEY} key in ${PROMOTION_YAML}"
    exit 1
  fi

  if [[ ${RETURN_VALUE} == "true" ]]
  then
    yq -r "${YAML_PATH}.${KEY}" ${PROMOTION_YAML}
  fi
}

if [[ ${PERFORM_CHECKS} == "true" ]]
then
  # Check that feature_flag.vpc-ci key is defined.
  check_promotion_key ".feature_flag" "vpc-ci" "${PROMOTION_YAML_FILE_LOCATION}" "false"

  # Check that pre_integration_environments key is defined.
  check_promotion_key "." "pre_integration_environments" "${PROMOTION_YAML_FILE_LOCATION}" "false"
fi
