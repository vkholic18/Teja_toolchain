#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

#
# This scripts determines what tests to run for a feature flag and then runs them
#

# Set flags
set -ex

# Set default values
export GLOBAL_TEST_CONFIG=${GLOBAL_TEST_CONFIG:-"tests/qa/cpap/suites/rias_no_cos.ini"}
export GLOBAL_META_PURPOSES=${GLOBAL_META_PURPOSES:-"smoke"}
export RELEASEDEPLOY_LOCK_ENVIRONMENTS=${RELEASEDEPLOY_LOCK_ENVIRONMENTS:-""}

# OnePipeline overrides
if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
  export ROOT_DIR=${WORKSPACE}
  export WORKSPACE_NAME=${APP_REPO_NAME}
  set +x  # so we don't log the secret
  export SECRET_MANAGER_KEY_CSI=$(get_secret secret-manager-api-key-csi)
  set -x
fi


ls -ls ${PROMOTION_OUTPUT}
if [[ ! "$(ls -A ${PROMOTION_OUTPUT})" ]]; then
  echo "Promotion folder is empty, no need to run promotion tests. Exiting ..."
  exit 0
fi

if [[ -e ./pipe-data/pr.sh ]]; then
  . pipe-data/pr.sh
  echo "Git Environment:"
  env | grep ^PR_
fi

export PROMOTION_PR_BRANCH=${PR_BRANCH}
echo PROMOTION_PR_BRANCH: ${PROMOTION_PR_BRANCH}
export PROMOTION_PR_NUMBER=${PR_ID}
echo PROMOTION_PR_NUMBER: ${PROMOTION_PR_NUMBER}

export USE_SINGLE_PROMOTION_PIPELINE=$(get_env USE_SINGLE_PROMOTION_PIPELINE)
export SPP_FEATURE_FLAG=$(get_env SPP_FEATURE_FLAG)

export NO_JIRA_FLAGS_FOR_CD_TEST=$(get_env no_jira_flags_for_cd_test)

# Search for dev config file and extract the public ip
function get_cluster_public_ip() {
  # Reduce log verbosity
  set +x
  if [ "$1" != "${RIAS_URL}" ]; then
    echo "Searching for cluster directory."
    cluster_dir=$(find -L ${PATH_TO_RIAS_GLOBALS_REPO} -type f -name "$1\.yaml")
    if [[ -z ${cluster_dir} ]]; then
      echo "Cluster $1 directory was not found in globals, no op"
      exit 1
    fi
    echo "Cluster directory : ${cluster_dir}."
    template_data=$(yq -r '.spec.strTemplates[]' "${cluster_dir}")
    PUBLIC_IP=$(echo "${template_data}" | yq -r '.data.ingress' | jq -r '.hosts[0]')
  else
    PUBLIC_IP="${RIAS_URL#https://}"
  fi
  echo "Cluster public ip: ${PUBLIC_IP}"
  set -x
}

# We need to wait for the test to complete here if tests are run in parallel
function wait_for_tests(){

  if [[ ( "$USE_SINGLE_PROMOTION_PIPELINE" != "true" ) ||
        ( "$USE_SINGLE_PROMOTION_PIPELINE" == "true" && "$SPP_FEATURE_FLAG" == "$FEATURE_FLAG" ) ]]; then
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
        # If a test suite failed, then add it to failed_results.
        if [[ ${test_result} -ne 0 ]]; then
          if [[ "${log_ff_name_failed}" == "false" ]]; then
              failed_tests+="\n\n$(echo ${FEATURE_FLAG}:)"
              log_ff_name_failed=true
          fi
          failed_tests+="\n$(echo \* ${test_rollup[$i]})"
        else
          if [[ "${log_ff_name_passed}" == "false" ]]; then
              passed_tests+="\n\n$(echo ${FEATURE_FLAG}:)"
              log_ff_name_passed=true
          fi
          passed_tests+="\n$(echo \* ${test_rollup[$i]})"
        fi
      done
      #Empty arrays
      parallel_pids=()
      test_names=()
    fi
  fi

}

# pull smotainer image
OUTPUT_DIR=$(pwd)/smoke-output
mkdir -p ${OUTPUT_DIR}
VAULT_CERT_DIR=$(pwd)/vaultcerts
mkdir -p ${VAULT_CERT_DIR}
set +x  # so we don't log the password
echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_PROD_URL} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
set -x

# get latest smotainer release from vetted version
SMOTAINER_IMAGE_PATH=qa-test/smotainer-${SMOTAINER_INTEGRATION_BRANCH}
SMOTAINER_IMAGE_TAG=`yq -r '.version."smotainer-release"' ${VETTED_VERSION_REPO}/${GENCTL_VETTED_VERSIONS}`
echo SMOTAINER_IMAGE_TAG: ${SMOTAINER_IMAGE_TAG} from ${VETTED_VERSION_REPO}/${GENCTL_VETTED_VERSIONS}
# pull smotainer image
docker pull ${ARTIFACTORY_DOCKER_PROD_URL}/${SMOTAINER_IMAGE_PATH}:${SMOTAINER_IMAGE_TAG}

COMPONENTS_ORDERED_LIST_FILE="components-ordered-list"
echo COMPONENTS_ORDERED_LIST_FILE location: ${PROMOTION_OUTPUT}/${COMPONENTS_ORDERED_LIST_FILE}
if [ ! -f ${PROMOTION_OUTPUT}/${COMPONENTS_ORDERED_LIST_FILE} ]; then
  echo "COMPONENTS_ORDERED_LIST_FILE file not found!"
else
    COMPONENTS_ORDERED_LIST=$(cat ${PROMOTION_OUTPUT}/${COMPONENTS_ORDERED_LIST_FILE})
    echo COMPONENTS_ORDERED_LIST: ${COMPONENTS_ORDERED_LIST}
fi

#CD-2334 FEATURE_FLAG tag extraction and store in components-ordered-list
ws_repo_path="${PATH_TO_WORKSPACE_REPO}/environment.yaml"
touch "${PROMOTION_OUTPUT}/components-ordered-list-version"
chmod 755 "${PROMOTION_OUTPUT}/components-ordered-list-version"
cat /dev/null > "${PROMOTION_OUTPUT}/components-ordered-list-version"

if [[ $PROMOTION_PR_BRANCH == *-RB-* ]]; then
  for i in `cat ${PROMOTION_OUTPUT}/components-ordered-list` ; do VERSION=`cat $ws_repo_path |grep -wA2 $i | sed -n '$p' | awk '{print $3}'` ; echo  $i $VERSION>>${PROMOTION_OUTPUT}/components-ordered-list-version ; done
else
  for i in `cat ${PROMOTION_OUTPUT}/components-ordered-list` ; do VERSION=`cat $ws_repo_path |grep -wA2 $i | sed -n '$p' | awk '{print $2}'` ; echo  $i $VERSION>>${PROMOTION_OUTPUT}/components-ordered-list-version ; done
fi
# Collects results from all test suite(s) for all ${COMPONENTS_ORDERED_LIST[@]}
# CD-2656: build a list of tests that are going to run for this promotion and post to the Promotion PR.
tests_to_run=""
passed_tests=""
failed_tests=""

echo "Determine tests to Run"
for test_component in ${COMPONENTS_ORDERED_LIST[@]} ; do
  promote_workspace=${PROMOTION_OUTPUT}/${test_component}
  echo promote_workspace: ${promote_workspace}
  export WS_PATH=${promote_workspace}

  if [ -d "${promote_workspace}" ]; then
    # Check if there are functional tests defined in hack/ci/pipeline.yaml
    # If so we need to skip Smoke test from build_functional_tests.py
    # Check if pipeline.yaml file exists
    cat ${WS_PATH}/hack/ci/pipeline.yaml || true
    cat ${PROMOTION_OUTPUT}/components-ordered-list-version || true

    if [[ -f ${WS_PATH}/hack/ci/pipeline.yaml ]]; then
      FEATURE_FLAG=$(yq -r '.deployment.feature_flag | select(. != null)' ${WS_PATH}/hack/ci/pipeline.yaml)
      FEATURE_FLAG_VERSION=$(keyword="$FEATURE_FLAG" ; awk -v key="$keyword" '$1 ==key {print $2}' "${PROMOTION_OUTPUT}/components-ordered-list-version")
      if [[ ( "$USE_SINGLE_PROMOTION_PIPELINE" != "true" ) ||
            ( "$USE_SINGLE_PROMOTION_PIPELINE" == "true" && "$SPP_FEATURE_FLAG" == "$FEATURE_FLAG" ) ]]; then
        echo "Adding $FEATURE_FLAG to test list"

        # skip rias_globals, genctl_globals, and rias_inception flags
        if [[ $FEATURE_FLAG != "rias_globals_version" ]] &&
          [[ $FEATURE_FLAG != "genctl_globals_version" ]] &&
          [[ $FEATURE_FLAG != "rias_inception_version" ]]; then
          tests_to_run+="$FEATURE_FLAG:$FEATURE_FLAG_VERSION\n"
        fi

        test_opt=""
        #Check if functional tests were defined in pipeline.yaml
        functional_test=$(yq -r '.functional_tests | select(. != null)' ${WS_PATH}/hack/ci/pipeline.yaml)
        # if The tests were defined and non empty value was received, filter smoke test and use only the functional test
        if [[ ! -z "$functional_test" ]]; then
          test_opt="--skip-smoke"
        fi

        export OUTPUT=test_executions.json
        echo "Running build_functional_tests.py ${test_opt}"
        if [[ ! -z "${test_opt}" ]]; then
          #If functional tests were defined we want to skip smoke and just add the functional tests
          python3 ${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/build_functional_tests.py "${test_opt}"
        else
          #if functional tests were not defined, run smoke
          python3 ${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/build_functional_tests.py
        fi

        declare -i test_idx=1
        tests_to_execute=""
        for test_execution in $(cat ${OUTPUT} | jq -c '.[]'); do
              testplan=$(echo ${test_execution} | jq -r '.test_plan')
              echo "Adding $testplan to test list"
              tests_to_execute+=" $test_idx. $testplan \n"
              test_idx=$test_idx+1
        done

        if [[ -z "$tests_to_execute" ]]; then
          tests_to_run+="* No test defined. Skipping\n"
        else
          tests_to_run+=$tests_to_execute
        fi
        tests_to_run+="\n"
      fi

    fi
  fi
done

echo "Tests to Run: ${tests_to_run}"

if [[ ! -z $tests_to_run ]]; then
  # Overrides for OnePipeline
  if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
    base_url="${IBM_HTTPS_BASE_URL}"
    org_repo="${APP_REPO_ORG}/${APP_REPO_NAME}"
    pr_number="${PROMOTION_PR_NUMBER}"
  elif [ -f "$NEW_RESOURCE_URL_PATH" ]; then
    url=$(cat $NEW_RESOURCE_URL_PATH)
    pat='(.*)\/([^\/]+\/[^\/]+)\/pull\/([0-9]+)'
    [[ "$url" =~ $pat ]]
    base_url="${BASH_REMATCH[1]}"
    org_repo="${BASH_REMATCH[2]}"
    pr_number="${BASH_REMATCH[3]}"
  else
    url=$(cat $OLD_RESOURCE_URL_PATH)
    pat='(.*)\/([^\/]+\/[^\/]+)\/pull\/([0-9]+)'
    [[ "$url" =~ $pat ]]
    base_url="${BASH_REMATCH[1]}"
    org_repo="${BASH_REMATCH[2]}"
    pr_number="${BASH_REMATCH[3]}"
  fi

  # Get PR org to supply to the smotainer run which reports the results back to the PR
  PR_ORG=${org_repo%/*}

  echo "Getting PR Number"
  set +x
  pr=$( \
      curl \
          --connect-timeout 30 --retry 5 --retry-delay 3 --fail -sS \
          -H "Authorization: Bearer ${GHE_API_TOKEN}" \
          ${base_url}/api/v3/repos/${org_repo}/pulls/${pr_number} \
  )
  echo "[INFO] PR value=" 
  echo $pr | jq -r . | grep -A2 -B2 "closed_at" || true

  if [ "$(echo $pr | jq .closed_at)" != null ]; then
    echo "PR is merged; exiting"
    exit 1
  fi
  set -x

  # Post to the Promotion PR
  echo "Posting Tests to Run to PR"
  set +x
  curl \
      -s \
      -X POST \
      -H "Authorization: Bearer ${GHE_API_TOKEN}" \
      -d "{\"body\":\"Running Promotion tests for:\n\n ${tests_to_run}\"}" \
      ${base_url}/api/v3/repos/${org_repo}/issues/${pr_number}/comments \
      > /dev/null
fi

set -x
echo "Running Tests"
skipped_duplicate_test_names=""
for test_component in ${COMPONENTS_ORDERED_LIST[@]} ; do
  promote_workspace=${PROMOTION_OUTPUT}/${test_component}
  echo promote_workspace: ${promote_workspace}
  log_ff_name_passed=false
  log_ff_name_failed=false
  if [ -d "${promote_workspace}" ]; then
    KEYS_DIR=/tmp/${test_component}/keys
    echo KEYS_DIR: ${KEYS_DIR}
    mkdir -p ${KEYS_DIR}
    export WS_PATH=${promote_workspace}
    echo WS_PATH: ${WS_PATH}

    # Check if there are functional tests defined in hack/ci/pipeline.yaml
    # If so we need to skip Smoke test from build_functional_tests.py
    test_opt=""
    # Check if pipeline.yaml file exists
    if [[ -f ${WS_PATH}/hack/ci/pipeline.yaml ]]; then
      FEATURE_FLAG=$(yq -r '.deployment.feature_flag | select(. != null)' ${WS_PATH}/hack/ci/pipeline.yaml)
      FEATURE_VERSION=$(keyword="$FEATURE_FLAG" ; awk -v key="$keyword" '$1 ==key {print $2}' "${PROMOTION_OUTPUT}/components-ordered-list-version")

      set +x
      echo " ----------------------------------------------------- Promotion test for ${FEATURE_FLAG}:${FEATURE_VERSION} feature flag -----------------------------------------------------"
      set -x
      #Check if functional tests were defined in pipeline.yaml
      functional_test=$(yq -r '.functional_tests | select(. != null)' ${WS_PATH}/hack/ci/pipeline.yaml)
      # if The tests were defined and non empty value was received, filter smoke test and use only the functional test
      if [[ ! -z "$functional_test" ]]; then
        test_opt="--skip-smoke"
      fi
      # Check mzone && iks cluster configured (non optional params, if not configured no op)
      MZONE_NAME=$(yq -r '.deployment.mzone_name | select(. != null)' ${WS_PATH}/hack/ci/pipeline.yaml)
      # Set mzone name to uppercase to be compatible with test dashboard.
      MZONE_NAME=$(echo ${MZONE_NAME} | tr '[:lower:]' '[:upper:]')
      IBMCLOUD_IKS_CLUSTER_NAME=$(yq -r '.deployment.iks_cluster_name | select(. != null)' ${WS_PATH}/hack/ci/pipeline.yaml)
      RIAS_URL=$(yq -r '.deployment.rias_url | select(. != null)' ${WS_PATH}/hack/ci/pipeline.yaml)
      APIKEY_ALIAS=$(yq -r '.deployment.api_key_alias | select(. != null)' ${WS_PATH}/hack/ci/pipeline.yaml)
      JIRA_PROJECT=$(yq -r '.jira_project | select(. != null)' ${WS_PATH}/hack/ci/pipeline.yaml)
      echo MZONE_NAME: ${MZONE_NAME}
      echo IBMCLOUD_IKS_CLUSTER_NAME: ${IBMCLOUD_IKS_CLUSTER_NAME}
      echo RIAS_URL: ${RIAS_URL}
      echo APIKEY_ALIAS: ${APIKEY_ALIAS}
      if [[ -z "${MZONE_NAME}" || -z "${APIKEY_ALIAS}" ]] || [[ -z ${IBMCLOUD_IKS_CLUSTER_NAME} && -z ${RIAS_URL} ]]; then
        echo "Mzone name, cluster name, rias url or key alias keys are not defined in pipeline params deployment, no op."
        exit 0
      fi

      # if workspace-repo is passed in, volume mount it to the smotainer; else, unset WS_PATH and don't volume mount
      if [ -d $WS_PATH ]; then
        ws_volume_mount="-v ${WS_PATH}:/root/genctl/integration-testing/${WS_PATH}"
      else
        #Unset WS_PATH so that build_functional_tests.py skips checking for user configured tests
        unset WS_PATH
        ws_volume_mount=""
      fi
      echo ws_volume_mount: ${ws_volume_mount}

      # Run build_functional_tests.py to generate test runs json config
      export OUTPUT=test_executions.json
      # Set path to track functional test runs
      export TEST_TRACKER_PATH=test_tracker.json
      echo "Running build_functional_tests.py ${test_opt}"
      if [[ ! -z "${test_opt}" ]]; then
        #If functional tests were defined we want to skip smoke and just add the functional tests
        python3 ${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/build_functional_tests.py "${test_opt}"
      else
        #if functional tests were not defined, run smoke
        python3 ${PATH_TO_GENCTL_CI}/scripts/pipeline_builder/build_functional_tests.py
      fi
      mv test_executions.json ${WS_PATH}/test_executions.json

      pushd ${WS_PATH}
      echo test output:
      cat ${OUTPUT}

      declare -i test_idx=1
      declare -i temp_counter=1

      # Create the temp directory where the tests that run in parallel will store the results
      rm -rf ${ROOT_DIR}/test_results
      mkdir ${ROOT_DIR}/test_results
      num_test_suites=0
      echo $functional_test > ${WS_PATH}/hack/ci/functional_tests.yaml
      rpt=$(yq -r '.run_tests_in_parallel | select(. != null)' ${WS_PATH}/hack/ci/functional_tests.yaml)

      # check if tests need to be run in parallel, declare the variables used to store the data on parallel runs
      run_parallel_tests="true"
      if [[ "$rpt" == "false" ]]; then
        echo "functional_test[run_tests_in_parallel] is set false"
        run_parallel_tests=false
      fi
      echo $run_parallel_tests
      declare -A parallel_pids
      declare -A test_names
      declare -A test_rollup

      # loop through global test config and user defined tests generated by build_functional_tests.py
      for test_execution in $(cat ${OUTPUT} | jq -c '.[]'); do
        path=$(echo ${test_execution} | jq -r '.path')
        echo Running tests ${path}
        meta_purposes=$(echo ${test_execution} | jq -r '.meta_purposes')
        echo tests meta_purposes ${meta_purposes}
        testplan=$(echo ${test_execution} | jq -r '.test_plan')
        echo tests testplan ${testplan}
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
        api_key_alias_override=$(echo ${test_execution} | jq -r '.api_key_alias')
        echo tests api_key_alias_override ${api_key_alias_override}
        processes=$(echo ${test_execution} | jq -r '.processes')
        echo tests processes count ${processes}
        skip_test=$(echo ${test_execution} | jq -r '.skip_test')
        echo skipping test run: ${skip_test}
        promotion_test_path=$(dirname $PWD)
        if [[ ${skip_test} == "true" ]]; then
          test_idx=$test_idx+1
          echo $PWD
          echo -e "$testplan $path ${FEATURE_FLAG}:${FEATURE_VERSION}" >> ${promotion_test_path}/skipped_duplicate_tests
          cat ${promotion_test_path}/skipped_duplicate_tests
          continue          
        fi
        echo -e "$testplan $path ${FEATURE_FLAG}:${FEATURE_VERSION}" >> ${promotion_test_path}/executed_tests
        cat ${promotion_test_path}/executed_tests
  
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
        export TIMESTAMP=$(date +"%Y%m%d-%H-%M-%S")
        test_run="RIAS_${MZONE_NAME}_${TIMESTAMP}"

        # generate a test_plan flags string from testplan
        test_plan=${test_type}
        if [ "${testplan}" != "" ]; then
            test_plan=${testplan}
            test_run="${testplan}_${MZONE_NAME}_${TIMESTAMP}"
        fi

        echo  test_plan: ${test_plan}

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
            if [ "${meta_flags}" != "" ]; then
              meta_flags="${meta_flags},"
            fi
            if [ "${meta_features_flags}" != "" ]; then
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
            get_cluster_public_ip ${cluster_name}
            echo use overriden cluster ${iks_cluster_name_override} and public ip: ${PUBLIC_IP}
        elif [ -n "${IBMCLOUD_IKS_CLUSTER_NAME}" ]; then
            get_cluster_public_ip ${IBMCLOUD_IKS_CLUSTER_NAME}
            echo use cluster ${IBMCLOUD_IKS_CLUSTER_NAME} public ip: ${PUBLIC_IP}
        elif [ -n "${RIAS_URL}" ]; then
            get_cluster_public_ip ${RIAS_URL}
            echo use rias_url ${RIAS_URL} public ip: ${PUBLIC_IP}
        fi


        jira_flags=""
        if [ "${jira_project_override}" != "[]" ]; then
          jira_flags="--abf-enable --jira-project ${jira_project_override} --jira-label cd-blocker,${FEATURE_FLAG} --jira-assignee Automatic"
          echo "use jira project override ${jira_project_override}"
        elif [[ ! -z "${JIRA_PROJECT}" ]]; then
          jira_flags="--abf-enable --jira-project ${JIRA_PROJECT} --jira-label cd-blocker,${FEATURE_FLAG} --jira-assignee Automatic"
          echo "use jira project ${JIRA_PROJECT}"
        fi

        if [[ ${NO_JIRA_FLAGS_FOR_CD_TEST} == "true" ]]; then
          echo "Ignore Jira flags for testing set. Clearing jira_flags"
          jira_flags=""
        fi

        pr_flags=""
        if [ -z "${PROMOTION_PR_NUMBER}" ];then
          echo "PROMOTION_PR_NUMBER not found, skipping --repository and --report-pr parameters"
        else
          pr_flags="--org ${PR_ORG} --repository ${WORKSPACE_NAME} --report-pr ${PROMOTION_PR_NUMBER}"
          echo "use pr_flags ${pr_flags}"
        fi

        api_key_alias=${APIKEY_ALIAS}
        if [ "${api_key_alias_override}" != "[]" ]; then
          api_key_alias="${api_key_alias_override}"
          echo "use api key alias override ${api_key_alias_override}"
        fi

        # If the test config's processes is equal to the global default of 4 defined here:
        # https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/scripts/pipeline_builder/build_functional_tests.py#L32
        # then override to 16 specifically for promotion runs. Otherwise any value other than 4
        # that is set in a test config will take precedence.
        if [ $processes -eq 4 ]; then
          processes=16
        fi

        if [[ ( "$USE_SINGLE_PROMOTION_PIPELINE" != "true" ) ||
              ( "$USE_SINGLE_PROMOTION_PIPELINE" == "true" && "$SPP_FEATURE_FLAG" == "$FEATURE_FLAG" ) ]]; then
          # If we're executing promotion tests then we're aggregating any errors from any test suites, before allowing
          # pipeline to terminate. Disable immediate pipeline termination in the event of a test suite failure.
          set +e

          #run tests
          if [[ ${run_parallel_tests} == "true" ]]; then
            echo "Running tests in parallel"
            result_file_name=$(echo $path | sed 's/\//_/g' )
            docker run --name=smotainer_$(date -u +%s)_${test_idx} \
                --net=host \
                -v ${KEYS_DIR}:/root/.ssh \
                -v ${OUTPUT_DIR}:/output \
                -e SECRET_MANAGER_KEY="${SECRET_MANAGER_KEY_CSI}" \
                ${ws_volume_mount} \
                ${ARTIFACTORY_DOCKER_PROD_URL}/${SMOTAINER_IMAGE_PATH}:${SMOTAINER_IMAGE_TAG} \
                python3 QA/lib/framework/cpap/launcher.py \
                    -v \
                    --tc=public_ip:${PUBLIC_IP} \
                    --tc=port:443 \
                    --tc=vault_certs:/vaultcerts/vault-td-smotainer-cert.crt \
                    --tc=secure:True --tc=apikey:${api_key_alias} \
                    -N ${processes} \
                    --out-dir=/output \
                    -S ${path} \
                    --report-rules-eng \
                    --group-set=${MZONE_NAME} \
                    --test-plan=${test_plan} \
                    --save-artifacts \
                    --test-run=${test_run} \
                    ${meta_tag} \
                    ${cmd_flags} \
                    ${cmdraw_flags} \
                    ${features_flags} \
                    ${jira_flags} \
                    ${pr_flags} > ${ROOT_DIR}/test_results/$result_file_name &
            test_pid=$!
            parallel_pids[$test_pid]=1
            test_names[$test_pid]=$path
            test_rollup[$test_pid]="$test_idx  $testplan"
            echo "${!parallel_pids[*]}"
            echo "${!test_names[*]}"
            echo "${!test_rollup[*]}"
            #bump the index here for parallel testing
            test_idx=$test_idx+1
            temp_counter=$temp_counter+1

            num_test_suites=$num_test_suites+1
            ls ${ROOT_DIR}/test_results/
          else
            docker run --name=smotainer_$(date -u +%s) \
                --net=host \
                -v ${KEYS_DIR}:/root/.ssh \
                -v ${OUTPUT_DIR}:/output \
                -e SECRET_MANAGER_KEY="${SECRET_MANAGER_KEY_CSI}" \
                ${ws_volume_mount} \
                ${ARTIFACTORY_DOCKER_PROD_URL}/${SMOTAINER_IMAGE_PATH}:${SMOTAINER_IMAGE_TAG} \
                python3 QA/lib/framework/cpap/launcher.py \
                    -v \
                    --tc=public_ip:${PUBLIC_IP} \
                    --tc=port:443 \
                    --tc=vault_certs:/vaultcerts/vault-td-smotainer-cert.crt \
                    --tc=secure:True --tc=apikey:${api_key_alias} \
                    -N ${processes} \
                    --out-dir=/output \
                    -S ${path} \
                    --report-rules-eng \
                    --group-set=${MZONE_NAME} \
                    --test-plan=${test_plan} \
                    --save-artifacts \
                    --test-run=${test_run} \
                    ${meta_tag} \
                    ${cmd_flags} \
                    ${cmdraw_flags} \
                    ${features_flags} \
                    ${jira_flags} \
                    ${pr_flags}
            test_results=$?
            # If a test suite failed, then add it to failed_tests.
            if [[ ${test_results} -ne 0 ]]; then
                if [[ "${log_ff_name_failed}" == "false" ]]; then
                  failed_tests+="\n\n$(echo ${FEATURE_FLAG}:)"
                  log_ff_name_failed=true
                fi

                failed_tests+="\n$(echo \* $test_idx $testplan)"
            else
                if [[ "${log_ff_name_passed}" == "false" ]]; then
                  passed_tests+="\n\n$(echo ${FEATURE_FLAG}:)"
                  log_ff_name_passed=true
                fi

                passed_tests+="\n$(echo \* $test_idx $testplan)"
            fi
            #for serialized testing, bump the index here.
            test_idx=$test_idx+1
            temp_counter=$temp_counter+1
            # Re-enable immediate pipeline termination upon error.
            set -e
          fi
        else
          echo "skipping FeatureFlag ${FEATURE_FLAG} TestPlan ${test_plan} index ${test_idx}"
        fi

        # check if greater than 8 tests are running at once and wait for them to complete before moving to next
        if [[ $temp_counter -gt 8 ]]; then 
          wait_for_tests
          #Reset counter back to 1 after waiting for 8 tests
          temp_counter=1
          echo "Temp test counter reset to 1 after waiting for 8 tests"
        fi
      done
      wait_for_tests
      # Re-enable immediate pipeline termination upon error.
      set -e

      # back to build root directory
      popd
    else
      echo "hack/ci/pipeline.yaml does not exist. Exiting ..."
      exit 1
    fi
  fi
done

# Read and store the second column of each line of skipped_duplicate_tests file 
# grep with executed_tests file 
#if matches store first and third column of skipped_duplicate_tests & third column of executed_tests 
#in a variable skipped_duplicate_test_names and post it as a result in PR

if [ -s "${promotion_test_path}/skipped_duplicate_tests" ]; then
    while IFS= read -r line; do
        skipped_col=$(echo "$line" | awk '{print $2}')
        executed_col=$(cat "${promotion_test_path}/executed_tests" | grep "$skipped_col" | awk '{print $2}')

        if [ "$executed_col" = "$skipped_col" ]; then
            skipped_lines=$(echo "$line" | awk '{print $1,$3}')
            executed_lines=$(cat "${promotion_test_path}/executed_tests" | grep "$skipped_col" | awk '{print $3}')
            skipped_duplicate_test_names+="\n$(echo \* " $skipped_lines  test is skipped due to test $executed_lines")"
        fi
    done < "${promotion_test_path}/skipped_duplicate_tests"

    # Print the accumulated skipped_duplicate_test_names
    echo -e "$skipped_duplicate_test_names"
else
    echo "The file skipped_duplicate_tests is empty or does not exist."
fi


# if there is any duplicate test which is skipped , post it to PR
echo "skipped_duplicate_test_names"
set +x
if [[ -n "${skipped_duplicate_test_names}" ]]; then
    echo -e "${skipped_duplicate_test_names}"
    curl \
    -s \
    -X POST \
    -H "Authorization: Bearer ${GHE_API_TOKEN}" \
    -d "{\"body\":\"Skipped duplicate tests:\n ${skipped_duplicate_test_names}\"}" \
    ${base_url}/api/v3/repos/${org_repo}/issues/${pr_number}/comments \
    > /dev/null
fi
set -x
# roll up test status for a PR comment

echo -e "Passed Tests: ${passed_tests}"
echo -e "Failed Tests: ${failed_tests}"


if [ -n "${passed_tests}" ] || [ -n "${failed_tests}" ]; then
set +x
curl \
  -s \
  -X POST \
  -H "Authorization: Bearer ${GHE_API_TOKEN}" \
  -d "{\"body\":\"Passed Tests: \n ${passed_tests} \n\n Failed Tests: \n ${failed_tests}\"}" \
  ${base_url}/api/v3/repos/${org_repo}/issues/${pr_number}/comments \
  > /dev/null
set -x

else
  echo -e "Both passed_tests and failed_tests are empty."
fi  


if [[ -n ${failed_tests} ]]; then
  exit 1
fi
