#!/bin/bash
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# The following environment variables need to be set before calling this script
# WORKSPACE_DIR, RIAS_GLOBALS_DIR, PATH_TO_GENCTL_CI, IS_DEV_INTEGRATION

# Set flags
set -u

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh
START=$(date +%s)

run_validate_razee_files() {
    pushd $1
    files=$(ls *.yaml)
    for file in $files; do
        if [ "$file" == "common-globals.yaml" ];
        then
            continue
        fi
        python3 /tmp/scripts/validate_razee_files.py --commonGlobals=common-globals.yaml --regionGlobals=$file --svcLevelConfigmap=${SVC_LEVEL_CONFIGMAP} --workspaceRazeeDir=${WORKSPACE_DIR}/hack/deploy/razee
    done
    popd
}

# Check if pipeline.yaml file exists
if [[ -f ${WORKSPACE_DIR}/hack/ci/pipeline.yaml ]]; then
    # Check svc_level_configmap is defined
    export SVC_LEVEL_CONFIGMAP=$(yq -r '.deployment.svc_level_configmap | select(. != null)' ${WORKSPACE_DIR}/hack/ci/pipeline.yaml)
    if [[ -z "${SVC_LEVEL_CONFIGMAP}" ]]; then
        echo "Workspace level config map is not defined in pipeline params deployment, exiting..."
        END=$(date +%s)
        DIFF=$(( $END - $START ))
        echo -e "${BYellow}Validate Razee files took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
        exit 0
    fi
else
    echo "hack/ci/pipeline.yaml configuration does not exist, exiting"
    END=$(date +%s)
    DIFF=$(( $END - $START ))
    echo -e "${BYellow}Validate Razee files took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
    exit 1
fi
echo "validate_razee_files.yaml: SVC_LEVEL_CONFIGMAP=${SVC_LEVEL_CONFIGMAP}"

echo "validate_razee_files.sh: WORKSPACE_DIR=${WORKSPACE_DIR}"
echo "validate_razee_files.sh: RIAS_GLOBALS_DIR=${RIAS_GLOBALS_DIR}"
echo "validate_razee_files.sh: PATH_TO_GENCTL_CI=${PATH_TO_GENCTL_CI}"
echo "validate_razee_files.sh: SVC_LEVEL_CONFIGMAP=${SVC_LEVEL_CONFIGMAP}"
echo "validate_razee_files.sh: IS_DEV_INTEGRATION=${IS_DEV_INTEGRATION}"



pushd ${PATH_TO_GENCTL_CI}
echo "validate_razee_files.sh: ${PWD}"
echo "Installing requirements from validate_razee_files.txt"
python3 -m pip install -r scripts/validate_razee_files.txt
mkdir /tmp/scripts/
cp scripts/validate_razee_files.py /tmp/scripts/
popd

pushd ${RIAS_GLOBALS_DIR}
echo "validate_razee_files.sh: ${PWD}"
echo "SVC_LEVEL_CONFIGMAP=${SVC_LEVEL_CONFIGMAP}"

if [ "${IS_DEV_INTEGRATION}" == true ];
then
    echo "IS_DEV_INTEGRATION=${IS_DEV_INTEGRATION}"
    for dir in dev-mzr dev-szr; do
        run_validate_razee_files $dir
    done
fi

if [ "${IS_DEV_INTEGRATION}" == false ];
then
    echo "IS_DEV_INTEGRATION=${IS_DEV_INTEGRATION}"
    for dir in integ stage prod; do
        run_validate_razee_files $dir
    done
fi

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Validate Razee files took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"