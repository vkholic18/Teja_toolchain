#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI

# In addition the following variables are optional and if not have values they will take the default
set -x
SUB_PIPELINE_STAGE_NAME=${SUB_PIPELINE_STAGE_NAME:-"promotion-tests-as-subpipeline"}
SUB_PIPELINE_TRIGGER_TO_USE=${SUB_PIPELINE_TRIGGER_TO_USE:-"taas-worker-trigger"}

# this function will either build a list of tests that will run or run the promotion test suite
# based on the flag passed in 
# build_only=true - will compile a list of tests and log them to the PR
# build_only=false - will run the tests and return a list of passed and failed tests and log them to the PR
function build_and_run_promotion_tests () {
  build_only=$1

  # Promotion tests could take upto 24 hours to finish
  # Math is:
  # Up to 2880 attempts, sleeping 30 seconds between each attempt = 86400 seconds
  # 86400 seconds / (60*60) = 24 Hours
  export MAX_ATTEMPTS_BUSY_WAIT=2880
  export PROMOTION_OUTPUT="${WORKSPACE}/promotion"
  COMPONENTS_ORDERED_LIST_FILE="components-ordered-list"
  echo COMPONENTS_ORDERED_LIST_FILE location: ${PROMOTION_OUTPUT}/${COMPONENTS_ORDERED_LIST_FILE}
  if [ ! -f ${PROMOTION_OUTPUT}/${COMPONENTS_ORDERED_LIST_FILE} ]; then
    echo "COMPONENTS_ORDERED_LIST_FILE file not found!"
  else
      COMPONENTS_ORDERED_LIST=$(cat ${PROMOTION_OUTPUT}/${COMPONENTS_ORDERED_LIST_FILE})
      echo COMPONENTS_ORDERED_LIST: ${COMPONENTS_ORDERED_LIST}
  fi

  echo "Determine tests to Run"
  tests_to_run=""
  passed_tests=""
  failed_tests=""
  skipped_duplicate_test_names=""
  set +e
  for test_component in ${COMPONENTS_ORDERED_LIST[@]} ; do
    promote_workspace=${PROMOTION_OUTPUT}/${test_component}
    log_ff_name_passed=false
    log_ff_name_failed=false

    echo promote_workspace: ${promote_workspace}
    export WS_PATH=${promote_workspace}

    if [ -d "${promote_workspace}" ]; then
      # Check if there are functional tests defined in hack/ci/pipeline.yaml
      # If so we need to skip Smoke test from build_functional_tests.py
      # Check if pipeline.yaml file exists
      if [[ -f ${WS_PATH}/hack/ci/pipeline.yaml ]]; then
        FEATURE_FLAG=$(yq -r '.deployment.feature_flag | select(. != null)' ${WS_PATH}/hack/ci/pipeline.yaml)
        FEATURE_FLAG_VERSION=$(keyword="$FEATURE_FLAG" ; awk -v key="$keyword" '$1 ==key {print $2}' "${PROMOTION_OUTPUT}/components-ordered-list-version")
        
        # Extract mzone_name from pipeline.yaml for QZ2 worker selection
        MZONE_NAME=$(yq -r '.deployment.mzone_name | select(. != null)' ${WS_PATH}/hack/ci/pipeline.yaml)
        if [[ ! -z "$MZONE_NAME" ]]; then
          export MZONE_NAME
          echo "Extracted MZONE_NAME from pipeline.yaml: ${MZONE_NAME}"
        fi

        # skip rias_globals, genctl_globals, and rias_inception flags
        if [[ $FEATURE_FLAG != "rias_globals_version" ]] &&
          [[ $FEATURE_FLAG != "genctl_globals_version" ]] &&
          [[ $FEATURE_FLAG != "rias_inception_version" ]]; then
          tests_to_run+="$FEATURE_FLAG:$FEATURE_FLAG_VERSION\n"
        else
          echo "Skipping FeatureFlag ${FEATURE_FLAG}"
          break
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

          set_env USE_SINGLE_PROMOTION_PIPELINE "true"
          set_env SPP_FEATURE_FLAG "$FEATURE_FLAG"

          export_env "USE_SINGLE_PROMOTION_PIPELINE"
          export_env "SPP_FEATURE_FLAG"

          #if this is a build only call, don't excute the tests
          if [[ $build_only != true ]]; then
            ${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline.sh ${SUB_PIPELINE_STAGE_NAME} ${SUB_PIPELINE_TRIGGER_TO_USE}
            test_results=$?

            # If a test suite failed, then add it to failed_tests.
            if [[ ${test_results} -ne 0 ]]; then
              export SAVE_SUBPIPELINE_URL=$(get_env SAVE_SUBPIPELINE_URL)
              failed_tests+="\n\n$(echo ${FEATURE_FLAG} ${SAVE_SUBPIPELINE_URL})"
            else
              passed_tests+="\n\n$(echo ${FEATURE_FLAG})"
            fi
          fi
        fi
        tests_to_run+="\n"
      fi
    fi
  done
  set -e

  base_url="${IBM_HTTPS_BASE_URL}"
  org_repo="${APP_REPO_ORG}/${APP_REPO_NAME}"
  pr_number="${PR_ID}"

  if [[ $build_only == true ]]; then
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
    set -x
  else
    echo "Posting test Results to PR"

    echo -e "Passed Tests: ${passed_tests}"
    echo -e "Failed Tests: ${failed_tests}"

    set +x
    curl \
      -s --fail --show-error --retry 3 --retry-delay 10 -o /dev/null \
      -X POST \
      -H "Authorization: Bearer ${GHE_API_TOKEN}" \
      -d "{\"body\":\"Passed Tests: \n ${passed_tests} \n\n Failed Tests: \n ${failed_tests}\"}" \
      ${base_url}/api/v3/repos/${org_repo}/issues/${pr_number}/comments
    set -x

    if [[ -n ${failed_tests} ]]; then
      exit 1
    fi
  fi

}

export USE_ONE_SUBPIPELINE=$(get_env use_one_subpipeline)
echo "use_one_subpipeline ${USE_ONE_SUBPIPELINE}"

if [[ ${USE_ONE_SUBPIPELINE} == "true" ]]; then
  echo "Legacy subpipeline behavior enabled"
  ${PATH_TO_GENCTL_CI}/onepipeline/scripts/trigger_subpipeline.sh ${SUB_PIPELINE_STAGE_NAME} ${SUB_PIPELINE_TRIGGER_TO_USE}
else
  echo "using separate subpipelines for Promotion Tests"
  # build the list and post to the promotion PR
  build_and_run_promotion_tests true

  # execute the promotion tests
  build_and_run_promotion_tests false
fi
