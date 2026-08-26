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

# Define the repositories to be cloned
REPOS_TO_CLONE="
PLATFORM_INVENTORY
RESOURCELOCK
GENCTL_GLOBALS
RIAS_GLOBALS
DEV_REGIONS
GENESIS_DEPLOY_ARTIFACTS
RIAS_ETCD_GLOBALS
RIAS_ETCD_RELEASE
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

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_PLATFORM_INVENTORY_REPO="${WORKSPACE}/${PLATFORM_INVENTORY_REPO_NAME}"
export PATH_TO_RESOURCELOCK_REPO="${WORKSPACE}/${RESOURCELOCK_REPO_NAME}"
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_RIAS_ETCD_GLOBALS_REPO="${WORKSPACE}/${RIAS_ETCD_GLOBALS_REPO_NAME}"
export PATH_TO_RIAS_ETCD_RELEASE_REPO="${WORKSPACE}/${RIAS_ETCD_RELEASE_REPO_NAME}"
export PATH_TO_GENCTL_GLOBALS_REPO="${WORKSPACE}/${GENCTL_GLOBALS_REPO_NAME}"
export PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO="${WORKSPACE}/${GENESIS_DEPLOY_ARTIFACTS_REPO_NAME}"
export PATH_TO_DEV_REGIONS_REPO="${WORKSPACE}/${DEV_REGIONS_REPO_NAME}"

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Set the SSH
eval "$(ssh-agent -s)" # Check if needed here
ssh-add - <<< "${GIT_PRIVATE_KEY}" # Check if needed here

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

# The save artifacts in PR to master of razee deals only with the first image
export SAVE_ARTIFACTS_ONLY_FIRST_IMAGE_MODE="true"
export SAVE_ARTIFACTS_SKIP_PACKAGES="true"

# Save artifacts is required both for collecting evidence of BRT and for dynamic scan
run_task "false" ${CHECKS_PREFIX} "SAVE_ARTIFACTS_FOR_PR_EVIDENCE" ${EXIT_ON_TASK_FAILURE} \
${PATH_TO_GENCTL_CI}/onepipeline/scripts/save_artifacts_v11.sh

if [[ "${NEED_TO_RUN_DYNAMIC_SCAN}" == "true" ]]
then
    ## Check if we can reuse evidence, if yes, no need to run UT ##
    check-evidence-for-reuse --tool-type "owasp-zap" \
    --evidence-type "com.ibm.dynamic_scan" \
    --asset-type "artifact" \
    --asset-key "app-image"

    if [[ $? -eq 0 ]]
    then
        echo "Will re-use evidence, no need to run Dynamic Scan"
    else        
        # At this point we assume that we have the lock since the BRT run and passed and we are in a workspace that runs dynamic scan
        # Therefore we can safely proceed to run dynamic scan
        ### Run dynamic scan - This runs in a sub-pipeline in TAAS worker ###
        # Important: Note that this runs on a fire and forget mode, it means we trigger the subpipeline but we don't wait for it to finish

        # Fire and forget subpipeline for dynamic scan
        run_task "false" ${CHECKS_PREFIX} "DYNAMIC_SCAN_SUBPIPELINE_TRIGGER" ${EXIT_ON_TASK_FAILURE} \
        ${PATH_TO_GENCTL_CI}/onepipeline/scripts/dynamic_scan_subpipeline_trigger_v11.sh "onepipeline/pipelines/templatized/razee/pr_and_ci_master_v11/.pipeline-config-subpipeline-configurations.yaml"
    fi
fi
