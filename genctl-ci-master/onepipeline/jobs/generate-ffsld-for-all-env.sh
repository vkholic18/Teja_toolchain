#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

python3 -m pip install -q ${PATH_TO_GENCTL_CI}/tools/ci_python_tools
pip3 install -r ${PATH_TO_GENCTL_CI}/scripts/generateFFSLD/requirements.txt

cd "${PATH_TO_WORKSPACE_REPO}"

modified_files=$(git diff --name-only HEAD~1 HEAD)
echo -e "${BGreen}Files modified in this commit are: ............................................................................. ${NC}"
echo -e "${BYellow} ${modified_files} ............................................................................. ${NC}"

function generate_ffsld_for_all_env(){
    export FFSLD_ARTIFACTS_PATH=${PATH_TO_WORKSPACE_REPO}/FFSLD_ARTIFACTS
    for dir in "$PATH_TO_DEV_REGIONS_REPO"/genctl-ng-* "$PATH_TO_DEV_REGIONS_REPO"/rias-ng-* "$PATH_TO_DEV_REGIONS_REPO"/mascd-*; do
        if [ -d "$dir" ]; then
            for file in "$dir"/*; do
                if [ -f "$file" ]; then
                    echo -e "${BGreen}Processing file: $file ............................................................................. ${NC}"
                    # Extract just the file name without parent folder and extensions
                    testbed_name="${file##*/}"
                    testbed_name="${testbed_name%.*}"
                    echo -e "${BGreen}Testbed Name: $testbed_name ............................................................................. ${NC}"
                    ${PATH_TO_GENCTL_CI}/scripts/setup_and_merge_envrionment_files.sh ${file} ${PATH_TO_DEV_REGIONS_REPO}/vetted-versions.yaml ${PATH_TO_WORKSPACE_REPO}/master_merged_vv_file.yaml
                    ${PATH_TO_GENCTL_CI}/scripts/generateFFSLD/generateFFSLD.sh ${file}
                    git pull origin master
                    echo "upload to cos"
                    ${PATH_TO_GENCTL_CI}/scripts/ffsld_upload_to_cos/ffsld_upload_to_cos.sh ${FFSLD_ARTIFACTS_PATH}
                    rm ${PATH_TO_WORKSPACE_REPO}/master_merged_vv_file.yaml
                    find ${FFSLD_ARTIFACTS_PATH} -mindepth 1 -delete
                    echo -e "${BPurple}FFSLDs are generated for file: $file ............................................................................. ${NC}"
                fi
            done
        fi
    done
}

if [[ $modified_files =~ "vetted-versions.yaml" ]]; then
    echo -e "${BRed}vetted-versions.yaml has been modified ............................................................................. ${NC}"
    if git diff -U0 HEAD~1 HEAD -- vetted-versions.yaml | grep -q "variation_value"; then
        echo -e "${BRed}The modified line contains variation_value, ffsld needs to be generated. ............................................................................. ${NC}"

        generate_ffsld_for_all_env
    else
        echo -e "${BGreen}The modified lines do not contain variation_value, no need to generate FFSLDs ............................................................................. ${NC}"
        exit 0
    fi
else
    for every_file_modified in "${modified_files[@]}"; do
        export FFSLD_ARTIFACTS_PATH=${PATH_TO_WORKSPACE_REPO}/FFSLD_ARTIFACTS
        echo -e "${BRed}$every_file_modified has been modified ............................................................................. ${NC}"
        if git diff -U0 HEAD~1 HEAD -- $every_file_modified | grep -q "variation_value"; then
            # Extract just the file name without parent folder and extensions
            testbed_name="${file##*/}"
            testbed_name="${testbed_name%.*}"
            echo -e "${BGreen}Testbed Name: $testbed_name ............................................................................. ${NC}"
            ${PATH_TO_GENCTL_CI}/scripts/setup_and_merge_envrionment_files.sh $PATH_TO_DEV_REGIONS_REPO/${every_file_modified} ${PATH_TO_DEV_REGIONS_REPO}/vetted-versions.yaml ${PATH_TO_WORKSPACE_REPO}/master_merged_vv_file.yaml
            ${PATH_TO_GENCTL_CI}/scripts/generateFFSLD/generateFFSLD.sh $PATH_TO_DEV_REGIONS_REPO/${every_file_modified}
            echo "upload to cos"
            ${PATH_TO_GENCTL_CI}/scripts/ffsld_upload_to_cos/ffsld_upload_to_cos.sh ${FFSLD_ARTIFACTS_PATH}
        else
            echo -e "${BGreen}In $every_file_modified file, the modified lines do not contain variation_value, no need to generate FFSLDs ............................................................................. ${NC}"
            exit 0
        fi
    done
fi
