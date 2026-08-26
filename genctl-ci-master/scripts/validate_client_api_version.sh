#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
set -eu
# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh
START=$(date +%s)
# The following environment variables need to be set before executing the script:
#   PATH_TO_GENCTL_CI, VAULT_GIT_CONFIG_USER_EMAIL, VAULT_GIT_CONFIG_USERNAME, GIT_PRIVATE_KEY , IBM_GITHUB_URI_BASE , API_EXT_WRKSPACE_ORG_NAME, API_EXT_WRKSPACE_REPO_NAME, PATH_TO_WORKSPACE_REPO

echo "start ${PATH_TO_GENCTL_CI}/scripts/validate_client_api_version.sh"
git config --global --add url."git@github.ibm.com:".insteadOf "https://github.ibm.com"
build_root="${PWD}"

# See if the repo includes ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2
if [ ! -f ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2 ]; then
    echo "This repo does not implement ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2; exiting without errors"
    echo "end ${PATH_TO_GENCTL_CI}/scripts/validate_client_api_version.sh"
    END=$(date +%s)
    DIFF=$(( $END - $START ))
    echo -e "${BYellow}Validate client API version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
    exit 0 
fi 
# See if the repo supports the /genctl/apiversion-check; 
apiversioncheck=false
if grep -q '/genctl/apiversion-checker:' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2; then
    if grep -q 'GENCTL_APIS_GITHASH' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2; then        
        apiversioncheck=true
    fi
fi 

if [ "$apiversioncheck" = false ] ; then
    echo "This repo does not implement the /genctl/apiversion-check; exiting without errors"
    echo "end ${PATH_TO_GENCTL_CI}/scripts/validate_client_api_version.sh"
    END=$(date +%s)
    DIFF=$(( $END - $START ))
    echo -e "${BYellow}Validate client API version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
    exit 0
fi

echo "Checking deployment.yaml.j2 for /genctl/apiversion-checker usage"
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
if [ ! -d "~/.ssh" ]; then
    mkdir -p ~/.ssh
fi
ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
# If the VAULT_GIT_CONFIG_USER_EMAIL has a non-zero length, setup git email config
if [[ -n ${VAULT_GIT_CONFIG_USER_EMAIL} ]]; then
    git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
    unset VAULT_GIT_CONFIG_USER_EMAIL
fi
# If the VAULT_GIT_CONFIG_USERNAME has a non-zero length, setup git email config
if [[ -n ${VAULT_GIT_CONFIG_USERNAME} ]]; then
    git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"
    unset VAULT_GIT_CONFIG_USERNAME
fi
cd "${PATH_TO_GENCTL_RELEASE_REPO}"
FILE=component-input/inventory.json
if [ -f "$FILE" ]; then
    api_extension_workspace_hash=`jq -r '."api-extension-workspace".hash' $FILE`
    echo "cloning api-extension-workspace at this commit : $api_extension_workspace_hash "
else
    echo "$FILE does not exist."
fi
cd $build_root

# Clone the change versions repo that we will be updating
git clone ${IBM_GITHUB_URI_BASE}:${API_EXT_WRKSPACE_ORG_NAME}/${API_EXT_WRKSPACE_REPO_NAME}.git
cd api-extension-workspace
git checkout $api_extension_workspace_hash
git submodule update --init
# Clone the apis submodule repo  
cd $build_root
git clone ${IBM_GITHUB_URI_BASE}:genctl/apis.git
cd apis
echo apis path:$PWD
api_git_hashes_cmd="git rev-list `git rev-parse HEAD` --max-count=100"
api_git_hashes_arr=($($api_git_hashes_cmd))

# Clone the api-extension-server submodule repo  
cd $build_root
git clone ${IBM_GITHUB_URI_BASE}:genctl/api-extension-server.git
cd api-extension-server
echo api-extension-server path:$PWD
api_ext_server_git_hashes_cmd="git rev-list `git rev-parse HEAD` --max-count=100"
api_ext_server_git_hashes_arr=($($api_ext_server_git_hashes_cmd))

# Verfiy the githashes match 
cd $build_root
deployment_genctl_api_githash_array=(`awk '/GENCTL_APIS_GITHASH/{getline;gsub(/"/, "", $2);print $2;}' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2`)
for deployment_api_githash in "${deployment_genctl_api_githash_array[@]}"
do
    if [[ ! " ${api_git_hashes_arr[@]} " =~ " ${deployment_api_githash} " ]]; then
        echo "GENCTL_APIS_GITHASH in deployment.yaml.j2 ($deployment_api_githash) is not in api-extension-workspace supported by latest version in inventory.json"
        echo "end ${PATH_TO_GENCTL_CI}/scripts/validate_client_api_version.sh with errors"
        END=$(date +%s)
        DIFF=$(( $END - $START ))
        echo -e "${BYellow}Validate client API version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
        exit 1
    fi
done
    
echo "GENCTL_APIS_GITHASH in deployment.yaml.j2 matches APIS_SUBMODULE_GITHASH in api-extension-workspace supported by latest version in inventory.json"
if grep -q 'GENCTL_APIEXTSERVER_GITHASH' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2; then
    deployment_apiextserver_githash_array=(`awk '/GENCTL_APIEXTSERVER_GITHASH/{getline;gsub(/"/, "", $2);print $2;}' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2`)
    for deployment_apiextserver_githash in "${deployment_apiextserver_githash_array[@]}"
    do
        if [[ ! " ${api_ext_server_git_hashes_arr[@]} " =~ " ${deployment_apiextserver_githash} " ]]; then
        echo "GENCTL_APIEXTSERVER_GITHASH in deployment.yaml.j2 ($deployment_apiextserver_githash) is not in api-extension-workspace supported by latest version in inventory.json"
        echo "end ${PATH_TO_GENCTL_CI}/scripts/validate_client_api_version.sh with errors"
        END=$(date +%s)
        DIFF=$(( $END - $START ))
        echo -e "${BYellow}Validate client API version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
        exit 1
        fi
    done
fi
echo "GENCTL_APIEXTSERVER_GITHASH in deployment.yaml.j2 matches API_EXTENSION_SERVER_SUBMODULE_GITHASH in api-extension-workspace supported by latest version in inventory.json"
echo "end ${PATH_TO_GENCTL_CI}/scripts/validate_client_api_version.sh"

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Validate client API version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"