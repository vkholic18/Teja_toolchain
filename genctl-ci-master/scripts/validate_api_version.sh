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
# PATH_TO_WORKSPACE_REPO

    echo "start genctl-ci/tasks/validate-api-version.yaml"
    # Check for deployment.yaml.j2 first 

    if [ ! -f ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2 ]; then
       echo "This repo does not implement the /hack/deployment.yaml.j2; exiting without errors"
       echo "end genctl-ci/tasks/validate-api-version.yaml"
       END=$(date +%s)
       DIFF=$(( $END - $START ))
       echo -e "${BYellow}Validate API version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
       exit 0
    fi 

    echo "Checking deployment.yaml.j2 for apiversion-checker usage"
    if ! grep -q '/genctl/apiversion-checker:' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2; then
       echo "This repo does not implement the apiversion-check; exiting without errors"
       echo "end genctl-ci/tasks/validate-api-version.yaml"
       END=$(date +%s)
       DIFF=$(( $END - $START ))
       echo -e "${BYellow}Validate API version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
       exit 0
    fi

    echo "apiversion-checker is in use"

    if grep -q 'GENCTL_APIS_GITHASH' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2; then
       deployment_genctl_api_githash_array=(`awk '/GENCTL_APIS_GITHASH/{getline;gsub(/"/, "", $2);print $2;}' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2`)
       repo_api_githash="$(git -C ${PATH_TO_WORKSPACE_REPO}/src/github.ibm.com/genctl/apis rev-parse --verify HEAD || echo unknown)"
       echo "APIS_SUBMODULE_GITHASH: $repo_api_githash"
       for deployment_genctl_api_githash in "${deployment_genctl_api_githash_array[@]}"
          do
            if [ "$deployment_genctl_api_githash" != "$repo_api_githash" ]; then
              echo "GENCTL_APIS_GITHASH in deployment.yaml.j2 ($deployment_genctl_api_githash) does NOT match APIS_SUBMODULE_GITHASH ($repo_api_githash)"
              echo "end genctl-ci/tasks/validate-api-version.yaml with errors"
              END=$(date +%s)
              DIFF=$(( $END - $START ))
              echo -e "${BYellow}Validate API version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
              exit 1
            fi
          done
    fi
    
    echo "GENCTL_APIS_GITHASH in deployment.yaml.j2 matches APIS_SUBMODULE_GITHASH"
    if grep -q 'GENCTL_APIEXTSERVER_GITHASH' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2; then
       deployment_apiextserver_githash_array=(`awk '/GENCTL_APIEXTSERVER_GITHASH/{getline;gsub(/"/, "", $2);print $2;}' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2`)
       repo_apiextserver_githash="$(git -C ${PATH_TO_WORKSPACE_REPO}/src/github.ibm.com/genctl/api-extension-server rev-parse --verify HEAD || echo unknown)"
       echo "APIEXTSERVER_SUBMODULE_GITHASH: $repo_apiextserver_githash"
       for deployment_apiextserver_githash in "${deployment_apiextserver_githash_array[@]}"
          do
            if [ "$deployment_apiextserver_githash" != "$repo_apiextserver_githash" ]; then
              echo "GENCTL_APIEXTSERVER_GITHASH in deployment.yaml.j2 ($deployment_apiextserver_githash) does NOT match APIEXTSERVER_SUBMODULE_GITHASH ($repo_apiextserver_githash)"
              echo "end genctl-ci/tasks/validate-api-version.yaml with errors"
              END=$(date +%s)
              DIFF=$(( $END - $START ))
              echo -e "${BYellow}Validate API version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
              exit 1
            fi
          done
    fi

    echo "GENCTL_APIEXTSERVER_GITHASH in deployment.yaml.j2 matches APIEXTSERVER_SUBMODULE_GITHASH"
    echo "exiting without errors"
    echo "end genctl-ci/tasks/validate-api-version.yaml"
END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Validate API version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"