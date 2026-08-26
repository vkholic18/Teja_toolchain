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

# Set the SSH - needed for core module repo clone
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

# setup artifactory backend creds
${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/setup_terraform.sh

raise_empty_prs_for_team_prod_branches() {
  local modified_ci_file="shared_ci_template_vars.tf"
  local modified_cd_file="shared_cd_template_vars.tf"
  local changed_files current_branch timestamp target_branch dummy_branch pr_title pr_body source_branch pr_url
  local target_branches=()
  local raised_prs=()
  local skipped_prs=()
  local utils_dir pr_summary review_body changed_templates

  changed_files=$(git diff-tree --no-commit-id --name-only -r HEAD)
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  utils_dir="${PATH_TO_GENCTL_CI}/onepipeline/utils"

  if grep -Eq "(^|/)${modified_ci_file}$" <<< "${changed_files}"; then
    changed_templates+="- ${modified_ci_file}"$'\n'
    for target_branch in ${UUC_CI_TEAM_PROD_BRANCHES}; do
      target_branches+=("${target_branch}")
    done
  fi

  if grep -Eq "(^|/)${modified_cd_file}$" <<< "${changed_files}"; then
    changed_templates+="- ${modified_cd_file}"$'\n'
    for target_branch in ${UUC_CD_TEAM_PROD_BRANCHES}; do
      target_branches+=("${target_branch}")
    done
  fi

  if [[ ${#target_branches[@]} -eq 0 ]]; then
    echo "No shared template file changes detected; skipping empty PR creation."
    return 0
  fi

  timestamp=$(date +%Y%m%d%H%M%S)

  gh auth login --hostname github.ibm.com --with-token <<< "${GH_TOKEN}"
  git fetch origin

  local total_branches=${#target_branches[@]}
  local branch_index=0

  for target_branch in "${target_branches[@]}"; do
    branch_index=$(( branch_index + 1 ))

    if [[ "${target_branch}" == "${current_branch}" ]]; then
      echo "Skipping current branch ${target_branch}."
      skipped_prs+=("- ${target_branch}: skipped because it is the current branch")
      continue
    fi

    if ! git ls-remote --exit-code --heads origin "${target_branch}" >/dev/null 2>&1; then
      echo "Branch ${target_branch} does not exist on origin; skipping."
      skipped_prs+=("- ${target_branch}: skipped because the branch does not exist on origin")
      continue
    fi

    source_branch="${target_branch}"
    dummy_branch="${current_branch}-${timestamp}-for-${target_branch}"
    pr_title="chore: CION-0000: trigger ${target_branch} from ${current_branch}"
    pr_body="Created automatically by VPC CI automation after shared template updates from ${current_branch}."

    git checkout -b "${dummy_branch}" "origin/${source_branch}"
    git commit --allow-empty -m "chore: trigger ${target_branch} from ${current_branch}"
    git push origin "${dummy_branch}"

    pr_url=$(gh pr create \
      --base "${target_branch}" \
      --head "${dummy_branch}" \
      --title "${pr_title}" \
      --body "${pr_body}")

    raised_prs+=("${target_branch}: ${pr_url}")

    git checkout "${current_branch}"

    # Wait 8 minutes between PR creations to avoid race conditions on downstream pipelines
    if (( branch_index < total_branches )); then
      echo "Sleeping 8 minutes before next PR creation (${branch_index}/${total_branches} done)..."
      sleep 480
    fi
  done

  if [[ ${#raised_prs[@]} -eq 0 ]]; then
    return 0
  fi

  pr_summary="Follow-up pull requests were created for team production branches after shared template updates."
  review_body=$'FINDINGS\n'
  review_body+=$'Change propagated from:\n'
  review_body+=$(printf '%s' "${changed_templates}")
  review_body+=$'\n\n'
  review_body+=$'RAISED PRS\n'
  for raised_pr in "${raised_prs[@]}"; do
    review_body+="${raised_pr}"$'\n'
  done
  review_body+=$'_END_OF_RAISED_PRS_\n'
  review_body+=$'\n'

  if [[ ${#skipped_prs[@]} -gt 0 ]]; then
    review_body+=$'\n'
    review_body+=$'SKIPPED BRANCHES\n'
    review_body+=$(printf '%s\n' "${skipped_prs[@]}")
    review_body+=$'\n'
  fi

  bash "${utils_dir}/notify_terraform_review.sh" \
    --webhook-url "${SLACK_WEBHOOK_URL:-}" \
    --channel "${SLACK_CHANNEL:-}" \
    --verdict "SUCCESS" \
    --notification-kind "follow_up_prs" \
    --pipeline-url "${PIPELINE_RUN_URL:-}" \
    --workspace "${workspace_name:-}" \
    --mode "infrastructure" \
    --pipeline-type "Merge" \
    --repo "${WORKSPACE_REPO:-}" \
    --plan-summary "${pr_summary}" \
    --review-body "${review_body}" || true
}

raise_empty_prs_for_team_prod_branches
