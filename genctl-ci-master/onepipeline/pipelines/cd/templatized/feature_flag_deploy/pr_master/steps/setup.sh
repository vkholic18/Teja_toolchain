#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Define type of pipeline (Used to search overrides)
PIPELINE_TYPE="pr"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

# To have same effect that in concourse of in this template not having SKIP_CHECK_PR_TITLE
export SKIP_CHECK_PR_TITLE=""

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

## Check pr title and commits ##
echo "CHECKING PR TITLE"
run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "SCAN_PR_TITLE" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/scripts/check_pr_title/check_pr_title.sh

function exit_if_label_present {
  # Exit if the passed argument label exists on the PR
  export SKIP_LABEL=${1}
  export MESSAGE=${2}

  ${PATH_TO_GENCTL_CI}/scripts/check_pr_has_label/check_pr_has_label.sh "${SKIP_LABEL}"
  result=$?
  echo "result check_pr_has_label: $result"
  if [[ $result -eq 0 ]] ; then
      # Post a comment on the PR
      python3 -m pip install -q -r ${PATH_TO_GENCTL_CI}/scripts/pr_utils/requirements.txt
      python3 ${PATH_TO_GENCTL_CI}/scripts/pr_utils/pr_comment.py -msg "${MESSAGE}"
      echo "${MESSAGE} Exiting now ..."
      exit 1
  elif [[ $result -eq 100 ]] ; then
      echo "failed to get information about the ${SKIP_LABEL} label"
      exit 1
  fi

}

######## RUN PRELIMINARY CHECKS ########
echo
echo "Running Preliminary Checks"
echo
# Exit if PR is draft
if ${PR_DRAFT} ; then echo "ERROR: This is a Draft PR. Push an empty commit when it is ready for review. Exiting." && exit 1 ; fi

# Exit if "promotion", "automation" or "parallel" labels exist on the PR
exit_if_label_present "promotion" "Legacy pipeline update - PR cannot have PROMOTION label. It is set ON only for running promotion tests."
exit_if_label_present "automation" "Legacy pipeline update - PR cannot have AUTOMATION label. It is set ON only for running deployments using Jenkins pipelines."
exit_if_label_present "parallel" "Legacy pipeline update - PR cannot have PARALLEL label. It is set ON only for running parallel deployments using Jenkins pipelines."
