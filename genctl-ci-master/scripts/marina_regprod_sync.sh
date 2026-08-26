#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
export SKIP_MARINA_REGPROD_SYNC=${SKIP_MARINA_REGPROD_SYNC:-"false"} # By default we DO want to make a sync request, therefore, skip = false
export MARINA_REGPROD_SYNC_SKIP_CHECK_IS_GENCTL_COMPONENT=${MARINA_REGPROD_SYNC_SKIP_CHECK_IS_GENCTL_COMPONENT:-"false"} # By default we DO want to check if is genctl component, therefore, skip = false
export MARINA_REGPROD_SYNC_DRY_RUN_MODE=${MARINA_REGPROD_SYNC_DRY_RUN_MODE:-"false"}

# Source one-pipeline utils
. ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source bash tools
. ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

function initGit {
  eval "$(ssh-agent -s)"
  ssh-add - <<< "${GIT_PRIVATE_KEY}"
  mkdir -p ~/.ssh
  ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
  git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
  git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"
}

function push_release_information_file(){
    MAX_ATTEMPTS=$1

    ATTEMPTS=0
    SLEEP_TIME=10

    while true
    do
        # If we reach the maximum number of attempts, exit 1
        if [[ ${ATTEMPTS} -eq ${MAX_ATTEMPTS} ]]
        then
            echo "After ${ATTEMPTS} attempts failed to push"
            break
        fi
        echo "Will make attempt ${ATTEMPTS} to push"

        echo "will try to push"
        git push origin HEAD:master

        if [[ $? -eq 0 ]]
        then
            # At this point the remote was updated, therefore we can safely assume that we have the lock
            # No other parallel process can acquire it until we release it
            echo "Marina/Reg-prof image file successfully committed"
            break
        fi
            echo "Between the local pipeline change and the remote update, something changed"

        # Update for next try
        git pull --rebase

        # Wait and increment the number of attempts
        sleep ${SLEEP_TIME}
        ATTEMPTS=$((ATTEMPTS+1))
    done
}

if [[ "${SKIP_MARINA_REGPROD_SYNC}" == "true" ]]; then
    echo "Skipping marina reg prod sync..."
else
    if repo_is_from_prod_org ${PATH_TO_WORKSPACE_REPO}
    then
        # Initially assume we won't perform the sync
        PERFORM_SYNC="false"

        if [[ "${MARINA_REGPROD_SYNC_SKIP_CHECK_IS_GENCTL_COMPONENT}" == "true" ]]
        then
            echo "It was explicitly required NOT to check if is genctl component"
            PERFORM_SYNC="true"
        else
            echo "check if the component ${PIPELINE_REPO_NAME} is part of genctl inventory"
            set +e
            python3 ${PATH_TO_GENCTL_CI}/scripts/exist_in_inventory_razee.py \
            ${PIPELINE_REPO_NAME} ${PATH_TO_GENESIS_DEPLOY_ARTIFACTS_REPO}/${RAZEE_DEFAULT_DEPLOYMENT_FILES_DIR}/${GENESIS_DEPLOY_ARTIFACTS_GENCTL_CLUSTER_REMOTE_RESOURCE}
            
            if [[ $? -eq 0 ]]
            then
                echo "component ${PIPELINE_REPO_NAME} is a part of genctl inventory..."
                PERFORM_SYNC="true"
            else
                echo "component ${PIPELINE_REPO_NAME} is NOT a part of genctl inventory..."
            fi
        fi
        
        if [[ "${PERFORM_SYNC}" == "true" ]]
        then
            echo "Will perform marina/reg-prod sync"

            initGit
            # Move to the repo
            pushd "${PATH_TO_WORKSPACE_REPO}"
            # Get the tags
            git fetch --tags
            export RESULT_REPO_SHA=$(git rev-parse HEAD)
            export RESULT_REPO_SEMVER=$(git describe --tags --exact-match --abbrev=0 2> /dev/null) || true
            echo RESULT_REPO_SHA: ${RESULT_REPO_SHA}
            echo RESULT_REPO_SEMVER: ${RESULT_REPO_SEMVER}
            popd

            # Get the SHA and SemVer of master
            echo PIPELINE_TYPE: ${PIPELINE_TYPE}
            echo PIPELINE_RUN_URL: ${PIPELINE_RUN_URL}
            echo PIPELINE_REPO_ORG: ${PIPELINE_REPO_ORG}
            MARINA_METADATA_FILE_NAME="${PIPELINE_REPO_ORG}_${PIPELINE_REPO_NAME}_${RESULT_REPO_SHA}.json"
            echo MARINA_METADATA_FILE_NAME: ${MARINA_METADATA_FILE_NAME}
            # Take a "shorter" version of the SHA
            SHORT_SHA=${RESULT_REPO_SHA:0:12}

            # Move to the PATH_TO_ONE_PIPELINE_MARINA_REG_PROD_SYNC_REPO
            pushd "${PATH_TO_ONE_PIPELINE_MARINA_REG_PROD_SYNC_REPO}"

            jq -n \
            --arg p_type "${PIPELINE_TYPE}" \
            --arg p_url "${PIPELINE_RUN_URL}" \
            --arg p_repo_org "${PIPELINE_REPO_ORG}" \
            --arg p_repo_name "${PIPELINE_REPO_NAME}" \
            --arg p_repo_sha "${RESULT_REPO_SHA}" \
            --arg p_repo_semver "${RESULT_REPO_SEMVER}" \
            '{
                pipeline_type: $p_type   ,
                pipeline_url: $p_url ,
                repo_org: $p_repo_org,
                repo_name: $p_repo_name    ,
                sha: $p_repo_sha    ,
                semver: $p_repo_semver
            }' > ${MARINA_METADATA_FILE_NAME}

            echo "Content of file:"
            cat ${MARINA_METADATA_FILE_NAME}
            
            if [[ "${MARINA_REGPROD_SYNC_DRY_RUN_MODE}" == "true" ]]
            then
                echo "We are in dry run mode !!!"
                echo "We won't actually add and push the file..."
            else
                git add ${MARINA_METADATA_FILE_NAME}
                git commit -m "Pipeline of: ${PIPELINE_TYPE} fore repository ${PIPELINE_REPO_ORG}/${PIPELINE_REPO_NAME} on commit with sha: ${SHORT_SHA}"
                #10 attempts to push new file
                push_release_information_file 10
                popd
            fi
        else
            echo "No need to perform marina/reg-prod sync"
        fi
    else
        echo "We don't commit marina/reg-prod sync requests for repositories that are not production"
        echo "PIPELINE_REPO_ORG is ${PIPELINE_REPO_ORG}, it might be the case you are running on a fork..."
    fi
fi
