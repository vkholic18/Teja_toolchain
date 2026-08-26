#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# This script will use the compiler script inside platform-inventory/hack/ci
# and will generate k8s configmaps using the information located in region/undercloud files
#
# =============================================================================================
set -eu
install_pre_req() {
    # get kustomize
    set +x
    curl --retry 5 -s -H "Authorization: Bearer ${CC_ARTIF_ACCESS_TOKEN}" \
        ${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_GENERIC_REPO_PATH}/third-party/kustomize/kustomize \
        -o kustomize
    chmod +x kustomize && mv kustomize /usr/local/bin
    # get yq4
    rm -f /usr/local/bin/yq
    wget --header="Authorization: Bearer ${CC_ARTIF_ACCESS_TOKEN}" \
        ${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_GENERIC_REPO_PATH}/third-party/yq/yq_linux_amd64 \
        -qO /usr/bin/yq && chmod +x /usr/bin/yq
}

if [ "$#" -ne 3 ]; then
    echo "ERROR: ${FUNCNAME[0]} requires 3 arguments but got $#. Please pass in the correct arguments."
    exit 1
else
    ROOT_DIR=$1
    WORKSPACE_DIR=$2
    OUTOUT_DIR=$3
fi

# download pre-req - install yq and kustomize
install_pre_req
# allowing this to be a default value in case this is for PR pipeline dry-run evaluation
TAG="0.0.0"
if [[ $RELEASE == true ]]; then
    echo "This is a release pipeline, extracting undercloud source files from tarfile"
    SOURCE_RELEASE_FOLDER=/tmp/$WORKSPACE_DIR
    pushd gh-release
    TAG=$(cat tag)
    mkdir -p $SOURCE_RELEASE_FOLDER && tar xzf source.tar.gz -C $SOURCE_RELEASE_FOLDER --strip-components=1
    popd
    rm -rf $WORKSPACE_DIR/region/undercloud/
    cp -r $SOURCE_RELEASE_FOLDER/region/undercloud $WORKSPACE_DIR/region/undercloud
fi

FILES=$(ls $WORKSPACE_DIR/region/undercloud/*undercloud.yml)
pushd $WORKSPACE_DIR/hack/ci
mkdir -p $OUTOUT_DIR
echo "Using tag: $TAG"
for file in $FILES; do
    file_name=$(basename $file)
    ./config_map_transform.sh $ROOT_DIR/$file $TAG > $ROOT_DIR/$OUTOUT_DIR/$file_name
done
