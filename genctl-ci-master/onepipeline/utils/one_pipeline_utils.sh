#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================


# This script does 2 main things

# 1. Declare a series of useful functions related to one-pipeline
# 2. Export some useful variables that rely in the way we use one-pipeline

function set_ghe_commit_status() {
    # Generic function to set/update the commit status

    # This meant to be used in the context of a One-Pipeline pipeline execution

    # It assumes that the status will be for the current "app repo" and commit of the pipeline execution
    # It also assumes that the link of the check should take us to the task and step of the pipeline execution

    # Expected parameters:
    STATE=$1      #status - success,failure,pending
    DESCRIPTION=$2  #description of the CI check
    CONTEXT=$3 # The actual "string" of the check that we see in GitHub UI

    set-commit-status \
        --repository "$(load_repo app-repo url)" \
        --commit-sha "$(load_repo app-repo commit)" \
        --state "${STATE}" \
        --description "${DESCRIPTION}" \
        --context "${CONTEXT}" \
        --task-name "${TASK_NAME}" \
        --step-name "${STEP_NAME}"
}

function clone_repos_from_env_vars() {
    # This function is used in order to clone repositories
    # It relies on the standard naming convention used in pipeline-params

    # XXX-repo-name: somename
    # XXX-org-name: someorg
    # xxx-branch: somebranch

    # Some examples:

    #storage-service-workspace-repo-name: storage-service-workspace
    #storage-service-workspace-org-name: genctl
    #storage-service-workspace-branch: master

    #storage-workspace-repo-name: storage-workspace
    #storage-workspace-org-name: genctl
    #storage-workspace-branch: master

    #genctl-vetted-versions-repo-name: vetted-versions
    #genctl-vetted-versions-org-name: genctl-cicd
    #genctl-vetted-versions-branch-name: master

    # This function uses some one-pipeline env vars, therefore should be used only in one-pipeline

    # It assumes that the pipeline-params file was already converted to env vars and sourced,
    # Therefore, we have environment variables in the form of:

    # PLATFORM_INVENTORY_ORG_NAME=platform-inventory
    # PLATFORM_INVENTORY_REPO_NAME=cloudlab
    # PLATFORM_INVENTORY_BRANCH=master

    # It receives as a parameter both a base directory where to perform all the clones and a list of "repositories"
    # For each of the repositories, it performs clone

    # Expected parameters:
    BASE_URL=$1
    BASE_DIR=$2
    REPOS_LIST=$3

    # We are improvising logic of grep to fetch the repo name, org name and Branch. Rathar than grepping it twice we are
    # performing it in single action and the change is that now are greping the key as a whole.

    for REPO in ${REPOS_LIST}
    do
        REPO_NAME=$(env | grep "^${REPO}_REPO_NAME" | cut -d '=' -f 2)
        REPO_ORG=$(env | grep "^${REPO}_ORG_NAME" | cut -d '=' -f 2)
        REPO_BRANCH=$(env | grep "^${REPO}_BRANCH" | cut -d '=' -f 2)

        echo "Will try to clone: ${BASE_URL}/${REPO_ORG}/${REPO_NAME} ..."

        # Check if there is not already an existing directory
        # (For example from repositories that are "cloned" by OnePipeline as they are GitHub integrations of the toolchain)
        if [ ! -d "${BASE_DIR}/${REPO_NAME}" ]; then
            . "${ONE_PIPELINE_PATH}"/git/clone_repo "${BASE_URL}/${REPO_ORG}/${REPO_NAME}" \
            "${REPO_BRANCH}" "${BASE_DIR}/${REPO_NAME}"
        else
            echo "${BASE_DIR}/${REPO_NAME} already exists; skip cloning"
        fi
    done
}

function export_pr_info() {
    # This function is used in order to export some information of the PR
    # It should do equivalent work to export-pipe-data being used in Concourse pipelines

    # The way it works is by creating (Or sourcing an existing) .sh file that contain exports commands

    # Note: Before we call this function, we need to be in the TEMP CI DIR

    PR_INFO_FILE_NAME="pr_info.sh"

    # Check if file exists, if it does not, create it
    if [ -f "${PR_INFO_FILE_NAME}" ];
    then
        echo "PR info file exists ..."
    else
        echo "PR info file not found, proceeding to create one..."

        # Here we check if we have something in PR_URL, if not we assume is because we are in a subpipeline
        if [[ -z "${PR_URL}" ]]
        then
            # Since we are in a subpipeline we bring the values in some other way
            {
                echo "export PR_URL=\"$(get_env pr_url)\""
                echo "export PR_HEADSHA=\"$(load_repo app-repo commit)\""
                echo "export PR_BRANCH=\"$(get_env pr_branch)\""
                echo "export PR_BASEBRANCH=\"$(get_env pr_basebranch)\""
                echo "export PR_ID=\"$(get_env pr_id)\""
            } >> "${PR_INFO_FILE_NAME}"
        else
            {
                echo "export PR_URL=\"${PR_URL}\""
                echo "export PR_HEADSHA=\"$(load_repo app-repo commit)\""
                echo "export PR_BRANCH=\"${HEAD_BRANCH}\""
                echo "export PR_BASEBRANCH=\"${BASE_BRANCH}\""
                echo "export PR_ID=\"$(get_env "PR_URL" | grep -o '[^/]*$')\""

                TRIGGER_PAYLOAD_PATH=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "$PR_URL" | jq )
                echo "export PR_BASESHA=\"$(echo ${TRIGGER_PAYLOAD_PATH} | jq -r '.base.sha')\""
                echo "export PR_USERLOGIN=\"$(echo ${TRIGGER_PAYLOAD_PATH} | jq -r '.user.login')\""
                echo "export PR_TITLE=\"$(echo ${TRIGGER_PAYLOAD_PATH} | jq -r '.title')\""
                echo "export PR_HTML_URL=\"$(echo ${TRIGGER_PAYLOAD_PATH} | jq -r '.html_url')\""
                echo "export PR_DRAFT=\"$(echo ${TRIGGER_PAYLOAD_PATH} | jq -r '.draft')\""
                # echo "export PR_BODY=\"$(echo ${TRIGGER_PAYLOAD} | jq -r '.pull_request.body')\"" --> Check if needed ?

                echo "export PR_LABELS=\"$(echo ${TRIGGER_PAYLOAD_PATH} | jq -r '.labels[].name')\""
            
            } >> "${PR_INFO_FILE_NAME}"
        fi

    fi
    # Show file
    cat "${PR_INFO_FILE_NAME}"

    # Source it
    source "${PR_INFO_FILE_NAME}"
}

function prepare_pipeline_environment() {
    # This function "prepares" the environment for the pipeline by sourcing the files defined for that purpose

    # Expected parameters:
    BASE_PATH=$1 # The path to the directory where the "pipeline environment" files sit

    if [ -d ${BASE_PATH} ]
    then
        # First move to the directory
        pushd ${BASE_PATH}

        echo "Will list content of ${BASE_PATH}"
        ls -la

        ENVIRONMENT_FILES="secrets vars aliases"

        # Loop over the different types of "environment files" we support
        for env_file in ${ENVIRONMENT_FILES}
        do
            # Set on a variable the name of the file
            FILE_TO_CHECK="${PWD}/${env_file}.sh"

            echo "Will try to source ${FILE_TO_CHECK}"

            if [ -f ${FILE_TO_CHECK} ]
            then
                echo "Will source ${FILE_TO_CHECK}"
                source ${FILE_TO_CHECK}
            else
                echo "Could not find ${env_file} file ..."
            fi
        done

        # Come back
        popd
    else
        echo "WARNING: Could not find directory ${BASE_PATH}"
    fi
}

function set_env_for_subpipeline() {
    # This function performs few set_env commands to put some useful information of the parent pipeline
    # This information is consumed by the subpipeline

    set_env ci_parent_pipeline_build_number "${BUILD_NUMBER}"
    export_env "ci_parent_pipeline_build_number"
    set_env ci_parent_pipeline_run_id "${PIPELINE_RUN_ID}"
    export_env "ci_parent_pipeline_run_id"
    set_env pr_branch "${PR_BRANCH}"
    export_env "pr_branch"
    set_env pr_basebranch "${PR_BASEBRANCH}"
    export_env "pr_basebranch"
    set_env pr_id "${PR_ID}"
    export_env "pr_id"
    set_env pr_url "${PR_URL}"
    export_env "pr_url"
    set_env app_repo_name "${APP_REPO_NAME}"
    export_env "app_repo_name"
    set_env app_repo_org "${APP_REPO_ORG}"
    export_env "app_repo_org"
    # print the public key for all consumers. each consumer should have the ability to manually verify the signature that CI signed
    set_env print-code-signing-public-key "1"
    export_env "print-code-signing-public-key"
    set_env print-code-signing-certificate "1"
    export_env "print-code-signing-certificate"

    # If we have CLAIM_MZONE_RESULT set in case is needed to be used by a subpipeline
    if [[ ! -z "${CLAIM_MZONE_RESULT}" ]]
    then
        set_env ci_parent_pipeline_claimed_mzone "${CLAIM_MZONE_RESULT}"
        export_env "ci_parent_pipeline_claimed_mzone"
    fi
    if [[ ! -z "${LOCK_CLAIMED_MSG}" ]]
    then
        set_env ci_parent_pipeline_lock_claimed_msg "${LOCK_CLAIMED_MSG}"
        export_env "ci_parent_pipeline_lock_claimed_msg"
    fi
    if [[ ! -z "${MULTIPLE_LOCKS_COMMIT_MSG}" ]]
    then
        set_env ci_parent_pipeline_multiple_locks_commit_msg "${MULTIPLE_LOCKS_COMMIT_MSG}"
        export_env "ci_parent_pipeline_multiple_locks_commit_msg"
    fi    
}

function get_parent_pipeline_info() {
    # This function performs few get_env commands to get some useful information of the parent pipeline

    export PARENT_PIPELINE_BUILD_NUMBER=$(get_env ci_parent_pipeline_build_number )
    export PARENT_PIPELINE_RUN_ID=$(get_env ci_parent_pipeline_run_id)
    export PR_BRANCH=$(get_env pr_branch)
    export PR_BASEBRANCH=$(get_env pr_basebranch)
    export PR_ID=$(get_env pr_id)
    export PR_URL=$(get_env pr_url)
    export APP_REPO_NAME=$(get_env app_repo_name)
    export APP_REPO_ORG=$(get_env app_repo_org)

}

function collect_evidence(){
    # This function is used to update evidence repo
    # Expected parameters:
    TOOL_TYPE=$1      #The ID of the tool that provides evidence data. For example: "owasp-zap-ui", "cra"
    STATUS=$2  #The evidence status and can be one of the following: success, pending, failure
    EVIDENCE_TYPE=$3 # The ID of the evidence type. For example: com.ibm.image_vulnerability_scan, com.ibm.unit_tests
    ASSET_TYPE=$4 # The asset type from pipelinectl and can be one of the following types: repo, artifact
    ASSET_KEY=$5 # The key in pipelinectl assets. For the following commands load_artifact <key> or load_repo <key>

    collect-evidence \
      --tool-type "${TOOL_TYPE}" \
      --status "${STATUS}" \
      --evidence-type "${EVIDENCE_TYPE}" \
      --asset-type "${ASSET_TYPE}" \
      --asset-key "${ASSET_KEY}"
}

function get_pipeline_type(){
    BNTP=$1 # Branch name to process
    IPT=$2  # Initial pipeline type (Ex: pr,merge)
    RBTC=$3  # Repo branch to compare

    if [[ "${BNTP}" == "${RBTC}" ]]
    then
        export PIPELINE_TYPE="${IPT}"
    else
        if [[ $BNTP == *"release"* ]]
        then
            # If the branch has the word release we assume is in the format of hostOS in which
            # The repo names are like hostos-base-net-sw-release
            # The branches names are like release-5, release-5
            # In hostos, the branches have names like release-5, release-6
            # The entries in pipeline-overrides are in the format of hostos-base-net-sw-release-6-merge

            # This will extract only the number
            BRANCH_NUMBER=${BNTP#"release-"}

            # Define type of pipeline (Used to search overrides)
            # In hostOS, the repo names are like: hostos-base-net-sw-release
            # In the pipeline overrides we have entries like hostos-base-net-sw-release-6-merge
            # Therefore we need in PIPELINE_TYPE to have 6-merge

            export PIPELINE_TYPE="${BRANCH_NUMBER}-${IPT}"
        elif [[ $BNTP == *"stable"* ]]
        then
            # If the branch has the word stable we assume is in the format of SDN in which
            # The branches names are like stable-1.6, stable-1.5
            # The entries in pipeline overrides are in the format of fabcon-stable-1_6-merge (dots are replaced by underscore)
            # Therefore we need in PIPELINE_TYPE to have stable-1_6-merge

            # This will extract only the number
            #BRANCH_NUMBER=${BNTP#"stable-"}

            # Replace dots with underscore
            # Result should be from stable-1.6 to stable-1_6
            REPLACED_BRANCH_NUMBER=$(echo "$BNTP" | tr . _)

            export PIPELINE_TYPE="${REPLACED_BRANCH_NUMBER}-${IPT}"
        else
            export PIPELINE_TYPE="${BNTP}-${IPT}"
        fi
    fi

    echo "Pipeline type is ${PIPELINE_TYPE}"
}

function print_divider(){
  # This function prints a log divider for clarity
  echo
  for i in {1..150}; do echo -n "#"; done
  echo
}

# First thing we do is we validate important YAML files (We source in order to exit 1 if failure)
source ${PATH_TO_GENCTL_CI}/scripts/validate_cicd_yaml_files.sh

# This is the IBM cloud api key used for the pipelines
export ONE_PIPELINE_CI_IBM_CLOUD_API_KEY=$(get_secret ibmcloud-api-key)

# Required for succesfully cloning and also in some scripts
# We need this to succesfully clone repos
export GIT_TOKEN_PATH="${WORKSPACE}/git-token"
export GH_TOKEN=$(cat ${GIT_TOKEN_PATH})

# Vars
export IBM_HTTPS_BASE_URL="https://github.ibm.com"
export CHECKS_PREFIX="tekton-vpc-ci"
export ONEPIPELINE_CHECKS_PREFIX="tekton"

export PIPELINE_REPO_NAME=$(load_repo app-repo path)
export PATH_TO_WORKSPACE_REPO="${WORKSPACE}/${PIPELINE_REPO_NAME}"

export PIPELINE_REPO_ORG=$(get_env repo_org)
export ORG_AND_REPO="${PIPELINE_REPO_ORG}/${PIPELINE_REPO_NAME}"
export REPO_MAIN_BRANCH=$(get_env repo_branch)

export PIPELINE_RUN_BRANCH=$(cd ${PATH_TO_WORKSPACE_REPO}; git rev-parse --abbrev-ref HEAD)

# If it does not exist, create a directory used for CI purposes
export CI_TEMP_DIR="${PWD}/CI_TEMP_DIR"
mkdir -p "${CI_TEMP_DIR}"

# Before we deal with the environment of the specific pipeline we check if is PR pipeline and if yes, export some info
export PIPELINE_NAMESPACE=$(get_env pipeline_namespace)

# Check if we are in a PR pipeline, if yes, export PR information
if [[ ${PIPELINE_NAMESPACE} == "pr" ]]; then
    echo "We are on a PR pipeline, will proceed to extract some PR Info..."

    # Move to temp CI dir
    pushd ${CI_TEMP_DIR}

    # Create and/or source existing PR info file
    export_pr_info

    # Come back
    popd
fi

# Create the directory used to hold the artifacts that need to be uploaded
export CI_ARTIFACTS_TO_UPLOAD_DIR="${CI_TEMP_DIR}/CI_ART_TO_UPLOAD"
mkdir -p "${CI_ARTIFACTS_TO_UPLOAD_DIR}"

# Create the directory used to hold the artifacts that need to be downloaded
export CI_ARTIFACTS_TO_DOWNLOAD_DIR="${CI_TEMP_DIR}/CI_ARTIFACTS_TO_DOWNLOAD_DIR"
mkdir -p "${CI_ARTIFACTS_TO_DOWNLOAD_DIR}"

# Create the directory used to hold protected files
export CI_PROTECTED_FILES_DIR="${CI_TEMP_DIR}/CI_PROTECTED_FILES_DIR"
mkdir -p "${CI_PROTECTED_FILES_DIR}"

# Handling non standard naming artifacts
export CI_NON_STANDARD_NAMING_ARTIFACTS_DIR="${CI_TEMP_DIR}/CI_NON_STANDARD_NAMING_ARTIFACTS_DIR"

# Images
export CI_NON_STANDARD_NAMING_IMAGES_DIR="${CI_NON_STANDARD_NAMING_ARTIFACTS_DIR}/IMAGES"
mkdir -p "${CI_NON_STANDARD_NAMING_IMAGES_DIR}"

export IS_ONE_PIPELINE_RUN="true"

check_yaml_path_has_data() {
    local yaml_path="$1"
    BUILD_META_YAML_FILE="hack/ci/build-meta.yaml"

    # Move to the workspace directory
    pushd "${PATH_TO_WORKSPACE_REPO}"

    [[ -z "$yaml_path" || ! -f "$BUILD_META_YAML_FILE" ]] && return 1

    IFS='.' read -ra parts <<< "$yaml_path"
    local path_array
    path_array=$(printf '"%s",' "${parts[@]}")
    path_array="[${path_array%,}]"

    local result
    result=$(yq -e -r "
      try getpath($path_array) catch null
      | if . == null or . == \"\" then false
        elif type == \"string\" then (gsub(\"\\\\s+\"; \"\") != \"\")
        elif type == \"array\" then
            map(select(. != null and . != \"\" and (type != \"string\" or (gsub(\"\\\\s+\"; \"\") != \"\")))) | length > 0
        elif type == \"object\" then
            to_entries | map(select(.value != null and .value != \"\")) | length > 0
        else false
        end
    " "$BUILD_META_YAML_FILE" 2>/dev/null)
    popd
    
    result=${result:-false}
    [[ "$result" == "true" ]] && return 0 || return 1
}

check_yaml_file_is_empty() {
    BUILD_META_YAML_FILE="hack/ci/build-meta.yaml"

    pushd "${PATH_TO_WORKSPACE_REPO}"

    if [[ ! -f "${BUILD_META_YAML_FILE}" ]]; then
        export BUILD_META_YAML_IS_EMPTY="true"
        popd 
        echo "BUILD_META_YAML_IS_EMPTY is set to: ${BUILD_META_YAML_IS_EMPTY}"
        return
    fi

    # Remove comments and blank lines; if nothing remains, treat as empty
    if [[ -z "$(grep -v '^[[:space:]]*#' "${BUILD_META_YAML_FILE}" | grep -v '^[[:space:]]*$')" ]]; then
        export BUILD_META_YAML_IS_EMPTY="true"
    else
        export BUILD_META_YAML_IS_EMPTY="false"
    fi

    popd
    echo "BUILD_META_YAML_IS_EMPTY is set to: ${BUILD_META_YAML_IS_EMPTY}"
}

has_non_s390x_packages_data() {        
    BUILD_META_YAML_FILE="hack/ci/build-meta.yaml"
    
    # Move to the workspace directory
    pushd "${PATH_TO_WORKSPACE_REPO}"

    [[ ! -f "$BUILD_META_YAML_FILE" ]] && return 1

     # Check if packages section exists
    if [[ "$(yq -r 'has("packages")' "$BUILD_META_YAML_FILE")" != "true" ]]; then        
        return 1
    fi

    local targets=("amd64" "arm64" "noarch")

    for type in debian rpm tar golang; do
        for arch in "${targets[@]}"; do
            path="packages.$type.$arch"
            if check_yaml_path_has_data "$path"; then                
                return 0
            fi
        done
    done

    #come back
    popd
    return 1
}

# --- function to decide whether to run job for s390x packages ---
has_s390x_packages_data() {
    BUILD_META_YAML_FILE="hack/ci/build-meta.yaml"

    # Move to the workspace directory
    pushd "${PATH_TO_WORKSPACE_REPO}"

    [[ ! -f "$BUILD_META_YAML_FILE" ]] && return 1

    # Check top-level packages section
    if [[ "$(yq -r 'has("packages")' "$BUILD_META_YAML_FILE")" != "true" ]]; then
        return 1
    fi

    # Check s390x under each known package type
    for type in debian rpm tar golang; do
        if check_yaml_path_has_data "packages.$type.s390x"; then
            echo "Found s390x data at packages.$type.s390x → run the job"
            return 0
        fi
    done
    #come back
    popd    
    return 1
}


get_and_export_secret() {
  local key="$1"
  local var_name="$2"
  local value

  if value=$(get_secret "$key" 2>/dev/null); then
    export "$var_name"="$value"
  fi
}

get_and_export_text() {
  local key="$1"
  local var_name="$2"
  local value

  if value=$(get_env "$key" 2>/dev/null); then
    export "$var_name"="$value"
  fi
}

# Helper to export multiple env variables defined in array
export_env_props() {
  # Get the last parameter as type, rest as array elements
  local type="${@: -1}"  # Last parameter is the type
  local env_props=("${@:1:$#-1}")  # All parameters except the last one

  # Check if array is empty
  if [ ${#env_props[@]} -eq 0 ]; then
    echo "No environment properties provided to export. Skipping."
    return
  fi

  for mapping in "${env_props[@]}"; do
    # Skip empty lines or comment lines
    [[ -z "$mapping" || "$mapping" =~ ^# ]] && continue
    
    # %%:* means: remove the longest match of :* from the end of the string.
    # Effectively, it keeps everything before the first colon.
    local var="${mapping%%:*}"
    
    # ##*: means: remove the longest match of *: from the beginning of the string.
    # Effectively, it keeps everything after the last colon.
    local key="${mapping##*:}"

    # Check that both variable and property are non-empty
    if [[ -z "$var" || -z "$key" ]]; then
      echo "Skipping invalid mapping: '$mapping' (missing variable or property)"
      continue
    fi
    # Export the variable if the property exists according to the type of the variable
    if [[ "$type" == "text" ]]; then
      get_and_export_text "$key" "$var"
    elif [[ "$type" == "secure" ]]; then
      get_and_export_secret "$key" "$var"
    fi
  done
}

detect_pr_phase() {
  local PULL_REQUEST_URL="$1"

  if [[ -z "${PULL_REQUEST_URL}" ]]; then
    echo "ERROR: PR_URL is required"
    return 1
  fi
  
  # Verify GH_TOKEN exists
  if [[ -z "${GH_TOKEN}" ]]; then
    echo "ERROR: GH_TOKEN is not set"
    return 1
  fi

  # gh Login with error checking
  if ! gh auth login --hostname github.ibm.com --with-token <<< ${GH_TOKEN}; then
    echo "ERROR: Failed to authenticate with GitHub"
    return 1
  fi

  # Verify authentication worked
  if ! gh auth status --hostname github.ibm.com >/dev/null 2>&1; then
    echo "ERROR: GitHub authentication verification failed"
    return 1
  fi
  
  # Parse PR URL
  local PR_NUMBER
  local REPO

  PR_NUMBER=$(echo "${PULL_REQUEST_URL}" | sed -E 's#.*/pulls/([0-9]+).*#\1#')
  REPO=$(echo "${PULL_REQUEST_URL}" | sed -E 's#.*/repos/([^/]+/[^/]+)/pulls/.*#\1#')

  if [[ -z "${PR_NUMBER}" || -z "${REPO}" ]]; then
    echo "ERROR: Invalid PR_URL: ${PULL_REQUEST_URL}"
    return 1
  fi
  
  # Fetch PR metadata
  local PR_JSON STATE

  PR_JSON=$(gh pr view "${PR_NUMBER}" --repo "${REPO}" \
    --json state)

  STATE=$(jq -r '.state' <<< "${PR_JSON}")  
  
  # Determine PR phase
  case "${STATE}" in
    OPEN)
      export PR_PHASE="pre-merge"
      ;;
    MERGED)
      export PR_PHASE="post-merge"
      ;;
    CLOSED)
      echo "PR is CLOSED (not merged). Exiting pipeline."
      export PR_PHASE="closed"
      ;;
    *)
      echo "Unknown PR state: ${STATE}"
      return 1
      ;;
  esac

  echo "PR_PHASE=${PR_PHASE} (state=${STATE})"
}
