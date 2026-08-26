#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -eu
# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh
START=$(date +%s)
# The following environment variables need to be set before executing the script:
# PATH_TO_WORKSPACE_REPO  

      echo "start genctl-ci/tasks/validate-regional-version.yaml"
      echo "Checking deployment.yaml.j2 for regional-apiversion-checker usage"

      # Verfiy the repo implements ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2 
      if [ ! -f ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2 ]; then
         echo "This repo does not implement the /hack/deployment.yaml.j2; exiting without errors"
         echo "end genctl-ci/tasks/validate-regional-version.yaml"
         END=$(date +%s)
         DIFF=$(( $END - $START ))
         echo -e "${BYellow}Validate regional version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
         exit 0
      fi
     
      # Verfiy the repo uses genctl/regional-apiversion-checker
      if ! grep -q '/genctl/regional-apiversion-checker:' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2; then 
         echo "This repo does not implement the regional-apiversion-checker; exiting without errors"
         echo "end genctl-ci/tasks/validate-regional-version.yaml"
         END=$(date +%s)
         DIFF=$(( $END - $START ))
         echo -e "${BYellow}Validate regional version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
         exit 0
      fi 
     
      echo "regional-apiversion-checker is in use"
      if grep -q 'GENCTL_REGIONALK8S_GITHASH' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2; then
        deployment_genctl_regk8s_githash_array=(`awk '/GENCTL_REGIONALK8S_GITHASH/{getline;gsub(/"/, "", $2);print $2;}' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2`)
        repo_k8s_githash="$(git -C ${PATH_TO_WORKSPACE_REPO}/src/github.ibm.com/genctl/regional-k8s-types rev-parse --verify HEAD || echo unknown)"
        echo "REGIONALK8S_TYPES_SUBMODULE_GITHASH: $repo_k8s_githash"
        for deployment_genctl_regk8s_githash in "${deployment_genctl_regk8s_githash_array[@]}"
        do
          if [ "$deployment_genctl_regk8s_githash" != "$repo_k8s_githash" ]; then
            echo "GENCTL_REGIONALK8S_GITHASH in deployment.yaml.j2 ($deployment_genctl_regk8s_githash) does NOT match REGIONAL_K8S_TYPES_SUBMODULE_GITHASH ($repo_k8s_githash)"
            echo "end genctl-ci/tasks/validate-regional-version.yaml with errors"
            END=$(date +%s)
            DIFF=$(( $END - $START ))
            echo -e "${BYellow}Validate regional version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
            exit 1
          fi
        done
      fi

      echo "GENCTL_REGIONALK8S_GITHASH in deployment.yaml.j2 matches REGIONAL_K8S_TYPES_SUBMODULE_GITHASH"
      if grep -q 'GENCTL_REGIONAL_EXTSERVER_GITHASH' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2; then
        deployment_regionalextserver_githash_array=(`awk '/GENCTL_REGIONAL_EXTSERVER_GITHASH/{getline;gsub(/"/, "", $2);print $2;}' ${PATH_TO_WORKSPACE_REPO}/hack/deploy/deployment.yaml.j2`)
        repo_regionalextserver_githash="$(git -C ${PATH_TO_WORKSPACE_REPO}/src/github.ibm.com/genctl/regional-extension-server rev-parse --verify HEAD || echo unknown)"
        echo "REGEXTSERVER_SUBMODULE_GITHASH: $repo_regionalextserver_githash"
        for deployment_apiextserver_githash in "${deployment_regionalextserver_githash_array[@]}"
        do
          if [ "$deployment_apiextserver_githash" != "$repo_regionalextserver_githash" ]; then
            echo "GENCTL_REGIONAL_EXTSERVER_GITHASH in deployment.yaml.j2 ($deployment_apiextserver_githash) does NOT match REGEXTSERVER_SUBMODULE_GITHASH ($repo_regionalextserver_githash)"
            echo "end genctl-ci/tasks/validate-regional-version.yaml with errors"
            END=$(date +%s)
            DIFF=$(( $END - $START ))
            echo -e "${BYellow}Validate regional version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"
            exit 1
          fi
        done
      fi
      echo "GENCTL_REGIONAL_EXTSERVER_GITHASH in deployment.yaml.j2 matches REGEXTSERVER_SUBMODULE_GITHASH"          
      echo "end genctl-ci/tasks/validate-regional-version.yaml"
END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Validate regional version took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............${NC}"