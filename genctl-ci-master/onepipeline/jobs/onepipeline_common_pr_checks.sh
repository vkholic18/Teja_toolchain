#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

export GIT_PRIVATE_KEY=$(get_secret "ghe-private-key")

INITIAL_PIPELINE_TYPE="pr"
get_pipeline_type "${PR_BASEBRANCH}" "${INITIAL_PIPELINE_TYPE}" "${REPO_MAIN_BRANCH}"

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

# Set the SSH
eval "$(ssh-agent -s)" # Check if needed here
ssh-add - <<< "${GIT_PRIVATE_KEY}" # Check if needed here
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts

# Set the flag that indicates if exit when a taks fails
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="false"

## Check if we are in a PR pipeline using pipeline_namespace ##
if [[ "${PIPELINE_NAMESPACE}" != "pr" ]]; then
    echo "Not a PR pipeline (pipeline_namespace=${PIPELINE_NAMESPACE}). Skipping common PR checks."
    exit 0
fi

if [[ "${CANCEL_OLD_PR_PIPELINE_RUNS}" == "true" ]]; then
    ## Fetch PR_NUMBER if not set ##
    if [[ -z "${PR_NUMBER}" ]] && [[ -n "${PR_URL}" ]]; then
        echo "PR_NUMBER not set, extracting from PR_URL..."
        export PR_NUMBER=$(echo "${PR_URL}" | grep -o '[^/]*$')
        echo "Extracted PR_NUMBER: ${PR_NUMBER}"
    fi

    ## Detect PR phase to determine if we should run cancellation ##
    if [[ -n "${PR_URL}" ]]; then
        echo "Detecting PR phase..."
        detect_pr_phase "${PR_URL}"
        
        if [[ "${PR_PHASE}" == "pre-merge" ]]; then
            echo "PR is in pre-merge phase. Proceeding with old pipeline run cancellation..."
            
            ## Cancel old PR pipeline runs to save infrastructure resources ##
            if [[ -n "${PR_NUMBER}" ]]; then
                run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "CANCEL_OLD_PR_PIPELINE_RUNS" false \
                ${PATH_TO_GENCTL_CI}/onepipeline/scripts/cancel_old_pr_pipeline_runs.sh
            else
                echo "No PR_NUMBER found. Skipping old pipeline run cancellation check."
            fi
        else
            echo "PR is in ${PR_PHASE} phase. Skipping old pipeline run cancellation."
        fi
    else
        echo "No PR_URL found. Skipping PR phase detection and cancellation check."
    fi
fi

## Apply branch protection rules if enabled ##
ADD_BRANCH_PROTECTION_RULES="$(get_env add-branch-protection-rules)"
if [ "${ADD_BRANCH_PROTECTION_RULES}" = "1" ]; then
    echo "Branch protection rules enabled. Applying to ${BASE_BRANCH}..."
    run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "APPLY_BRANCH_PROTECTION_RULES" ${EXIT_ON_TASK_FAILURE} \
    ${COMMONS_PATH}/utils/setup_branch-protection.sh
elif [ "${ADD_BRANCH_PROTECTION_RULES}" = "0" ]; then
    echo "Application of branch protection rules disabled"
else
    echo "Invalid value present in env var add-branch-protection-rules, expected 0 or 1, got: ${ADD_BRANCH_PROTECTION_RULES}"
    echo "Skipping branch protection rules application"
fi
