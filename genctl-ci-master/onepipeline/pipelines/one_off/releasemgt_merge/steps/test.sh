# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

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


echo "machine github.ibm.com login ${GITHUB_USERNAME} password ${GITHUB_API_KEY}" > ~/.netrc
go install github.ibm.com/genctl-cicd/changeloggen/cmd/changeloggen@${CHANGELOGGEN_VERSION}
python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/versioning/requirements.txt

python3 ${PATH_TO_GENCTL_CI}/scripts/versioning/update_bundle_changelog.py
