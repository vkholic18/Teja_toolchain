#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

#
# This script validates that the PR includes a change to environment.yaml or promotion yaml only.
# If none of those files changed, then exit the pipeline.
#

# Set flags
set -ex

# Overrides for OnePipeline
if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
  # Source one-pipeline utils
  source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh
elif [[ -e ./pipe-data/pr.sh ]]; then
  . pipe-data/pr.sh
  echo "Git Environment:"
  env | grep ^PR_
fi

cd ${PATH_TO_WORKSPACE_REPO}

# Determine which promotion yaml file to use based on branch name
SUBSTR='OPS-PROMOTION-BRANCH'
if [[ "$PR_BRANCH" == *"$SUBSTR"* ]]; then
  export PROMOTION_YAML_FILE_NAME="ops-promotion.yaml"
else
  export PROMOTION_YAML_FILE_NAME="promotion.yaml"
fi

# Diff'ing the two trees, base and current promotion pr
diff_result=$(git diff-tree --no-commit-id --name-only -r $PR_BASESHA $PR_HEADSHA)
if grep -e "environment.yaml" -e "${PROMOTION_YAML_FILE_NAME}" <<< "$diff_result"
then
    echo "Updates to environment.yaml or promotion yaml detected, continuing..."
else
    echo "No changes to either environment.yaml or promotion yaml, exiting pipeline"
    exit 1
fi
