#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2019-2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# The following environment variables need to be set before executing the script:
#PATH_TO_GENCTL_CI
#PATH_TO_WORKSPACE_REPO
#VETTED_VERSION_REPO
#VETTED_VERSION_REPO_UPDATED  (optional, used in a razee hotfix pipeline)
#RIAS_GLOBALS_REPO

#ARTIFACTORY_DOCKER_PROD_URL:
#GENCTL_VETTED_VERSIONS:
#GIT_PRIVATE_KEY (e.g. ghe-private-key)
#GLOBAL_TEST_CONFIG (default: tests/qa/cpap/suites/rias_no_cos.ini)
#GLOBAL_META_PURPOSES (default: smoke)
#SMOTAINER_INTEGRATION_BRANCH (e.g integration-testing-branch)
#SECRET_MANAGER_KEY_CSI (e.g. secret-manager-api-key-csi)
#CC_ARTIF_ACCESS_TOKEN (e.g wcp-genctl-docker-local-artifactory-token)
#WCP_ARTIFACTORY_USERNAME (e.g wcp-genctl-docker-local-artifactory-username))
#HOTFIX_FUNCTIONAL_TESTS: ""
#RAZEE_HOTFIX: ""

# Set flags
set -ex
# Set default values
export GLOBAL_TEST_CONFIG=${GLOBAL_TEST_CONFIG:-"tests/qa/cpap/suites/rias_no_cos.ini"}
export GLOBAL_META_PURPOSES=${GLOBAL_META_PURPOSES:-"smoke"}
export RELEASEDEPLOY_LOCK_ENVIRONMENTS=${RELEASEDEPLOY_LOCK_ENVIRONMENTS:-""}

# By default, we do NOT want to skip vetted versions
USE_LOCALLY_BUILT_SMOTAINER_IMAGE=${USE_LOCALLY_BUILT_SMOTAINER_IMAGE:-"false"}

# TODO: remove $KEYS_DIR once smotainer stops requiring it
KEYS_DIR=/tmp/keys
mkdir -p ${KEYS_DIR}

export root_dir=${PWD}
echo root_dir: ${root_dir}

function get_cluster_ip() {
  # Reduce log verbosity
  set +x
  echo "Searching for cluster directory."
  cluster_dir=$(find -L ${RIAS_GLOBALS_REPO} -type f -name "$1\.yaml")
  if [[ -z ${cluster_dir} ]]; then
    echo "Cluster $1 directory was not found in globals, no op"
    exit 1
  fi
  echo "Cluster directory : ${cluster_dir}."
  template_data=$(yq -r '.spec.strTemplates[]' "${cluster_dir}")

  cluster_t=$2
  if [[ "${cluster_t}" == "public" ]]; then
      CLUSTER_IP=$(echo "${template_data}" | yq -r '.data.ingress' | jq -r '.hosts[0]')
      echo "Use public cluster ip : ${CLUSTER_IP}"
  elif [[ "${cluster_t}" == "private" ]]; then
      CLUSTER_IP=$(echo "${template_data}" | yq -r '.data.proxy_ingress_private' | jq -r '.x_private_host')
      echo "Use private cluster ip : ${CLUSTER_IP}"
  else
    echo "CLUSTER IP TYPE: ${cluster_t} neither public nor private and not valid. Exiting ..."
    exit 1
  fi
  set -x
}

# Check if there are functional tests defined in hack/ci/pipeline.yaml
# If so we need to skip Smoke test from build_functional_tests.py
test_opt=""
# Check if pipeline.yaml file exists
if [[ -f ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml ]]; then
  # Check if functional tests were defined in pipeline.yaml
  functional_test=$(yq -r '.functional_tests | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
  # if The tests were defined and non empty value was received, filter smoke test and use only the functional test
  if [[ ! -z "$functional_test" ]]; then
    test_opt="--skip-smoke"
  fi
  # Check mzone && iks cluster configured (non optional params, if not configured no op)
    ########################################## HOTFIX ###################################################
    ##  for razee HotFix get MZONE_NAME IBMCLOUD_IKS_CLUSTER_NAME APIKEY_ALIAS from locked environment ##
    if [[ ! -z "$RAZEE_HOTFIX" ]]; then
      #copy dynamically created razee vetted version file under vetted version directory
      if [[ -d ${VETTED_VERSION_REPO_UPDATED} ]]; then
        cp ${VETTED_VERSION_REPO_UPDATED}/${GENCTL_VETTED_VERSIONS} ${VETTED_VERSION_REPO}/${GENCTL_VETTED_VERSIONS}
        echo "razee hotfix vetted version file ${GENCTL_VETTED_VERSIONS}"
        cat ${VETTED_VERSION_REPO}/${GENCTL_VETTED_VERSIONS}
      fi

      export MZONE_NAME=`cat ${RELEASEDEPLOY_LOCK_ENVIRONMENTS}/metadata`
      if [[ -z "$MZONE_NAME" ]]; then
        . ${PATH_TO_GENCTL_CI}/scripts/rebase_and_retrieve_metadata.sh
        pushd ${RELEASEDEPLOY_LOCK_ENVIRONMENTS}
        initGit
        rebase
        popd
        getPipelineDetails
        getMzone
        MZONE_NAME=$mzoneName
      fi

      case "$MZONE_NAME" in
      mzone7215)
          IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev05-etcd"
          APIKEY_ALIAS=nonprod023
          ;;
      mzone7286)
          IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev06-etcd"
          APIKEY_ALIAS=nonprod024
          ;;
      mzone7287)
          IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev07-etcd"
          APIKEY_ALIAS=nonprod025
          ;;
      mzone7288)
          IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev08-etcd"
          APIKEY_ALIAS=nonprod033
          ;;
      mzone7301)
          IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev24-etcd"
          APIKEY_ALIAS=cicd-mz2308
          ;;
      mzone7302)
          IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev25-etcd"
          APIKEY_ALIAS=cicd-mz2309
          ;;
      *)
          echo "${MZONE_NAME} is not supported for rias smoke"
          exit 1
          ;;
      esac
      ########## override functional_test if defined in the HOTFIX   #########
      if [[ ! -z "${HOTFIX_FUNCTIONAL_TESTS}" ]]; then
          functional_test=${HOTFIX_FUNCTIONAL_TESTS}
          echo "override pipeline.yaml and use BRT defined in HOTFIX configuration"
          echo "HOTFIX_FUNCTIONAL_TESTS: ${HOTFIX_FUNCTIONAL_TESTS}"
          # use enviromnent as parmeters: ${PATH_TO_WORKSPACE_REPO} ${HOTFIX_FUNCTIONAL_TESTS}
          python3 ${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/override_brt.py
          cat ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml
      fi
    else
      MZONE_NAME=$(yq -r '.deployment.mzone_name | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
      IBMCLOUD_IKS_CLUSTER_NAME=$(yq -r '.deployment.iks_cluster_name | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
      APIKEY_ALIAS=$(yq -r '.deployment.api_key_alias | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)
    fi
    JIRA_PROJECT=$(yq -r '.jira_project | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)

    echo MZONE_NAME: ${MZONE_NAME}
    echo IBMCLOUD_IKS_CLUSTER_NAME: ${IBMCLOUD_IKS_CLUSTER_NAME}
    echo APIKEY_ALIAS: ${APIKEY_ALIAS}
    if [[ -z "${MZONE_NAME}" || -z "${IBMCLOUD_IKS_CLUSTER_NAME}" || -z "${APIKEY_ALIAS}" ]]; then
      echo "Mzone name, cluster name or key alias keys are not defined in pipeline params deployment, no op."
      exit 1
    fi
else
  echo "hack/ci/pipeline.yaml does not exist. Exiting ..."
  exit 1
fi

OUTPUT_DIR=$(pwd)/smoke-output
mkdir -p ${OUTPUT_DIR}

VAULT_CERT_DIR=$(pwd)/vaultcerts
mkdir -p ${VAULT_CERT_DIR}



# Check if the update vetted version skip flag defined in the overrides, if yes exit with 0
SMOTAINER_IMAGE_PATH=qa-test/smotainer-${SMOTAINER_INTEGRATION_BRANCH}
if [[ "${USE_LOCALLY_BUILT_SMOTAINER_IMAGE}" == "true" ]]; then
  echo "Use locally built smotainer image"
  set +x  # so we don't log the password
  echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${DOCKER_REG} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
  set -x
  # DOCKER_REG is ARTIFACTORY_DOCKER_STAGING_URL registry for intermediate smotainer images
  #RELEASE_TAG_SHA is a local testing smotainer sha version
  SMOTAINER_FULL_DOCKER_IMAGE_NAME=${DOCKER_REG}/${SMOTAINER_IMAGE_PATH}:${RELEASE_TAG_SHA}
else
  set +x  # so we don't log the password
  echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_PROD_URL} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
  set -x

  # get latest smotainer release from vetted version
  SMOTAINER_IMAGE_TAG=`yq -r '.version."smotainer-release"' ${VETTED_VERSION_REPO}/${GENCTL_VETTED_VERSIONS}`
  echo SMOTAINER_IMAGE_TAG: ${SMOTAINER_IMAGE_TAG} from ${VETTED_VERSION_REPO}/${GENCTL_VETTED_VERSIONS}
  SMOTAINER_FULL_DOCKER_IMAGE_NAME=${ARTIFACTORY_DOCKER_PROD_URL}/${SMOTAINER_IMAGE_PATH}:${SMOTAINER_IMAGE_TAG}
fi

# pull smotainer image
echo SMOTAINER_FULL_DOCKER_IMAGE_NAME: ${SMOTAINER_FULL_DOCKER_IMAGE_NAME}
docker pull ${SMOTAINER_FULL_DOCKER_IMAGE_NAME}

# if PATH_TO_WORKSPACE_REPO is passed in, volume mount it to the smotainer; else, unset WS_PATH and don't volume mount
export WS_PATH=${PATH_TO_WORKSPACE_REPO}
if [ -d ${PATH_TO_WORKSPACE_REPO} ]; then
  timestamp=$(date +%Y%m%d-%H%M%S)
  #ws_volume_mount="-v $(pwd)/${WS_PATH}:/root/genctl/integration-testing/${WS_PATH}"
  ws_volume_mount="-v ${PATH_TO_WORKSPACE_REPO}:/root/genctl/integration-testing/workspace-repo-${timestamp}"
  MOUNT_WS_DIR="/root/genctl/integration-testing/workspace-repo-${timestamp}"
else
  # Unset WS_PATH so that build_functional_tests.py skips checking for user configured tests
  unset WS_PATH
  ws_volume_mount=""
fi
echo ws_volume_mount: ${ws_volume_mount}

# Run build_functional_tests.py to generate test runs json config
export OUTPUT=test_executions.json
echo "Running build_functional_tests.py ${test_opt}"

if [[ ! -z "${test_opt}" ]]; then
  # If functional tests were defined we want to skip smoke and just add the functional tests
  python3 ${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/build_functional_tests.py "${test_opt}"
else
  # if functional tests were not defined, run smoke
  python3 ${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/build_functional_tests.py
fi

# Create the temp directory where the tests that run in parallel will store the results
rm -rf ${root_dir}/test_results
mkdir ${root_dir}/test_results
num_test_suites=0
echo $functional_test > ${WS_PATH}/hack/ci/functional_tests.yaml
rpt=$(yq -r '.run_tests_in_parallel | select(. != null)' ${WS_PATH}/hack/ci/functional_tests.yaml)
# check if tests need to be run in parallel, declare the variables used to store the data on parallel runs
run_parallel_test="false"
if [[ -v rpt ]] ; then
  echo "functional_test[run_tests_in_parallel] is set $rpt"
  run_parallel_tests=$rpt
fi
echo $run_parallel_tests
declare -A parallel_pids
declare -A test_names
declare tests_failed=0

IFS='/' read -r -a path_array <<< "$WS_PATH"
WS_NAME=${path_array[*]: -1}


# loop through global test config and user defined tests generated by build_functional_tests.py
for test_execution in $(cat ${OUTPUT} | jq -c '.[]'); do
  path=$(echo ${test_execution} | jq -r '.path')
  if [[ $path == *$WS_NAME* ]]; then
      echo Runing local tests:
      test_directory="${path#*$WS_NAME}"
      MOUNT_WS_DIR+="${test_directory}"
      path=${MOUNT_WS_DIR}
  fi
  echo Running tests ${path}
  meta_purposes=$(echo ${test_execution} | jq -r '.meta_purposes')
  echo tests meta_purposes ${meta_purposes}
  meta_environment=$(echo ${test_execution} | jq -r '.meta_environment')
  echo tests meta_environment ${meta_environment}
  cmdline=$(echo ${test_execution} | jq -r '.cmdline')
  echo tests cmdline ${cmdline}
  cmdlineraw=$(echo ${test_execution} | jq -r '.cmdlineraw')
  echo tests cmdlineraw ${cmdlineraw}
  iks_cluster_name_override=$(echo ${test_execution} | jq -r '.iks_cluster_name_override')
  echo tests iks_cluster_name_override ${iks_cluster_name_override}
  meta_features=$(echo ${test_execution} | jq -r '.meta_features')
  echo tests meta_features ${meta_features}
  jira_project_override=$(echo ${test_execution} | jq -r '.jira_project')
  echo tests jira_project_override ${jira_project_override}
  processes=$(echo ${test_execution} | jq -r '.processes')
  echo tests processes count ${processes}
  endpoint_type=$(echo ${test_execution} | jq -r '.endpoint_type')
  echo cluster endpoint_type ${endpoint_type}


  # generate a meta flags string that contains a flag for each meta_purpose
  test_type=""
  if [ "${meta_purposes}" != "[]" ]; then
      meta_flags=""
      for meta_purpose in $(echo ${meta_purposes} | jq -c '.[]'); do
          meta_flags+="purpose=$(echo ${meta_purpose} | tr -d '"'),"
          test_type+="$(echo ${meta_purpose} | tr -d '"'),"
      done
  else
      meta_flags=""
  fi
  if [[ ! -z ${meta_flags} ]]; then
    # Remove the ending comma
    meta_flags=${meta_flags%?}
  fi
  echo  meta_flags: ${meta_flags}

  if [[ ! -z ${test_type} ]]; then
    # Remove the ending comma
    test_type=${test_type%?}
  else
    test_type="functional_tests"
  fi

  ###################
  # generate a meta flags string that contains a flag for each meta_environment
  environment_type=""
  echo meta_environment: ${meta_environment}
  if [ "${meta_environment}" != "[]" ]; then
      env=$(echo ${meta_environment} | jq -c '.[]')
      environment_type="environment="$(echo ${env} | tr -d '"')
  fi
  echo  environment_type: ${environment_type}


  ################
  features_flags=""
  # generate a meta flags string that contains a flag for each meta_features
  if [ "${meta_features}" != "[]" ]; then
      meta_features_flags=""
      for meta_feature in $(echo ${meta_features} | jq -c '.[]'); do
          meta_features_flags+="feature=$(echo ${meta_feature} | tr -d '"'),"
      done
  else
      meta_features_flags=""
  fi
  echo meta_features_flags: ${meta_features_flags}

  if [[ ! -z ${meta_features_flags} ]]; then
    # Remove the ending comma
    meta_features_flags=${meta_features_flags%?}
  fi
  echo meta_features_flags: ${meta_features_flags}

  ###################
  meta_tag=""
  if [ "${meta_flags}" != "" ] || [ "${environment_type}" != "" ] || [ "${meta_features_flags}" != "" ]; then
      if [ ${meta_flags} != "" ]; then
        meta_flags="${meta_flags},"
      fi
      if [ ${meta_features_flags} != "" ]; then
        meta_features_flags="${meta_features_flags},"
      fi
      meta_tag="--meta-tag="${meta_flags}${meta_features_flags}${environment_type}
  fi
  echo  meta_tag: ${meta_tag}
  ###################
  # generate a meta cmd_flags string
  cmd_flags=""
  if [ "${cmdline}" != "[]" ]; then
      for cmd in $(echo ${cmdline} | jq -c '.[]'); do
          cmd_flags+="--tc=$(echo ${cmd} | tr -d '"') "
      done
  fi
  echo cmd_flags: ${cmd_flags}

  ###################
  # generate a meta cmdraw_flags string
  cmdraw_flags=""
  if [ "${cmdlineraw}" != "[]" ]; then
      for cmd in $(echo ${cmdlineraw} | jq -c '.[]'); do
          cmdraw_flags+="$(echo ${cmd} | tr -d '"') "
      done
  fi
  echo cmdraw_flags: ${cmdraw_flags}

  ##################
  # obtain an override cluster name and generate public ip
  if [ "${iks_cluster_name_override}" != "[]" ]; then
      cluster_name=$(echo ${iks_cluster_name_override} | jq -c '.[]')
      cluster_name=$(echo ${cluster_name} | tr -d '"')
      get_cluster_ip ${cluster_name} ${endpoint_type}
      echo use overriden cluster ${iks_cluster_name_override} and cluster ip: ${CLUSTER_IP}
  else
      get_cluster_ip ${IBMCLOUD_IKS_CLUSTER_NAME} ${endpoint_type}
      echo use cluster ${IBMCLOUD_IKS_CLUSTER_NAME} cluster ip: ${CLUSTER_IP}
  fi

  jira_flags=""
  if [ "${jira_project_override}" != "[]" ]; then
    jira_flags="--abf-enable --jira-issue-type=Stability --jira-project=${jira_project_override}"
    echo "use jira project override ${jira_project_override}"
  elif [[ ! -z "${JIRA_PROJECT}" ]]; then
    jira_flags="--abf-enable --jira-issue-type=Stability --jira-project=${JIRA_PROJECT}"
    echo "use jira project ${JIRA_PROJECT}"
  fi

  if [ $processes -le 0 ]; then
    # default to 4
    processes = 4
  fi

  export TIMESTAMP=$(date +"%Y%m%d-%H-%M-%S")

  # Disable immediate pipeline termination in the event of a test suite failure.
  set +e

  if [[ ${run_parallel_tests} == "true" ]]; then
    result_file_name=$(echo $path | sed 's/\//_/g' )
    docker run --name=smotainer_$(date -u +%s) \
      --net=host \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v ${KEYS_DIR}:/root/.ssh \
      -v ${OUTPUT_DIR}:/output \
      -e SECRET_MANAGER_KEY="${SECRET_MANAGER_KEY_CSI}" \
      ${ws_volume_mount} \
      ${SMOTAINER_FULL_DOCKER_IMAGE_NAME} \
      python3 QA/lib/framework/cpap/launcher.py \
          -v \
          --tc=public_ip:${CLUSTER_IP} \
          --tc=port:443 \
          --tc=secure:True --tc=apikey:${APIKEY_ALIAS} \
          -N ${processes} \
          --out-dir=/output \
          -S ${path} \
          --report-rules-eng \
          --group-set=${MZONE_NAME} \
          --test-plan=${test_type} \
          --save-artifacts \
          --test-run=RIAS_${MZONE_NAME}_${TIMESTAMP} \
          ${meta_tag} \
          ${cmd_flags} \
          ${cmdraw_flags} \
          ${features_flags} \
          ${jira_flags} > ${root_dir}/test_results/$result_file_name &
    test_pid=$!
    parallel_pids[$test_pid]=1
    test_names[$test_pid]=$path
    echo "${!parallel_pids[*]}"
    echo "${!test_names[*]}"
    num_test_suites=$num_test_suites+1
    ls ${root_dir}/test_results/
  else
    docker run --name=smotainer_$(date -u +%s) \
      --net=host \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v ${KEYS_DIR}:/root/.ssh \
      -v ${OUTPUT_DIR}:/output \
      -e SECRET_MANAGER_KEY="${SECRET_MANAGER_KEY_CSI}" \
      ${ws_volume_mount} \
      ${SMOTAINER_FULL_DOCKER_IMAGE_NAME} \
      python3 QA/lib/framework/cpap/launcher.py \
          -v \
          --tc=public_ip:${CLUSTER_IP} \
          --tc=port:443 \
          --tc=secure:True --tc=apikey:${APIKEY_ALIAS} \
          -N ${processes} \
          --out-dir=/output \
          -S ${path} \
          --report-rules-eng \
          --group-set=${MZONE_NAME} \
          --test-plan=${test_type} \
          --save-artifacts \
          --test-run=RIAS_${MZONE_NAME}_${TIMESTAMP} \
          ${meta_tag} \
          ${cmd_flags} \
          ${cmdraw_flags} \
          ${features_flags} \
          ${jira_flags}
    test_result=$?

    if [[ ${test_result} -ne 0 ]]; then
      tests_failed=1
    fi

    # Re-enable immediate pipeline termination upon error.
    set -e
  fi
done
##########
# We need to wait for the test to complete here if tests are run in parallel
##########
if [[ ${run_parallel_tests} == "true" ]]; then
  echo "Going to wait for tests to complete...."
  echo "Pid indices ${!parallel_pids[*]}"
  echo "Test name indices ${!test_names[*]}"
  echo "Number of entries in parallel_pid array ${#parallel_pids[@]}"
  echo "Number of entries in test_name array ${#test_names[@]}"
  for i in "${!parallel_pids[@]}"; do
    echo "waiting for pid $i"
    echo "test name ${test_names[$i]}}"
    wait $i
    test_result=$?
    echo "PID $i terminated with exit code $test_result"
    if [[ ${test_result} -ne 0 ]]; then
      tests_failed=1
    fi
  done

  # Re-enable immediate pipeline termination upon error.
  set -e
fi


exit ${tests_failed}
