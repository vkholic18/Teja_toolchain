#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

export MZONE_NAME=$(yq -r '.dmm_deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml | cut -d ',' -f2)

REGIONDIGIT=${MZONE_NAME#*[[:digit:]]}  # Remove everything up to and including first digit
REGIONDIGIT=${REGIONDIGIT:0:1}          # Take only the first character (2nd digit)

echo "Extracted region digit: ${REGIONDIGIT} from mzone: ${MZONE_NAME}"

export WORKER_ID="qz2-tekton-worker-trigger-dal1${REGIONDIGIT}"

echo "Selected worker: ${WORKER_ID}"

${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline_v11_brt.sh "qz2-cluster-validations" ${WORKER_ID} "true" "onepipeline/pipelines/templatized/razee/merge_master_with_deploy_dal/.pipeline-config.yaml" ${MZONE_NAME}
