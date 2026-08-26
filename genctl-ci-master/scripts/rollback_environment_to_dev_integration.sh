#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

#AUTH_TOKEN: ((vault-launch-darkly-api-key))
#GIT_TOKEN: ((ghe-access-token))
#LAUNCH_DARKLY_ENVIRONMENT (e.g development)

set -ex
if [[ -f ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml ]]; then
  LAUNCH_DARKLY_FEATURE_FLAG=$(yq -r '.deployment.feature_flag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
  LAUNCH_DARKLY_RULE_TAG=$(yq -r '.deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
else
  LAUNCH_DARKLY_FEATURE_FLAG=""
  LAUNCH_DARKLY_RULE_TAG=""
fi
echo "LAUNCH_DARKLY_FEATURE_FLAG=${LAUNCH_DARKLY_FEATURE_FLAG}"
echo "LAUNCH_DARKLY_RULE_TAG=${LAUNCH_DARKLY_RULE_TAG}"

if [[ -z "${LAUNCH_DARKLY_FEATURE_FLAG}" || -z "${LAUNCH_DARKLY_RULE_TAG}" ]]; then
  echo "Warning: LAUNCH_DARKLY_FEATURE_FLAG or LAUNCH_DARKLY_RULE_TAG is not defined. Exiting ..."
  exit 0
fi
source ${PATH_TO_GENCTL_CI}/scripts/retry.sh
retry python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/featureflags/requirements.txt
#all feature flags that shared environment LAUNCH_DARKLY_RULE_TAG  with LAUNCH_DARKLY_FEATURE_FLAG will be rolled to last commit on dev-integration branch
for rule_tag in $(echo ${LAUNCH_DARKLY_RULE_TAG} | tr "," "\n")
do
  if [[ -z "${rule_tag}" ]]; then
    continue
  fi
  echo "executing: python3 ${PATH_TO_GENCTL_CI}/scripts/featureflags/featureflags.py "" rollback_to_dev ${LAUNCH_DARKLY_ENVIRONMENT} ${rule_tag} ${LAUNCH_DARKLY_FEATURE_FLAG} *****"
  set +x
  python3 ${PATH_TO_GENCTL_CI}/scripts/featureflags/featureflags.py "" rollback_to_dev ${LAUNCH_DARKLY_ENVIRONMENT} ${rule_tag} ${LAUNCH_DARKLY_FEATURE_FLAG} ${GIT_TOKEN}
  set -x
done
