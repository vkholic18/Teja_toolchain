#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
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

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="razee"

export PIPELINE_TYPE="pr"

REPOS_TO_CLONE="
RESOURCELOCK
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

export PATH_TO_RESOURCELOCK_REPO="${WORKSPACE}/${RESOURCELOCK_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="false"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Here is the logic for trying to release the lock in case is stucked, however we can't perform this logic for repos that run dynamic scan
# The reason is that we won't be able to distinguish between a stucked lock and a lock that is still used by dynamic scan

if [[ "${NEED_TO_RUN_DYNAMIC_SCAN}" == "true" ]]
then
	echo "Repo does dynamic scan; won't do logic for releasing lock in case seems to be stucked..."
else
	# Configuration required for working with the git remote (Needed for acquire/release lock)
	eval "$(ssh-agent -s)"
	ssh-add - <<< "${GIT_PRIVATE_KEY}"
	mkdir -p ~/.ssh
	ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
	git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
	git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

	export FULL_ORIGINAL_ACQUIRE_MESSAGE="Lock ${BRT_ENVIRONMENT_NAME} acquired by ${LOCK_CLAIMED_MSG}"
	export FORCE_RELEASE_COMMIT_MESSAGE="FORCE RELEASE IN FINISH STAGE - ${LOCK_CLAIMED_MSG}"
	
	source ${PATH_TO_GENCTL_CI}/tools/lock_and_queue_utils/lock.sh
	
	if lock_is_still_mine ${PATH_TO_BRT} ${BRT_ENVIRONMENT_NAME} "${FULL_ORIGINAL_ACQUIRE_MESSAGE}"
	then
		echo "Will force release lock ${BRT_ENVIRONMENT_NAME}"
		release_lock ${PATH_TO_BRT} ${BRT_ENVIRONMENT_NAME} "${FORCE_RELEASE_COMMIT_MESSAGE}" 360 10
	fi
fi

# detect the phase of the PR
detect_pr_phase "$PR_URL"

if [[ "$PR_PHASE" == "pre-merge" ]]; then
	### Auto-merge ### (Since is only one task no need for job)
	run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "AUTO_MERGE" ${EXIT_ON_TASK_FAILURE} \
	${PATH_TO_GENCTL_CI}/scripts/merge_pr/merge_pr.sh
elif [[ "$PR_PHASE" == "post-merge" ]]; then
	echo "PR has already been merged, so skipping the auto-merge functionality."	
else
	echo "PR is either closed or UNKNOWN state; auto-merge will not be executed."
	echo "Exiting..."
	exit 1
fi
