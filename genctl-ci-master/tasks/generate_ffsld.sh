#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2025
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

#this script generate ffsld and pushes it to cos

#get rule_tags from pipeline.yaml
if [[ "${RAZEE_HOTFIX}" == "true" && -f ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml ]]; then
  echo "This is a hotfix pipeline. RULE_TAG should be empty to create variation only but not update the HF variation in the rule"
  RULE_TAG=""
elif [[ -f ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml ]]; then
  RULE_TAG=$(yq -r '.deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
else
  RULE_TAG=""
fi

echo "Rule tag: ${RULE_TAG}"

if [[ -f ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml ]]; then
    FEATURE_FLAG=$(yq -r '.deployment.feature_flag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
    IKS_CLUSTER_NAME=$(yq -r '.deployment.iks_cluster_name | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
 else
    echo "hack/ci/pipeline.yaml does not exist. Exiting ..."
    exit 1
fi

python3 -m pip install -q ${PATH_TO_GENCTL_CI}/tools/ci_python_tools
pip3 install -r ${PATH_TO_GENCTL_CI}/scripts/generateFFSLD/requirements.txt

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
                            echo $MZONE_GLOBALS
                            MZONE_UNDERCLOUD=$(yq ".infrastructure.providers.ibm_onprem.mzones[$i].undercloud" ${FILE})
                            MZONE_UNDERCLOUD=${MZONE_UNDERCLOUD//\"/}
                            echo $MZONE_UNDERCLOUD
                            MZONE_SOURCE=$(yq ".infrastructure.providers.ibm_onprem.mzones[$i].source" ${FILE})
                            MZONE_SOURCE=${MZONE_SOURCE//\"/}
                            echo $MZONE_SOURCE
                            yq ".infrastructure.providers.ibm_onprem.mzones += [{name: \"$NAME\", undercloud: \"$MZONE_UNDERCLOUD\", source: \"$MZONE_SOURCE\", genctl_globals: \"$MZONE_GLOBALS\"}]" ${FILE_TO_PROCESS} > temp.json
                            python3 ${PATH_TO_GENCTL_CI}/scripts/convert_json_to_yaml.py -i temp.json -o ${FILE_TO_PROCESS}
                        fi
                    done
                fi
            done
        fi
    fi
done

#generate master yaml file
${PATH_TO_GENCTL_CI}/scripts/setup_and_merge_envrionment_files.sh ${FILE_TO_PROCESS} ${PATH_TO_DEV_REGIONS_REPO}/vetted-versions.yaml ${PATH_TO_WORKSPACE_REPO}/master_merged_vv_file.yaml

#generate ffsld
${PATH_TO_GENCTL_CI}/scripts/generateFFSLD/generateFFSLD.sh ${FILE_TO_PROCESS}

export FFSLD_ARTIFACTS_PATH=${PATH_TO_WORKSPACE_REPO}/FFSLD_ARTIFACTS
echo "FFSLD_ARTIFACTS_PATH"
echo ${FFSLD_ARTIFACTS_PATH}

#upload to cos
${PATH_TO_GENCTL_CI}/scripts/ffsld_upload_to_cos/ffsld_upload_to_cos.sh ${FFSLD_ARTIFACTS_PATH} 
