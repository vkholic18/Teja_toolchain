#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -o pipefail


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

export PIPELINE_TYPE="merge"
# Define the repositories to be cloned
REPOS_TO_CLONE="
RAZEE_TOOLCHAINS
GLOBALS_TOOLCHAINS
RELEASE_BUNDLES_TOOLCHAINS
SDN_TOOLCHAINS
ARTIFACTS_TOOLCHAINS
ONE_OFF_TOOLCHAINS
PROD_ARTIFACTS_TOOLCHAINS
IAC_TOOLCHAINS
RE_TOOLCHAINS
SIMPLE_TOOLCHAINS
VPC_CI_DEV_TOOLCHAINS
"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Clone required repos
clone_repos_from_env_vars "${IBM_HTTPS_BASE_URL}" "${WORKSPACE}" "${REPOS_TO_CLONE}" 

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

cd ${PATH_TO_WORKSPACE}
MERGE_SHA=$(git rev-parse --short HEAD)
# Set the SSH - needed for core module repo clone
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

declare -a IAC_REPOS=(RAZEE_TOOLCHAINS_REPO_NAME GLOBALS_TOOLCHAINS_REPO_NAME RELEASE_BUNDLES_TOOLCHAINS_REPO_NAME SDN_TOOLCHAINS_REPO_NAME ARTIFACTS_TOOLCHAINS_REPO_NAME ONE_OFF_TOOLCHAINS_REPO_NAME PROD_ARTIFACTS_TOOLCHAINS_REPO_NAME IAC_TOOLCHAINS_REPO_NAME RE_TOOLCHAINS_REPO_NAME SIMPLE_TOOLCHAINS_REPO_NAME VPC_CI_DEV_TOOLCHAINS_REPO_NAME)

for repo in "${IAC_REPOS[@]}"
do
  echo -e "\n *************************************************************************** \n
                \033[0;35m Creating a PR in ${!repo} \033[0m
  \n *************************************************************************** \n"
  pushd "${WORKSPACE}/${!repo}"
  CURRENT_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  BRANCH_TO_CREATE_NAME="${!repo}_${CURRENT_TIMESTAMP}"

  # Pull latest code if any
  git fetch origin
  git pull

  # Create and move to local branch
  git checkout -b "${BRANCH_TO_CREATE_NAME}"

  git commit --allow-empty -m "Adding empty commit to update the changes in ${PIPELINE_REPO_NAME}"

  # Push the changes
  git push origin "${BRANCH_TO_CREATE_NAME}"

  # Login
  gh auth login --hostname github.ibm.com --with-token <<< ${GIT_1PL_CI_PAT}

  # Use gh tool to create PR
  gh pr create --title "Creating PR for the new merge commit in ${PIPELINE_REPO_NAME}" --body "Created automatically by VPC CI automation for the merge commit: ${MERGE_SHA} in ${PIPELINE_REPO_NAME}"

  echo -e "\n\033[1;32m PR created successfully in ${!repo} \033[0m \n"
  popd
done