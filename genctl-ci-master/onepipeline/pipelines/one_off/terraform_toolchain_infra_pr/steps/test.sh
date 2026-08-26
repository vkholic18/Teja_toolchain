#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
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
# source required properties
source ${PATH_TO_PIPELINE}/environment/vars.sh
source ${PATH_TO_PIPELINE}/environment/secrets.sh
source ${PATH_TO_PIPELINE}/environment/aliases.sh

cd ${PATH_TO_WORKSPACE}

set +e
export INIT_STATUS="NA"
export PLAN_STATUS="NA"
export MD5SUM="NA"

echo "------------------------ Running: terraform format and validate ------------------------"
terraform fmt -recursive -check -diff && export FMT_STATUS="Success" || export FMT_STATUS="Failure"
terraform validate -no-color && export VLDT_STATUS="Success" || export VLDT_STATUS="Failure"
echo "format status $FMT_STATUS, validate status $VLDT_STATUS"

set -e

export PLAN_SUMMARY="N/A"
echo "Plan summary: $PLAN_SUMMARY"

echo "This is a PR pipeline, sending plan report"
python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/requirements.txt
echo python3 ${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/add_comment.py -pn $PR_NUMBER
python3 ${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/add_comment.py -pn $PR_NUMBER

# cleanup
if [[ $VLDT_STATUS = "Failure" || $FMT_STATUS = "Failure" ]]; then
  echo "Preliminary checks failed, exiting..."

  exit 1
fi
