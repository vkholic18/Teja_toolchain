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

# Source the ibmcloud_utils.sh
source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh

set +x
# Login to ibmcloud using function defined in ibmcloud_utils.sh
ibmcloud_login "None" "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"
set -x

ibmcloud ks cluster config --cluster $CLUSTER_ID

secret_name=$(echo $BASTION_HOSTNAME |awk -F '.' '{print $1}')

kubectl get secrets --all-namespaces | grep "${secret_name}" > output.txt

count=$(cat output.txt | wc -l)

if [ "$count" -gt "0" ]; then
    for (( i=1 ; i<=$count ; i++ ));
    do      
        namespace=$(cat output.txt | sed 's/|/ /' | awk -v var=$i 'NR==var {print $1}')
        kubectl delete secret $secret_name -n $namespace
    done    
fi

ibmcloud ks nlb-dns secret regenerate --cluster $CLUSTER_ID --nlb-subdomain $BASTION_HOSTNAME

kubectl rollout restart deployment teleport -n teleport
