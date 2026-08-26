#!/usr/bin/env bash
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

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

pushd ${PATH_TO_WORKSPACE_REPO}

#Files changed in calico directory set to false by default
CHANGED="false"

#Print top 2 commits from the master
git log --oneline -2

COMMIT_ID_1=$(git log --oneline -2 | awk 'NR==1 {print $1}')
COMMIT_ID_2=$(git log --oneline -2 | awk 'NR==2 {print $1}')

FILES_CHANGED_IN_CALICO=$(git diff --name-only $COMMIT_ID_1 $COMMIT_ID_2 | grep 'calico/' | wc -l)

if [ "$FILES_CHANGED_IN_CALICO" -gt "0" ]; then
  CHANGED="true"
fi

popd

# Source the ibmcloud_utils.sh
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

set +x
# Login to ibmcloud using function defined in ibmcloud_utils.sh
ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}" "us-south"
set -x

get_iks_cluster_config $CLUSTER_ID

function delete(){
  declare -a arr=("deny-policies" "tekton-worker" "common")
  arr+=("$CLUSTER_REGION")
  for i in "${arr[@]}"; do
    for p in ${PATH_TO_GENCTL_CI}/calico/$i/*.yaml; do
      echo "Deleting $p policy"
      calicoctl delete -f $p --allow-version-mismatch
    done
  done
  for l in ${PATH_TO_GENCTL_CI}/calico/*.yaml; do
    echo "Deleting $l policy"
    calicoctl delete -f $l --allow-version-mismatch
  done
}

function apply(){
  declare -a arr=("common" "tekton-worker")
  arr+=("$CLUSTER_REGION")
  arr+=("deny-policies")
  for l in ${PATH_TO_GENCTL_CI}/calico/*.yaml; do
    echo "Appling $l policy"   
    calicoctl apply -f $l --allow-version-mismatch
  done

  for i in "${arr[@]}"; do
    for p in ${PATH_TO_GENCTL_CI}/calico/$i/*.yaml; do
      echo "Appling $p policy"
      calicoctl apply -f $p --allow-version-mismatch
    done
  done
}

function policies(){
    calicoctl get GNP -o wide --allow-version-mismatch
    echo -e " ***** Namespace Network Policies ***** \n"
    calicoctl get NP -n tekton-pipelines -o wide --allow-version-mismatch
}

if [[ "$CALICO_OPERATION" == "apply" && "$CHANGED" == "true" ]]; then    
    echo -e "List of policies before applying the changes \n"
    policies
    echo -e "\n ************************* Applying the calico policies ************************* \n"
    apply
    echo -e "\n ************************* Successfully applied the calico policies ************************* \n"
    echo -e "List of policies after applying the changes \n"
    policies
fi

if [[ "$CALICO_OPERATION" == "delete" ]]; then
    echo -e "List of policies before deleteing the policies \n"
    policies
    echo -e "\n ************************* Deleting the calico policies ************************* \n"
    delete
    echo -e "\n ************************* Successfully deleted the calico policies ************************* \n"
    echo -e "List of policies after deleting the policies \n"
    policies
fi

if [[ "$CALICO_OPERATION" == "list" ]]; then
    echo -e "List of global network and tekton-pipelines namespace policies \n"
    policies
fi
