#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2021, 2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

set -eux
export BUILD_ROOT=${PWD}

case "$MZONE_NAME" in
mzone7215)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev05-etcd"
    IBMCLOUD_MZONE_CLUSTER_NAME="mzone7215"
    ;;
mzone7286)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev06-etcd"
    IBMCLOUD_MZONE_CLUSTER_NAME="mzone7286"
    ;;
mzone7287)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev07-etcd"
    IBMCLOUD_MZONE_CLUSTER_NAME="mzone7287"
    ;;
mzone7288)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev08-etcd"
    IBMCLOUD_MZONE_CLUSTER_NAME="mzone7288"
    ;;
mzone7301)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev24-etcd"
    IBMCLOUD_MZONE_CLUSTER_NAME="mzone7301"
    ;;
mzone7302)
    IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev25-etcd"
    IBMCLOUD_MZONE_CLUSTER_NAME="mzone7302"
    ;;
*)
    echo "${MZONE_NAME} is not supported for rias deploys"
    exit 1
    ;;
esac
export IBMCLOUD_IKS_CLUSTER_NAME
echo "IBMCLOUD_IKS_CLUSTER_NAME=${IBMCLOUD_IKS_CLUSTER_NAME}"
export IBMCLOUD_MZONE_CLUSTER_NAME
echo "IBMCLOUD_MZONE_CLUSTER_NAME=${IBMCLOUD_MZONE_CLUSTER_NAME}"

export LAUNCH_DARKLY_RULE_TAG=${IBMCLOUD_IKS_CLUSTER_NAME},${IBMCLOUD_MZONE_CLUSTER_NAME}
echo "LAUNCH_DARKLY_RULE_TAG=${LAUNCH_DARKLY_RULE_TAG}"
export GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION=${GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION}
echo "GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION=${GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION}"


if [[ -f ${PATH_TO_WORKSPACE_REPO:-}/hack/ci/pipeline.yaml ]]; then
  LAUNCH_DARKLY_FEATURE_FLAG=$(yq -r '.deployment.feature_flag | select(. != null)' $PATH_TO_WORKSPACE_REPO/hack/ci/pipeline.yaml)
else
  LAUNCH_DARKLY_FEATURE_FLAG=""
fi
export LAUNCH_DARKLY_FEATURE_FLAG=${LAUNCH_DARKLY_FEATURE_FLAG}
echo "LAUNCH_DARKLY_FEATURE_FLAG=${LAUNCH_DARKLY_FEATURE_FLAG}"

python3 -m pip install -r $PATH_TO_GENCTL_CI/scripts/featureflags/requirements.txt
echo RAZEE_HOTFIX_ON_DEPLOY_NEXT_GENERATION: ${RAZEE_HOTFIX_ON_DEPLOY_NEXT_GENERATION}
#if not a razee hotfix roll back LD components feature flags to have a default variation (MASTER) for CI cluster rule tags
if [[ -z "$RAZEE_HOTFIX_ON_DEPLOY_NEXT_GENERATION" && "$HOTFIX" == false ]]; then
    python3 -m pip install -r $PATH_TO_GENCTL_CI/scripts/featureflags/requirements.txt
    #set up inception FF version
    for rule_tag in $(echo ${LAUNCH_DARKLY_RULE_TAG} | tr "," "\n")
    do
        if [[ -z "${rule_tag}" ]]; then
            continue
        fi
        if [[ ${rule_tag} == mzone* ]]; then
          ############ check if need to override GDA inception version ###########
          echo IS_OVERRIDE_GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION: ${IS_OVERRIDE_GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION}
          echo OVERRIDE_GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION: ${OVERRIDE_GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION}
          if [ ${IS_OVERRIDE_GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION} = 'true' ]; then
            echo "REPOSITORY_NAME=${REPOSITORY_NAME}"
            echo LABEL_TO_SEARCH=${LABEL_TO_SEARCH}

            if [[ $IS_ONE_PIPELINE_RUN == "true" ]]
            then
              if [[ $PIPELINE_TYPE == *"pr"* ]]
              then
                PR_NUMBER=${PR_ID}
              fi
            else 
              pushd $PATH_TO_WORKSPACE_REPO
              ls -la
              # Get the PR number
              FILE=./.git/resource
              if [[ -d "$FILE" ]]; then # The new PR resource contains this information in this directory
                export PR_NUMBER=$(cat $FILE/pr)
              else
                export PR_NUMBER=$(git config --get pullrequest.id)
              fi
              # Move back
              popd
              
            fi
            echo PR_NUMBER=${PR_NUMBER}
            set +e
            python3 -m pip install -r $PATH_TO_GENCTL_CI/scripts/check_pr_has_label/requirements.txt
            python3 $PATH_TO_GENCTL_CI/scripts/check_pr_has_label/check_pr_has_label.py
            result=$?
            echo $result
            set -e
            if [[ ${result} == 0 ]]; then
              echo "Override PR label GDA inception found. Use ${OVERRIDE_GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION} as GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION version"
              export GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION=${OVERRIDE_GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION}
            else
              echo "Override PR label GDA inception not found. Use ${GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION} as GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION version"
            fi
          fi

          ########
          # Keep this option to set the version for rias-inception-version from genesis-deploy-artifacts-rias-inception parameter if we ever need new
          # razee phase for nscon and kali
          #echo "set ${GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION} version of rias-inception FF version for ${rule_tag}"
          #python3 genctl-ci-repo/scripts/featureflags/featureflags.py "rias-inception-version" add_and_use_in_rule ${GENESIS_DEPLOY_ARTIFACTS_RIAS_INCEPTION} ${LAUNCH_DARKLY_ENVIRONMENT} ${rule_tag}
          ########
          echo "set default version of rias-inception FF version for ${rule_tag}"
          python3 $PATH_TO_GENCTL_CI/scripts/featureflags/featureflags.py "rias-inception-version" use_default_in_rule ${LAUNCH_DARKLY_ENVIRONMENT} ${rule_tag}
        elif [[ ${rule_tag} == rias* ]]; then
          echo "set default version of rias-inception FF version for ${rule_tag}"
          python3 $PATH_TO_GENCTL_CI/scripts/featureflags/featureflags.py "rias-inception-version" use_default_in_rule ${LAUNCH_DARKLY_ENVIRONMENT} ${rule_tag}
        else
            echo "${rule_tag} does not match neither genctl nor rias, Exiting..."
            exit 1
        fi
        #all image-version FF and rias-globals with target rule ${rule_tag} will be rolled back to default variation
        echo "update for default version all feature flags for ${rule_tag}"
        python3 $PATH_TO_GENCTL_CI/scripts/featureflags/featureflags.py "" roll_to_default ${LAUNCH_DARKLY_ENVIRONMENT} ${rule_tag} "bogus_feature_flag"
    done
    #update LD component version with the current testing hash
    if [[ ${RIAS_DEPLOY_COMPONENT_TYPE:-} == 'genctl' && ! -z ${WORKSPACE_REPO_NAME:-} && ${HOTFIX} == 'false' ]]; then
      if [[ $IS_ONE_PIPELINE_RUN == "true" ]] && [[ $PIPELINE_TEMPLATE_TYPE == "razee" ]]
      then
        if [[ ! -z "${RESULT_DEV_INT_SHA}" ]]
        then
          echo "Equivalent dev-integ SHA is: ${RESULT_DEV_INT_SHA}"
          export GIT_SHA=${RESULT_DEV_INT_SHA}
        else
          echo "At this point, expected to have the equivalent dev-integ SHA on variable RESULT_DEV_INT_SHA, but is empty"
          echo "Will exit with error..."
          exit 1
        fi
      else
        pushd $PATH_TO_WORKSPACE_REPO
        export GIT_SHA=$(git rev-parse --verify HEAD)
        echo "GIT_SHA=${GIT_SHA}"
        popd
      fi
      echo "LAUNCH_DARKLY_RULE_TAG=${LAUNCH_DARKLY_RULE_TAG}"
      for rule_tag in $(echo ${LAUNCH_DARKLY_RULE_TAG} | tr "," "\n")
      do
          if [[ -z "${rule_tag}" ]]; then
            continue
          else
            echo "------------------------------------------------------------------------------------"
            echo "set component feature flag ${LAUNCH_DARKLY_FEATURE_FLAG} on environment: ${rule_tag}"
            python3 $PATH_TO_GENCTL_CI/scripts/featureflags/featureflags.py ${LAUNCH_DARKLY_FEATURE_FLAG} add_and_use_in_rule ${GIT_SHA} ${LAUNCH_DARKLY_ENVIRONMENT} ${rule_tag}
          fi
      done
    fi
else
    pushd $PATH_TO_WORKSPACE_REPO
    export GIT_SHA=$(git rev-parse --verify HEAD)
    echo "GIT_SHA=${GIT_SHA}"
    git_tag=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true
    echo "git_tag=${git_tag}"
    popd

    export BASE_ENVIRONMENT_PATH=$PATH_TO_VETTED_VERSIONS_REPO/"new-${RAZEE_HOTFIX_NEXTGEN_ENVIRONMENT_FILE}"
    echo BASE_ENVIRONMENT_PATH: ${BASE_ENVIRONMENT_PATH}
    if [[ -z $(yq -r '.apps | select(. != null)' $BASE_ENVIRONMENT_PATH) ]]; then
        echo "old vetted versions format files,setup not supported"
        exit 0
    fi

    export LAUNCH_DARKLY_DEFAULT_URL=${LAUNCH_DARKLY_DEFAULT_URL}
    echo "LAUNCH_DARKLY_DEFAULT_URL=${LAUNCH_DARKLY_DEFAULT_URL}"
    if [ "${LAUNCH_DARKLY_RULE_TAG}" != "" ]; then
        # new hotfix builder should set - RAZEE_HOTFIX_ON_DEPLOY_NEXT_GENERATION
        if [[ ! -z "$RAZEE_HOTFIX_ON_DEPLOY_NEXT_GENERATION" ]]; then
          # if we are on a new hotfix builder pipeline and pipeline.yaml is not found, this is critical
          # exit with status code 1
          # else we can continue
          if [[ -z "${LAUNCH_DARKLY_FEATURE_FLAG}" ]]; then
            echo "Warning: LAUNCH_DARKLY_FEATURE_FLAG is not defined. Exiting ..."
            exit 0
          fi
        fi

        export BASE_CLUSTER_REMOTE_RESOURCE_PATH="$PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO/hack/deploy/razee/"
        echo BASE_CLUSTER_REMOTE_RESOURCE_PATH: ${BASE_CLUSTER_REMOTE_RESOURCE_PATH}

        #set-cluster-for-razee-hotfix.py uses BASE_ENVIRONMENT_PATH, IBMCLOUD_IKS_CLUSTER_NAME, IBMCLOUD_MZONE_CLUSTER_NAME, LAUNCH_DARKLY_FEATURE_FLAG,
        #LAUNCH_DARKLY_DEFAULT_URL, LAUNCH_DARKLY_ENVIRONMENT and BASE_CLUSTER_REMOTE_RESOURCE_PATH as a parameters
        python3 $PATH_TO_GENCTL_CI/scripts/featureflags/set-cluster-for-razee-hotfix.py
        # only run this section when using the new razee hotfix builder
        if [[ ! -z "$RAZEE_HOTFIX_ON_DEPLOY_NEXT_GENERATION" ]]; then
            for rule_tag in $(echo ${LAUNCH_DARKLY_RULE_TAG} | tr "," "\n")
            do
                if [[ -z "${rule_tag}" ]]; then
                  continue
                elif [[ ${rule_tag} == mzone* ]]; then
                  echo "check if the component ${WORKSPACE_REPO_NAME} is part of genctl inventory"
                  set +e
                  python3 $PATH_TO_GENCTL_CI/scripts/exist_in_inventory_razee.py ${WORKSPACE_REPO_NAME} $PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO/hack/deploy/razee/genctl-cluster-remote-resource.yaml
                  result=$?
                  set -e
                  if [[ ! ${result} == 0 ]]; then
                    echo "component ${WORKSPACE_REPO_NAME} is not part of genctl inventory. No need to set target rule for genctl."
                    continue
                  fi
                elif [[ ${rule_tag} == rias* ]]; then
                  echo "check if the component ${WORKSPACE_REPO_NAME} is part of rias inventory"
                  set +e
                  python3  $PATH_TO_GENCTL_CI/scripts/exist_in_inventory_razee.py ${WORKSPACE_REPO_NAME} $PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO/hack/deploy/razee/rias-cluster-remote-resource.yaml
                  result=$?
                  set -e
                  if [[ ! ${result} == 0 ]]; then
                    echo "component ${WORKSPACE_REPO_NAME} is not part of rias inventory. No need to set target rule for rias."
                    continue
                  fi
                fi
                #if tag exists, create sha and tag variation, but use tag in rule
                echo "------------------------------------------------------------------------------------"
                echo "set HF component feature flag ${LAUNCH_DARKLY_FEATURE_FLAG} on environment: ${rule_tag}"
                if [[ ! -z "$git_tag" ]]; then
                    echo "git tag ${git_tag} found, update the rule with the git tag"
                    python3 $PATH_TO_GENCTL_CI/scripts/featureflags/featureflags.py ${LAUNCH_DARKLY_FEATURE_FLAG} add_and_use_in_rule ${git_tag} ${LAUNCH_DARKLY_ENVIRONMENT} ${rule_tag}
                else
                    echo "git tag was not found, update the rule with the git hash tag"
                    python3 $PATH_TO_GENCTL_CI/scripts/featureflags/featureflags.py ${LAUNCH_DARKLY_FEATURE_FLAG} add_and_use_in_rule ${GIT_SHA} ${LAUNCH_DARKLY_ENVIRONMENT} ${rule_tag}
                fi
            done
        fi
    fi
fi
