#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2020
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, PATH_TO_WORKSPACE_REPO
#COMPONENT: Name of the component (e.g. regional-storage)
#COS_UPLOAD_CONTENT_ROOT (e.g. hack/deploy/razee/)
#COS_UPLOAD_FILES_FILTER: regex filter to search and upload files match the pattern. e.g "\.json$" only *.json files will be uploaded
#COS_SERVICE_CREDENTIALS: (e.g. vault-ibm-cos-creds)
#COS_BUCKET_LIST (loaded from pipeline-params.yaml as cos-bucket-list eu/deployment-artifacts-eu-geo us/deployment-artifacts-us-geo us-south/development-workspace-artifacts)
#COS_ENDPOINT_TEMPLATE (loaded from pipeline-params.yaml as cos-endpoint-template: https://s3.REGION.cloud-object-storage.appdomain.cloud/)
#GIT_PRIVATE_KEY: ((ghe-private-key))

# The following variables are optional
# PATH_TO_GH_RELEASE --> If not then it will be considered as directory not exists
# UPLOAD_TO_COS_PYTHON_ISSUE_WORKAROUND

UPLOAD_TO_COS_PYTHON_ISSUE_WORKAROUND=${UPLOAD_TO_COS_PYTHON_ISSUE_WORKAROUND:"false"}

set -ex

function upload_to_cos() {
  if [ "$#" -ne 4 ]; then
    echo "ERROR: ${FUNCNAME[0]} requires 4 arguments but got $#. Please pass in the correct arguments."
    exit 1
  fi

  bucket_name=$1
  base_dir_file=$2
  destination=$3
  endpoint_url=$4

  echo "Uploading to COS"
  echo "Upload info : Bucket name=\"${bucket_name}\" Base directory name=\"${base_dir_file}\" Destination=\"${destination}\" Endpoint URL=\"${endpoint_url}\""
  if [[ -z ${COS_UPLOAD_FILES_FILTER} ]]; then
    retry python3 ${PATH_TO_GENCTL_CI}/scripts/upload_to_cos.py ${bucket_name} ${base_dir_file} ${destination} --cos-endpoint-url ${endpoint_url}
  else
    retry python3 ${PATH_TO_GENCTL_CI}/scripts/upload_to_cos.py ${bucket_name} ${base_dir_file} ${destination} --cos-upload-filter ${COS_UPLOAD_FILES_FILTER} --cos-endpoint-url ${endpoint_url}
  fi
}

source ${PATH_TO_GENCTL_CI}/scripts/retry.sh
# Configure ssh agent for git - used to do a git fetch on tags to get the most updated tags
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
mkdir -p ~/.ssh
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts

if [[ "${UPLOAD_TO_COS_PYTHON_ISSUE_WORKAROUND}" == "true" ]]
then
  retry pip3 install -r ${PATH_TO_GENCTL_CI}/scripts/git_meta_label_injector/requirements.txt
else
  retry python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/git_meta_label_injector/requirements.txt
fi

python3 ${PATH_TO_GENCTL_CI}/scripts/git_meta_label_injector/git_meta_label_injector.py

export build_root="${PWD}"

if [[ -d ${PATH_TO_GH_RELEASE} ]]; then
  pushd ${PATH_TO_GH_RELEASE}
  export GIT_SHA=$(cat commit_sha)
  echo "GIT_SHA=${GIT_SHA}"
  git_tag=$(cat tag)
  echo "git_tag=${git_tag}"
  popd
else
  pushd ${PATH_TO_WORKSPACE_REPO}
  #explicitly fetch tags
  git fetch --tags
  [[ -f .git/resource/head_sha ]] && export GIT_SHA=$(cat .git/resource/head_sha) || export GIT_SHA=$(git rev-parse --verify HEAD)
  echo "GIT_SHA=${GIT_SHA}"
  git_tag=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true
  if [ -z "${git_tag}" ]; then
      echo "Could not find tag name. Retry to get tag..."
      sleep 2
      git_tag=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true
      if [ -z "${git_tag}" ]; then
          echo "Could not find tag name after retry. Exiting ..."
          # exit 1 Some older hotfix pipelines do not have tags yet, so just warn for now.
      fi
  fi
  echo "git_tag=${git_tag}"
  popd
fi

versions="${GIT_SHA} ${git_tag}"

if [ -d "${PATH_TO_WORKSPACE_REPO}/${COS_UPLOAD_CONTENT_ROOT}" ]; then
  echo debug 51
  retry python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/upload_cos_requirements.txt
  # Check if COS bucket list was defined - allows to upload to multiple buckets
  if [[ ! -z ${COS_BUCKET_LIST} ]]; then
    echo "Using provided COS bucket list"
    for bucket in ${COS_BUCKET_LIST[@]}; do
      bucket_region=$(echo $bucket | awk -F/ '{print $1}')
      bucket_name=$(echo $bucket | awk -F/ '{print $2}')
      endpoint_url=$(echo $COS_ENDPOINT_TEMPLATE | sed "s/REGION/${bucket_region}/")
      for version in $versions; do
        upload_to_cos ${bucket_name} ${PATH_TO_WORKSPACE_REPO}/${COS_UPLOAD_CONTENT_ROOT} ${COMPONENT}/${version} ${endpoint_url}
      done
    done
  else
    # If no multiple buckets were defined, upload to cos with default params
    echo "COS bucket list is not defined"
  fi
else
  echo "Warning: COS files directory does not exist."
fi
