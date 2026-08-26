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

INITIAL_PIPELINE_TYPE="pr"
get_pipeline_type "${PR_BASEBRANCH}" "${INITIAL_PIPELINE_TYPE}" "${REPO_MAIN_BRANCH}"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides ${PATH_TO_GENCTL_CI} \
"${PIPELINE_REPO_NAME}" ${PIPELINE_TYPE}

# Come back
popd

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
# prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"
# echo "${TR_ARTIFACTORY_ACCESS_TOKEN}" > /tmp/.env
# export DOCKER_BUILDKIT=1
# export DOCKERBUILDFLAGS="--build-arg GIT_SHA --build-arg ART_API_KEY --build-arg COCOA_HOST --secret id=_env,src=/tmp/.env"

# for repo in ${PATH_TO_WORKSPACE_REPO}/dependencies/yum_repos/*.repo; do
#     echo $repo
#     echo "username=${TR_ARTIFACTORY_LOGIN}" >> "${repo}"
#     echo "password=${ART_API_KEY}" >> "${repo}"
# done
${COMMONS_PATH}/utils/setup_branch-protection.sh
echo "Running custom CRA script, preparing dockerfile build preliminary setup"

"/opt/commons/compliance-checks/run.sh"
rm -f /tmp/.env
