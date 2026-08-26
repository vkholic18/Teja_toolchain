# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description: Generates FFSLD for rias, rias-etcd and genctl
# Args
#     $1 - IKS_CLUSTER_NAME
#

#!/bin/bash


FILE_TO_PROCESS=$1

export FFSLD_ARTIFACTS_PATH=${PATH_TO_WORKSPACE_REPO}/FFSLD_ARTIFACTS
export DEV_REGIONS_ENV_PATH=${FILE_TO_PROCESS}


function generate_rias_and_rias_etcd_ffs() {
    echo "Entering generateRiasAndRiasEtcdFfs......"
    ibm_container_cluster_keys=$(yq ".infrastructure.providers.ibm_cloud.resources.ibm_container_cluster[].vars | keys[]" ${DEV_REGIONS_ENV_PATH})
    ibm_container_cluster_names=$(yq ".infrastructure.providers.ibm_cloud.resources.ibm_container_cluster[].name" ${DEV_REGIONS_ENV_PATH})
    rias_rias_etcd_file_entry=$(yq ".infrastructure.providers.ibm_cloud.resources.ibm_container_cluster[].vars | values[]" ${DEV_REGIONS_ENV_PATH})
    cluster_keys=($ibm_container_cluster_keys)
    cluster_names=($ibm_container_cluster_names)
    files=($rias_rias_etcd_file_entry)
    echo "${cluster_keys[@]}"
    echo "${cluster_names[@]}"
    echo "${files[@]}"

    #for every_cluster in $ibm_container_cluster_keys; do
    for ((i=0; i<${#cluster_keys[@]}; i++)); do
        if [[ ${cluster_keys[$i]} == "\"rias-release\"" ]]; then
            RIAS_FILE_NAME=$(echo ${files[$i]} | awk -F"//" '{print $2}' | awk -F"?" '{print $1}')
            if [[ $RIAS_FILE_NAME != "" ]]; then
                export PATH_TO_JSON_FILE=$PATH_TO_RIAS_GLOBALS_REPO/$RIAS_FILE_NAME
                echo $PATH_TO_JSON_FILE
                export PATH_TO_YAML_J2=${PATH_TO_RIAS_FFSLD}
                echo $PATH_TO_YAML_J2
                FOLDER_NAME="rias"
                python3 ${PATH_TO_DEV_REGIONS_REPO}/scripts/generateFFSLD.py ${PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO}/${PATH_TO_YAML_J2} ${PATH_TO_WORKSPACE_REPO}/master_merged_vv_file.yaml ${PATH_TO_RIAS_GLOBALS_REPO}/${RIAS_FILE_NAME} ${cluster_names[$i]} ${FFSLD_ARTIFACTS_PATH}
            fi
        elif [[ ${cluster_keys[$i]} == "\"rias-etcd-release\"" ]]; then
            RIAS_ETCD_FILE_NAME=$(echo ${files[$i]} | awk -F"//" '{print $2}' | awk -F"/" '{print $3}' | awk -F"?" '{print $1}')
            RIAS_ETCD_FILE_NAME="${RIAS_ETCD_FILE_NAME%.*}.yaml"
            echo $RIAS_ETCD_FILE_NAME
            if [[ $RIAS_ETCD_FILE_NAME != "" ]]; then
                PATH_TO_GLOBALS_YAML_FILE=$(find ${PATH_TO_RIAS_ETCD_GLOBALS_REPO} -name ${RIAS_ETCD_FILE_NAME})
                echo $PATH_TO_GLOBALS_YAML_FILE
                export PATH_TO_YAML_J2=${PATH_TO_RIAS_ETCD_FFSLD}
                echo $PATH_TO_YAML_J2
                FOLDER_NAME="rias-etcd"
                python3 ${PATH_TO_DEV_REGIONS_REPO}/scripts/generateFFSLD.py ${PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO}/${PATH_TO_YAML_J2} ${PATH_TO_WORKSPACE_REPO}/master_merged_vv_file.yaml ${PATH_TO_GLOBALS_YAML_FILE} ${cluster_names[$i]} ${FFSLD_ARTIFACTS_PATH}
            fi
        fi
    done
}

function generate_mzone_ffs() {
    echo "Entering generateMzoneFfs......"
    num_mzone_lines="$(yq '.infrastructure.providers.ibm_onprem.mzones | length' ${DEV_REGIONS_ENV_PATH})"
    echo "$num_mzone_lines"
    if [ -z $num_mzone_lines ]; then
    echo "cannot find any mzones"
    return
    fi
    if [[ $num_mzone_lines -eq 0 ]]; then
    echo "cannot find any mzone lines"
    return
    fi
    for ((i=0; i<$num_mzone_lines; i=i+1)); do
        echo "i=$i"
        name=$(yq ".infrastructure.providers.ibm_onprem.mzones[$i].name" ${DEV_REGIONS_ENV_PATH})
        echo $name
        genctl_globals=$(yq ".infrastructure.providers.ibm_onprem.mzones[$i].genctl_globals" ${DEV_REGIONS_ENV_PATH})
        echo $genctl_globals
        GENCTL_FILE_NAME=$(echo $genctl_globals | awk -F"//" '{print $2}' | awk -F"?" '{print $1}')
        echo $GENCTL_FILE_NAME
        export PATH_TO_JSON_FILE=${PATH_TO_GENCTL_GLOBALS_REPO}/${GENCTL_FILE_NAME}
        export PATH_TO_YAML_J2=${PATH_TO_GENCTL_FFSLD}
        python3 ${PATH_TO_DEV_REGIONS_REPO}/scripts/generateFFSLD.py ${PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO}/${PATH_TO_YAML_J2} ${PATH_TO_WORKSPACE_REPO}/master_merged_vv_file.yaml ${PATH_TO_JSON_FILE} ${name} ${FFSLD_ARTIFACTS_PATH}
    done
}


function generate_zonelets_ffs() {
    echo "Entering generateZoneletsFfs......"
    num_zonelets_lines="$(yq '.infrastructure.providers.ibm_onprem.zonelets | length' ${DEV_REGIONS_ENV_PATH})"
    echo "$num_zonelets_lines"
    if [ -z $num_zonelets_lines ]; then
        echo "cannot find any zonelets, skipping ..."
        return
    fi
    if [[ $num_zonelets_lines -eq 0 ]]; then
        echo "cannot find any zonelets lines"
        return
    fi
    echo "******************"

    for ((i=0; i<$num_zonelets_lines; i=i+1)); do
        echo "i=$i"
        name=$(yq ".infrastructure.providers.ibm_onprem.zonelets[$i].name" ${DEV_REGIONS_ENV_PATH})
        echo $name
        genctl_globals=$(yq ".infrastructure.providers.ibm_onprem.zonelets[$i].genctl_globals" ${DEV_REGIONS_ENV_PATH})
        echo $genctl_globals
        GENCTL_FILE_NAME=$(echo $genctl_globals | awk -F"//" '{print $2}' | awk -F"?" '{print $1}')
        echo $GENCTL_FILE_NAME
        export PATH_TO_JSON_FILE=${PATH_TO_GENCTL_GLOBALS_REPO}/${GENCTL_FILE_NAME}
        export PATH_TO_YAML_J2=${PATH_TO_GENCTL_FFSLD}
        ATTRIBUTE="zonelet"
        python3 ${PATH_TO_DEV_REGIONS_REPO}/scripts/generateFFSLD.py ${PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO}/${PATH_TO_YAML_J2} ${PATH_TO_WORKSPACE_REPO}/master_merged_vv_file.yaml ${PATH_TO_JSON_FILE} ${name} ${FFSLD_ARTIFACTS_PATH} ${ATTRIBUTE}
    done
}

generate_rias_and_rias_etcd_ffs
generate_mzone_ffs
generate_zonelets_ffs
