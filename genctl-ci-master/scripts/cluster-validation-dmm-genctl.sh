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

# Source lock utils
source ${PATH_TO_GENCTL_CI}/tools/lock_and_queue_utils/lock.sh

# Configuration required for working with the git remote (Needed for acquire/release lock)
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

# Source the validate_razee_cluster.sh
source $PATH_TO_GENCTL_CI/scripts/ssh_utils.sh
source $PATH_TO_GENCTL_CI/scripts/deployer_utils.sh
# eg, export MZONE_NAME=mzone7301
export MZONE_NAME=$(yq -r '.dmm_deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml | cut -d ',' -f2)


if [[ "${USE_QZ2_WORKER}" == true ]]; then
    echo "Use QZ2 tekton workers for validations"

    if [[ "$PIPELINE_TYPE" == *"pr"* ]]; then

        REGIONDIGIT=${MZONE_NAME#*[[:digit:]]}  # Remove everything up to and including first digit
        REGIONDIGIT=${REGIONDIGIT:0:1}          # Take only the first character (2nd digit)
        
        [ "${REGIONDIGIT}" == "1" ] && REGIONDIGIT="0"

        echo "Extracted region digit: ${REGIONDIGIT} from mzone: ${MZONE_NAME}"

        export WORKER_ID="qz2-tekton-worker-trigger-dal1${REGIONDIGIT}"

        echo "Selected worker: ${WORKER_ID}"

        #temp fix until the issue is resolved
        export WORKSPACE=/workspace/app

        ${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_v11_brt.sh "qz2-cluster-validations" ${WORKER_ID} "true" "onepipeline/pipelines/templatized/release_bundles/pr_with_rias_smoke_v11/.pipeline-config-subpipeline-brt-deploy-dal.yaml" ${MZONE_NAME}

    else
        echo "Genctl validations will be executed in a qz2 worker pipeline"
    fi

else

    set +x
    # Setup ssh to deployer
    if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
        setup_ssh_to_deployer_one_pipeline ${MZONE_NAME} ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}"
    else
        setup_ssh_to_deployer ${MZONE_NAME} ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}"
    fi

    set -x
    source ${PATH_TO_GENCTL_CI}/scripts/validate_razee_cluster_utils.sh

    source $PATH_TO_GENCTL_CI/scripts/retry.sh

    export MZONE_DIR=/home/${BASTION_USERNAME}/${MZONE_NAME}
    # Execute cluster MTPs readiness check

    set +x
    retry validate_razee_cluster_genctl ${MZONE_NAME} "${PATH_TO_GENCTL_CI}" ${BASTION_USERNAME} \
    "${DAL_VAULT_KEY}" "${PATH_TO_PLATFORM_INVENTORY_REPO}" \
    ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN}      \
    ${IMG_TO_RUN_PATH} ${IMG_TO_RUN_TAG}
    set -x

    # Execute cluster pods readiness check
    set +x
    retry validate_pods_cluster_readiness_goku "${PATH_TO_MDS_REPO}" "genctl" "${PATH_TO_GENCTL_CI}" "${MZONE_DIR}/${MZONE_NAME}.conf" ${MZONE_DIR} \
    "${DAL_VAULT_KEY}" "$PATH_TO_PLATFORM_INVENTORY_REPO" \
    ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN}
    set -x

fi
