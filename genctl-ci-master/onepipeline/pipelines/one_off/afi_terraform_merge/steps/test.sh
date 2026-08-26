#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -o pipefail

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# this script is internal to devsecops/baseimage image
source "${COMMONS_PATH}/terraform/terraform-utilities.sh"

# Set the pipeline template type
export PIPELINE_TYPE="merge"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# remove previous terraform installation - new installation defaults to 1.2.9
# "${COMMONS_PATH}/terraform/terraform-utilities.sh" has a function called terraform_install
# this function install by default terraform 1.2.9, or uses environment variable called terraform-version
# the variable terraform-version is also set on the pipeline and defaults to 1.2.9 in case the original default changes
if which terraform; then
  echo "removing old terraform version"
  rm -f $(which terraform)
fi

terraform_version="$(get_env terraform-version "1.10.2")"

curl https://releases.hashicorp.com/terraform/$terraform_version/terraform_${terraform_version}_linux_amd64.zip -o terraform.zip
unzip -o terraform.zip
chmod +x terraform
mv terraform /usr/bin/

if command -v terraform &>/dev/null; then
  terraform version
else
  echo "Terraform is NOT installed."
  exit 1
fi

rm -rf terraform.zip

# prepare terraform context (tfvars & TF_VAR export)
terraform_tfvars_setup
terraform_env_export

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

cd ${PATH_TO_WORKSPACE}

GIT_SHA=$(git rev-parse --verify HEAD)

# setup artifactory backend creds
${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/setup_terraform.sh

# workspace_name is an alias for TF_WORKSPACE which is an environment variable used to pick backend workspace without using the CLI
echo "Selecting workspace name: $workspace_name"

# Set the SSH - needed for core module repo clone
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

# running terraform init
echo "------------------------ Running: terraform init ------------------------"
terraform init && export INIT_STATUS="Success" || export INIT_STATUS="Failure"

echo "------------------------ Running: terraform output ------------------------"
terraform output

# running terraform plan
echo "------------------------ Running: terraform plan ------------------------"
terraform plan -parallelism=3 -no-color -input=false -out ${PATH_TO_WORKSPACE}/plantf | tee ${PATH_TO_WORKSPACE}/plan_show.txt  && export PLAN_STATUS="Success" || export PLAN_STATUS="Failure"

python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/requirements.txt
python3 ${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/get_pr_md5.py -o ${PATH_TO_WORKSPACE}/pr_md5.txt -s ${GIT_SHA}

# checking for status failure
if [[ $PLAN_STATUS = "Failure" || $INIT_STATUS = "Failure" ]]; then
  echo "Preliminary checks failed, exiting..."
  unset artifactory_token
  rm -f ${PATH_TO_WORKSPACE}/plantf
  rm -f ~/.terraform.d/credentials.tfrc.json
  exit 1
fi

# extract and print md5 values for each of the pr/merge plans
MD5_PR=$(cat ${PATH_TO_WORKSPACE}/pr_md5.txt)
MD5SUM_MERGE=$(terraform show -no-color ${PATH_TO_WORKSPACE}/plantf | md5sum | cut -f 1 -d ' ')
echo "Terraform pr    plan (MD5): $MD5_PR"
echo "Terraform merge plan (MD5): $MD5SUM_MERGE"

# if the plan file from the PR pipeline no longer matches what the merge pipeline intends to do, fail
if [[ "${MD5_PR}" != "${MD5SUM_MERGE}" ]]; then
    echo "ERROR: The PR plan no longer matches what the merge pipeline intends to deploy!"
    rm -f ${PATH_TO_WORKSPACE}/plantf
    rm -f ~/.terraform.d/credentials.tfrc.json
    exit 1
fi

# apply the plan if this is a merge pipeline (double check)
if [[ "$(get_env pipeline_namespace)" == *"ci"* ]]; then
  echo "This is a CI pipeline, applying plan..."
  terraform apply -parallelism=3 ${PATH_TO_WORKSPACE}/plantf \
      && export APPLY_STATUS="Success" || export APPLY_STATUS="Failure"
  echo "apply status $APPLY_STATUS"

  # =============================================================================
  # Slack notification — apply result
  # =============================================================================
  UTILS_DIR="${PATH_TO_GENCTL_CI}/onepipeline/utils"

  # Extract the plan summary line for context in the notification
  PLAN_SUMMARY=$(grep -E '^Plan:' ${PATH_TO_WORKSPACE}/plan_show.txt || echo "Plan: N/A")

  # Map apply result to a verdict the notifier understands (green=APPROVE, red=BLOCK)
  if [[ "${APPLY_STATUS}" == "Success" ]]; then
      _APPLY_VERDICT="SUCCESS"
      _APPLY_SUMMARY="Apply: SUCCESS | ${PLAN_SUMMARY}"
  else
      _APPLY_VERDICT="FAILURE"
      _APPLY_SUMMARY="Apply: FAILURE | ${PLAN_SUMMARY}"
  fi

  # Only tag on failure — a successful merge apply needs no human attention
  _MERGE_TAG_ARG=()
  [[ "${APPLY_STATUS}" != "Success" ]] && _MERGE_TAG_ARG=(--tag-group "${SLACK_TAG_GROUP:-}")

  echo "[SLACK] Posting apply result to Slack..."
  bash "${UTILS_DIR}/notify_terraform_review.sh" \
      --webhook-url    "${SLACK_WEBHOOK_URL:-}" \
      --channel        "${SLACK_CHANNEL:-}" \
      --verdict        "${_APPLY_VERDICT}" \
      --pipeline-url   "${PIPELINE_RUN_URL:-}" \
      "${_MERGE_TAG_ARG[@]}" \
      --workspace      "${workspace_name}" \
      --mode           "infrastructure" \
      --pipeline-type  "Merge" \
      --repo           "${WORKSPACE_REPO:-}" \
      --plan-summary   "${_APPLY_SUMMARY}" || true   # non-fatal

  # Exit non-zero if apply failed so the pipeline step is marked as failed
  if [[ "${APPLY_STATUS}" == "Failure" ]]; then
      echo "Terraform apply failed — exiting with error."
      exit 1
  fi
fi
