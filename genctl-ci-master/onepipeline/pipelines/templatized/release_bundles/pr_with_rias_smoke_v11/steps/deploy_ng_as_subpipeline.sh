#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Get the parent pipeline info to pass it to the sub-pipeline
get_parent_pipeline_info

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="release_bundles"

INITIAL_PIPELINE_TYPE="pr"
get_pipeline_type "${PR_BASEBRANCH}" "${INITIAL_PIPELINE_TYPE}" "${REPO_MAIN_BRANCH}"

# Define the repositories to be cloned
REPOS_TO_CLONE="
PLATFORM_INVENTORY
GENCTL_VETTED_VERSIONS
MICRO_DEPLOY_SERVER
GENESIS_DEPLOY_ARTIFACTS
RESOURCELOCK
GENCTL_RELEASE
RIAS_RELEASE
RIAS_ETCD_RELEASE
PATH_TO_VETTED_VERSIONS_REPO
RIAS_GLOBALS
INTEGRATION_TESTING
DEV_REGIONS
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

# To have same effect that in concourse of in this template not having SKIP_CHECK_PR_TITLE
export SKIP_CHECK_PR_TITLE=""

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

# Explicitly set variables of paths to used repos (This could be done also with a for loop and using eval but we prefer this explicit method)
export PATH_TO_PLATFORM_INVENTORY_REPO="${WORKSPACE}/${PLATFORM_INVENTORY_REPO_NAME}"
export PATH_TO_VETTED_VERSIONS_REPO="${WORKSPACE}/${GENCTL_VETTED_VERSIONS_REPO_NAME}"
export PATH_TO_VV_UPDATED="" # Not supported in OnePipeline yet
export PATH_TO_MDS_REPO="${WORKSPACE}/${MICRO_DEPLOY_SERVER_REPO_NAME}"
export PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO="${WORKSPACE}/${GENESIS_DEPLOY_ARTIFACTS_REPO_NAME}"
export PATH_TO_RESOURCELOCK_REPO="${WORKSPACE}/${RESOURCELOCK_REPO_NAME}"
export PATH_TO_GENCTL_RELEASE_REPO="${WORKSPACE}/${GENCTL_RELEASE_REPO_NAME}"
export PATH_TO_RIAS_RELEASE_REPO="${WORKSPACE}/${RIAS_RELEASE_REPO_NAME}"
export PATH_TO_RIAS_ETCD_RELEASE_REPO="${WORKSPACE}/${RIAS_ETCD_RELEASE_REPO_NAME}"
export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_INTEGRATION_TESTING_REPO="${WORKSPACE}/${INTEGRATION_TESTING_REPO_NAME}"
export PATH_TO_DEV_REGIONS_REPO=${WORKSPACE}/${DEV_REGIONS_REPO_NAME}

# Set the SSH
eval "$(ssh-agent -s)" # Check if needed here
ssh-add - <<< "${GIT_PRIVATE_KEY}" # Check if needed here

# Note: Here we use a mix of jobs and tasks, therefore we configure both flags

# Set the flag that indicates if exit when a job fails
export EXIT_ON_JOB_FAILURE="true"

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="true"

if [[ -z "${COMPONENT}" ]]
then
    echo "Component is not defined"
    exit 1
else
    echo "Component is: ${COMPONENT}"

    if [[ "${APPLY_DMM_DEPLOY_PROCESS}" == true ]]
    then
        echo "Using new deploy dal replacement process and exporting necessary env vars" 

        if [[ -f ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml ]]; then
            export MZONE_NAME_FOR_HIGH_LEVEL_RELEASE_BUNDLES=$(yq -r '.dmm_deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml | cut -d ',' -f1)
            export CLAIM_MZONE_RESULT=$(yq -r '.dmm_deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml | cut -d ',' -f2)
            export BRT_ENVIRONMENT_NAME=$(yq -r '.dmm_deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml | cut -d ',' -f1)
            if [[ ! -z "${MZONE_NAME_FOR_HIGH_LEVEL_RELEASE_BUNDLES}" ]] && [[ ! -z "${BRT_ENVIRONMENT_NAME}" ]]
            then    
                echo "MZONE_NAME_FOR_HIGH_LEVEL_RELEASE_BUNDLES"
                ENDPOINT=$(echo ${PIPELINE_RUN_URL##*ibm:} | cut -d ':' -f 2)
                export LOCK_CLAIMED_MSG="${ORG_AND_REPO} ${PIPELINE_TYPE} run ${BUILD_NUMBER} - 1P_INFO: ${PIPELINE_ID}/${PIPELINE_RUN_ID}/${ENDPOINT}"
                export PATH_TO_BRT="${PATH_TO_RESOURCELOCK_REPO}/${MASCD_BRT_POOL}"       
                run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "${SIMPLE_DEPLOY_DAL_GHE_CHECK_LABEL}" ${EXIT_ON_TASK_FAILURE} \
                ${PATH_TO_GENCTL_CI}/onepipeline/jobs/dmm_deployment_with_smoke_only.sh
            else
                echo "Could not find in pipeline.yaml rule_tag entry under deployment section"
                echo "Will exit with error..."
                exit 1
            fi
        else
            echo "Deploy dal replacement process relies on pipeline.yaml file, which was not found"
            echo "Exit with error..."
            exit 1
        fi
    elif [[ "$LOW_LEVEL_RELEASE_BUNDLE_TYPES" =~ (^|[[:space:]])$COMPONENT($|[[:space:]]) ]]
    then

        echo "Component is a low level release bundle, using traditional deploy dal process"
        run_job "${SIMPLE_DEPLOY_DAL_GHE_CHECK_LABEL}" ${EXIT_ON_JOB_FAILURE} \
        ${PATH_TO_GENCTL_CI}/onepipeline/jobs/simple_deploy_dal_with_smoke.sh

    elif [[ "$HIGH_LEVEL_RELEASE_BUNDLE_TYPES" =~ (^|[[:space:]])$COMPONENT($|[[:space:]]) ]]
    then
        echo "Component is a high level release bundle, using traditional deploy dal process"
        run_job "${SIMPLE_DEPLOY_DAL_GHE_CHECK_LABEL}" ${EXIT_ON_JOB_FAILURE} \
        ${PATH_TO_GENCTL_CI}/onepipeline/jobs/simple_deploy_dal_with_smoke.sh 

    else 
        echo echo "Component is neither low level nor high level release bundle"
        echo "Will exit with error..."
        exit 1
    fi
fi
