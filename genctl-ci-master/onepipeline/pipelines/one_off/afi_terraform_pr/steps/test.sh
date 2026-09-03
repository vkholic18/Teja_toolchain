#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -euo pipefail

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# this script is internal to devsecops/baseimage image
source "${COMMONS_PATH}/terraform/terraform-utilities.sh"

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
set +u
terraform_tfvars_setup
terraform_env_export
echo "there are cocoa image issues that should be fixed above that require us to loosen checks"
set -u

# source required properties
source ${PATH_TO_PIPELINE}/environment/vars.sh
source ${PATH_TO_PIPELINE}/environment/secrets.sh
source ${PATH_TO_PIPELINE}/environment/aliases.sh

cd ${PATH_TO_WORKSPACE}

# setup artifactory backend creds
${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/setup_terraform.sh

# workspace_name is an alias for TF_WORKSPACE which is an environment variable used to pick backend workspace without using the CLI
echo "Selecting workspace name: $workspace_name"

# Set the SSH - needed for core module repo clone
eval "$(ssh-agent -s)"
echo -e "${GIT_PRIVATE_KEY}" | ssh-add -
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL:-}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME:-}"

set +e
# running terraform init
echo "------------------------ Running: terraform init ------------------------"
terraform init && export INIT_STATUS="Success" || export INIT_STATUS="Failure"
echo "init status $INIT_STATUS"

export STATE_UNLOCK_ONLY=$(get_env "STATE_UNLOCK_ONLY")
if [[ ${STATE_UNLOCK_ONLY} -eq 1 ]]; then
    echo "Running state unlock only and exiting..."
    terraform force-unlock -force sys-wcp-genctl-team-1pl-tf-na-afi-terraformbackend-local/tf-afi-${workspace_name}
    exit 0
fi

echo "------------------------ Running: terraform output ------------------------"
terraform output

echo "------------------------ Running: terraform format and validate ------------------------"
terraform fmt -recursive -check -diff && export FMT_STATUS="Success" || export FMT_STATUS="Failure"
terraform validate -no-color && export VLDT_STATUS="Success" || export VLDT_STATUS="Failure"
echo "format status $FMT_STATUS, validate status $VLDT_STATUS"

echo "------------------------ Running: terraform plan ------------------------"
terraform plan -parallelism=3 -no-color -input=false -out ${PATH_TO_WORKSPACE}/plantf | tee ${PATH_TO_WORKSPACE}/plan_show.txt  && export PLAN_STATUS="Success" || export PLAN_STATUS="Failure"
echo "plan status $PLAN_STATUS"

set -e

# generate md5 from plan file
export MD5SUM=$(terraform show -no-color ${PATH_TO_WORKSPACE}/plantf | md5sum | cut -f 1 -d ' ')
echo "MD5 generated is: $MD5SUM"

# extract the plan summary line (e.g. "Plan: 28 to add, 0 to change, 0 to destroy.")
export PLAN_SUMMARY=$(grep -E '^Plan:' ${PATH_TO_WORKSPACE}/plan_show.txt || echo "Plan: N/A")
echo "Plan summary: $PLAN_SUMMARY"

echo "This is a PR pipeline, sending plan report"
python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/requirements.txt
if [[ -n "${PR_NUMBER:-}" ]]; then
  echo python3 ${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/add_comment.py -pn $PR_NUMBER
  python3 ${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/add_comment.py -pn $PR_NUMBER
else
  echo "PR_NUMBER is empty (likely issue-triggered run); skipping PR comment step"
fi

# Send Slack notification — verdict reflects plan success/failure
if [[ "${PLAN_STATUS}" == "Success" ]]; then
    _PLAN_VERDICT="SUCCESS"
    _PLAN_SUMMARY_LABEL="Plan: SUCCESS | ${PLAN_SUMMARY}"
else
    _PLAN_VERDICT="FAILURE"
    _PLAN_SUMMARY_LABEL="Plan: FAILURE | ${PLAN_SUMMARY}"
fi
bash "${PATH_TO_GENCTL_CI}/onepipeline/utils/notify_terraform_review.sh" \
    --webhook-url    "${SLACK_WEBHOOK_URL:-}" \
    --channel        "${SLACK_CHANNEL:-}" \
    --verdict        "${_PLAN_VERDICT}" \
    --pr-url         "https://$(get_env GITHUB_API_URL | sed 's|https://||;s|/api/v3||')/${WORKSPACE_ORG}/${WORKSPACE_REPO}/pull/${PR_NUMBER}" \
    --pipeline-url   "${PIPELINE_RUN_URL:-}" \
    --tag-group      "${SLACK_TAG_GROUP:-}" \
    --workspace      "${workspace_name}" \
    --mode           "toolchain" \
    --pipeline-type  "PR" \
    --repo           "${WORKSPACE_REPO:-}" \
    --plan-summary   "${_PLAN_SUMMARY_LABEL}" || true

unset artifactory_token
rm -f ${PATH_TO_WORKSPACE}/plantf
rm -f ~/.terraform.d/credentials.tfrc.json

# cleanup
if [[ $PLAN_STATUS = "Failure" || $VLDT_STATUS = "Failure" || $INIT_STATUS = "Failure" || $FMT_STATUS = "Failure" ]]; then
  echo "Preliminary checks failed, exiting..."

  exit 1
fi

