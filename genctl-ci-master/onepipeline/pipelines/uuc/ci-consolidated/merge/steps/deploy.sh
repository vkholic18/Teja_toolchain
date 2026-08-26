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

# Set the pipeline template type
export PIPELINE_TEMPLATE_TYPE="uuc-ci"

PIPELINE_TYPE="merge"

REPOS_TO_CLONE="
CI_CD_UTILS
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

# Set the SSH
eval "$(ssh-agent -s)" # Check if needed here
ssh-add - <<< "${GIT_PRIVATE_KEY}" # Check if needed here

# Set the flag that exits if the task failed
export EXIT_ON_TASK_FAILURE="true"

# Set the flag that indicates if set GHE statuses when running task
export SET_GHE_STATUSES="false"

DEPLOY_ENV=$(yq -r '(.deployment.env_code // .deployment.dev_cluster) | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)

echo "DEPLOY_ENV is ${DEPLOY_ENV}"

# Set WORKER_ID based on DEPLOY_ENV (substring match on datacenter name)
if [[ "${DEPLOY_ENV}" == *"dal14"* ]]; then
    export WORKER_ID="qz2-tekton-worker-trigger-dal14"
elif [[ "${DEPLOY_ENV}" == *"dal13"* ]]; then
    export WORKER_ID="qz2-tekton-worker-trigger-dal13"
elif [[ "${DEPLOY_ENV}" == *"dal12"* ]]; then
    export WORKER_ID="qz2-tekton-worker-trigger-dal12"
elif [[ "${DEPLOY_ENV}" == *"dal10"* ]]; then
    export WORKER_ID="qz2-tekton-worker-trigger-dal10"
elif [[ "${DEPLOY_ENV}" == *"eu-gb-dev01-cloud-zone1-undercloud"* ]]; then
    export WORKER_ID="cloud-tekton-worker-trigger-otc1"
elif [[ "${DEPLOY_ENV}" == *"eu-gb-dev02-cloud-zone1-undercloud-otc2"* ]]; then
    export WORKER_ID="cloud-tekton-worker-trigger-otc2"
elif [[ -z "${DEPLOY_ENV}" ]]; then
    export WORKER_ID="taas-worker-trigger"
    echo "DEPLOY_ENV is empty, setting WORKER_ID to ${WORKER_ID}"
else
    echo "DEPLOY_ENV is ${DEPLOY_ENV}, WORKER_ID not set"
fi

# Execute deployment based on WORKER_ID
if [[ "${WORKER_ID}" != "taas-worker-trigger" ]]; then
    ${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_v11.sh "deploy-subpipeline" "${WORKER_ID}" "true" "onepipeline/pipelines/uuc/ci-consolidated/merge/.pipeline-config-subpipeline.yaml"
else
    if [[ -f "${PATH_TO_WORKSPACE_REPO}/hack/cd/deploy.sh" ]]; then
        run_task ${SET_GHE_STATUSES} ${CHECKS_PREFIX} "DEPLOY" ${EXIT_ON_TASK_FAILURE} \
        ${PATH_TO_WORKSPACE_REPO}/hack/cd/deploy.sh
    else
        echo "File ${PATH_TO_WORKSPACE_REPO}/hack/cd/deploy.sh not found. Skipping deploy task."
    fi
fi
