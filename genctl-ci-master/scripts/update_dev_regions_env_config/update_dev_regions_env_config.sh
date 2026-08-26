#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script updates the dev-regions environment config file in such a way that only the feature-flag under testing is retained.
# Generates the desired FFSLD post modifying the env file and populates the rqeuired env variables useful for processing later.

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

if [[ -f ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml ]]; then
  FEATURE_FLAG=$(yq -r '.deployment.feature_flag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
  IKS_CLUSTER_NAME=$(yq -r '.deployment.iks_cluster_name | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
  RULE_TAG=$(yq -r '.deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
else
  echo "hack/ci/pipeline.yaml does not exist. Exiting ..."
  exit 1
fi

export DEV_REGIONS_FILE_PATH=${PATH_TO_DEV_REGIONS_REPO}/${IKS_CLUSTER_NAME}/${IKS_CLUSTER_NAME}.yaml

export PATH_TO_RIAS_GLOBALS_REPO="${WORKSPACE}/${RIAS_GLOBALS_REPO_NAME}"
export PATH_TO_GENCTL_GLOBALS_REPO="${WORKSPACE}/${GENCTL_GLOBALS_REPO_NAME}"

if [ -f "${PATH_TO_DEV_REGIONS_REPO}/${IKS_CLUSTER_NAME}/${IKS_CLUSTER_NAME}.yaml" ]; then
    export FILE_TO_PROCESS=${PATH_TO_DEV_REGIONS_REPO}/${IKS_CLUSTER_NAME}/${IKS_CLUSTER_NAME}.yaml
else
    # Search for YAML files containing the IKS_CLUSTER_NAME, recursively
    YAML_FILES=$(grep -lr --include "*.yaml" "$IKS_CLUSTER_NAME" ${PATH_TO_DEV_REGIONS_REPO})
    echo $YAML_FILES
    
    if [ -n "$YAML_FILES" ]; then
    # Iterate through the YAML files and check if it conatins the dev feature_flag versions
    for FILE in $YAML_FILES; do
        if grep -q "$FEATURE_FLAG" "$FILE"; then
            export FILE_TO_PROCESS=$FILE
        fi
    done
    else
        echo "No corresponding configuration file is found"
        exit 1
    fi
fi

echo "File to process : ${FILE_TO_PROCESS}"

for RULE in $(echo ${RULE_TAG} | tr "," "\n")
do
    #update the tag for the ff here:
    if [[ $RULE =~ "mzone" ]]; 
    then 
        MZONE_TO_SEARCH=$RULE
        echo $MZONE_TO_SEARCH
        if grep -q "$MZONE_TO_SEARCH" "$FILE_TO_PROCESS"; then
            echo "File to process for mzone rule tag: ${FILE_TO_PROCESS}"
        else
            MZONE_FILES=$(grep -lr --include "*.yaml" "$MZONE_TO_SEARCH" ${PATH_TO_DEV_REGIONS_REPO})
            echo ${MZONE_FILES}
            for FILE in $MZONE_FILES; do
                NUM_OF_MZONES="$(yq '.infrastructure.providers.ibm_onprem.mzones | length' ${FILE})"
                if [[ $NUM_OF_MZONES -ge 1 ]]; then
                    for ((i=0; i<$NUM_OF_MZONES; i=i+1)); do
                        NAME=$(yq ".infrastructure.providers.ibm_onprem.mzones[$i].name" ${FILE})
                        NAME=${NAME//\"/}
                        if [ $NAME == "$MZONE_TO_SEARCH" ]; then
                            MZONE_GLOBALS=$(yq ".infrastructure.providers.ibm_onprem.mzones[$i].genctl_globals" ${FILE})
                            MZONE_GLOBALS=${MZONE_GLOBALS//\"/}
                            MZONE_UNDERCLOUD=$(yq ".infrastructure.providers.ibm_onprem.mzones[$i].undercloud" ${FILE})
                            MZONE_UNDERCLOUD=${MZONE_UNDERCLOUD//\"/}
                            MZONE_SOURCE=$(yq ".infrastructure.providers.ibm_onprem.mzones[$i].source" ${FILE})
                            MZONE_SOURCE=${MZONE_SOURCE//\"/}
                            yq ".infrastructure.providers.ibm_onprem.mzones += [{name: \"$NAME\", undercloud: \"$MZONE_UNDERCLOUD\", source: \"$MZONE_SOURCE\", genctl_globals: \"$MZONE_GLOBALS\"}]" ${FILE_TO_PROCESS} > temp.json
                        fi
                    done
                fi
            done
            python3 ${PATH_TO_GENCTL_CI}/scripts/convert_json_to_yaml.py -i temp.json -o ${FILE_TO_PROCESS}
        fi
    fi
done

# python3 ${PATH_TO_GENCTL_CI}/scripts/convert_json_to_yaml.py -i temp.json -o ${FILE_TO_PROCESS}

python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/update_dev_regions_env_config/requirements.txt
python3 ${PATH_TO_GENCTL_CI}/scripts/update_dev_regions_env_config/update_dev_regions_env.py "${FEATURE_FLAG}" ${FILE_TO_PROCESS}

python3 -m pip install -q ${PATH_TO_GENCTL_CI}/tools/ci_python_tools
pip3 install -r ${PATH_TO_GENCTL_CI}/scripts/generateFFSLD/requirements.txt

${PATH_TO_GENCTL_CI}/scripts/setup_and_merge_envrionment_files.sh ${FILE_TO_PROCESS} ${PATH_TO_DEV_REGIONS_REPO}/vetted-versions.yaml ${PATH_TO_WORKSPACE_REPO}/master_merged_vv_file.yaml

${PATH_TO_GENCTL_CI}/scripts/generateFFSLD/generateFFSLD.sh ${FILE_TO_PROCESS} 

for RULE in ${RULE_TAG//,/ }; do
    if [[ $RULE != *"mzone"* ]]; then
        RIAS_AND_RIAS_ETCD_RULE_TAG=$RULE
    else
        MZONE_RULE_TAG=$RULE
    fi
done

echo "MZONE_RULE_TAG: ${MZONE_RULE_TAG}"
echo "RIAS_AND_RIAS_ETCD_RULE_TAG ${RIAS_AND_RIAS_ETCD_RULE_TAG}"

if [ -n "$MZONE_RULE_TAG" ]; then
    export GENCTL_FFSLD_FILE_PATH=${PATH_TO_WORKSPACE_REPO}/FFSLD_ARTIFACTS/ffsld/genctl/${MZONE_RULE_TAG}/featureflagsetld.yaml
    export GENCTL_DESIRED_FFSLD=$(yq '.data' ${GENCTL_FFSLD_FILE_PATH} | jq '{data: .}')
fi
if [ -n "$RIAS_AND_RIAS_ETCD_RULE_TAG" ]; then
    export RIAS_FFSLD_FILE_PATH=${PATH_TO_WORKSPACE_REPO}/FFSLD_ARTIFACTS/ffsld/rias/${RIAS_AND_RIAS_ETCD_RULE_TAG}/featureflagsetld.yaml
    export RIAS_ETCD_FFSLD_FILE_PATH=${PATH_TO_WORKSPACE_REPO}/FFSLD_ARTIFACTS/ffsld/rias-etcd/${RIAS_AND_RIAS_ETCD_RULE_TAG}/featureflagsetld.yaml
    export RIAS_DESIRED_FFSLD=$(yq '.data' ${RIAS_FFSLD_FILE_PATH} | jq '{data: .}')
    export RIAS_ETCD_DESIRED_FFSLD=$(yq '.data' ${RIAS_ETCD_FFSLD_FILE_PATH} | jq '{data: .}')
fi
