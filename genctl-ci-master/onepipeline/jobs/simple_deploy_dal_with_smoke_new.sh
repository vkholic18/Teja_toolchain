#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
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
