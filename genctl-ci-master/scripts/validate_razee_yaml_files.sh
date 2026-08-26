#!/bin/bash -eu
#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# Set flags
set -eu
# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh
START=$(date +%s)
echo "Start validating yaml files in hack/deploy directory of ${1}"
WORKSPACE_DIR=$1
PATH_TO_GENCTL_CI=$2
echo "validate_yaml_files.sh: WORKSPACE_DIR=${WORKSPACE_DIR}"
echo "validate_yaml_files.sh: PATH_TO_GENCTL_CI=${PATH_TO_GENCTL_CI}"

pushd ${PATH_TO_GENCTL_CI}
echo "validate_razee_files.sh: ${PWD}"
echo "Installing requirements from validate_razee_files.txt"
python3 -m pip install -r scripts/validate_yaml_files.txt
mkdir /tmp/scripts/
cp scripts/validate_yaml_files.py /tmp/scripts/
popd

for filename in $(find $WORKSPACE_DIR/hack/deploy/razee -type f -name "*.yaml"); do
    echo "Validating ${filename}"
    python3 /tmp/scripts/validate_yaml_files.py --file=$filename
done

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Validate Razee YAML Files took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"