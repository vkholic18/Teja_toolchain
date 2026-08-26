#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================

# The following environment variables need to be set before executing the script:

#Required
# VERSION_FILE
# GIT_PRIVATE_KEY
# VAULT_GIT_CONFIG_USER_EMAIL
# VAULT_GIT_CONFIG_USERNAME
# COMPONENT_FOR_VETTED_VERSION

set -exu

# By default, we do NOT want to skip vetted versions
# Repos that need to skip it (Ex: some kube release bundles) should have an override in pipeline-overrides with true value
SKIP_VETTED_VERSION_UPDATE=${SKIP_VETTED_VERSION_UPDATE:-"false"} 

# Check if the apdate vetted version skip flag defined in the overrides, if yes exit with 0
if [[ "${SKIP_VETTED_VERSION_UPDATE}" == "true" ]]; then
    echo "Skipping to update vetted version"
    exit 0
fi

# Check if the vetted version file value is set, if not exit with 0
if [ -z "${VERSION_FILE}" ]; then
   echo "Empty vetted versions file. Exiting ..."
   exit 0
fi

# Setup for interaction with git remote
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

if [ -d ${PATH_TO_RELEASE_ENVIRONMENT} ]; then
    echo "Using tag in release-environment from a release bundle build"
    IMAGE_TAG=$(cat ${PATH_TO_RELEASE_ENVIRONMENT}/build_tag)
fi
echo Updating: ${COMPONENT_FOR_VETTED_VERSION} with version: ${IMAGE_TAG}

pushd ${PATH_TO_VETTED_VERSIONS_REPO}
git fetch origin ${GENCTL_VETTED_VERSIONS_BRANCH_NAME}
git checkout ${GENCTL_VETTED_VERSIONS_BRANCH_NAME}
git reset --hard origin/${GENCTL_VETTED_VERSIONS_BRANCH_NAME}

# update version file
${PATH_TO_GENCTL_CI}/scripts/update_vetted_version.py ${PATH_TO_VETTED_VERSIONS_REPO}/${VERSION_FILE} ${COMPONENT_FOR_VETTED_VERSION} ${IMAGE_TAG}

# moving into workspace/app/vetted-versions directory 

git add ${VERSION_FILE}
git commit -m "Update vetted version for ${COMPONENT_FOR_VETTED_VERSION}"

# Introduces retry handling for push operations to prevent failures due to race conditions when multiple pipelines push to the same branch simultaneously. 
# This allows the pipeline to retry up to five times instead of failing immediately. No need of rerunning the pipeline CI team should debug the issue.
for i in {1..5}
do
  if git push origin; then
    echo "git push succeeded"
    break
  else
    echo "git push failed. Retrying... (attempt $i/5)"
    git pull --rebase origin --verbose
    # Adding incremental sleep to allow parallel pipelines time to finish their merge, for 2.5 mins. 
    sleep $((i * 10)) # sleep for 10, 20, 30, 40, 50 seconds
  fi
done

popd

echo Updating: ${COMPONENT_FOR_VETTED_VERSION} with version: ${IMAGE_TAG} for dev-regions

# update dev-regions version file
${PATH_TO_GENCTL_CI}/scripts/update_vetted_versions_for_dev_regions.py ${PATH_TO_DEV_REGIONS_REPO}/${DEV_REGIONS_VETTED_VERSIONS_FILE} ${COMPONENT_FOR_VETTED_VERSION} ${IMAGE_TAG}
pushd ${PATH_TO_DEV_REGIONS_REPO}

if [ $(git ls-files -m | wc -l) -eq 0 ]; then
    echo "No need to update remote repository."
    exit 0
else
    echo "Begin to update remote repository."
fi

git add ${DEV_REGIONS_VETTED_VERSIONS_FILE}
git commit -m "Update dev-regions vetted version for ${COMPONENT_FOR_VETTED_VERSION} with ${IMAGE_TAG}"

# Since we have -e flag at the top, we need to put set +e in order to not exit inmediately when the git push fails
set +e

for i in {1..5}
do
  git pull --rebase origin
  if git push origin; then
    echo "git push succeeded"
    exit 0
  else
    echo "git push failed. Trying again"
  fi
done
popd
