#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI, ONE_PIPELINE_CI_IBM_CLOUD_API_KEY, SKIP_CI_FAILURE_ANALYSIS

export SKIP_CI_FAILURE_ANALYSIS=${SKIP_CI_FAILURE_ANALYSIS:-false}

if [[ $SKIP_CI_FAILURE_ANALYSIS = true ]]; then
    echo "CI failure analysis is disabled. Skipping log analysis step."
else
    # Run the entire analysis in a subshell with error handling disabled so that
    # any failure (missing variable, unavailable service, etc.) is caught and
    # logged without breaking the pipeline.
    (
        set +e
        trap 'echo "WARNING: CI failure analysis encountered an error. Skipping remaining analysis steps."; exit 0' ERR

        echo "CI failure analysis enabled. Starting the CI failure log analysis..."
        source ${PATH_TO_GENCTL_CI}/scripts/log_analysis/log_utils.sh || { echo "WARNING: Failed to source log_utils.sh. Skipping CI failure analysis."; exit 0; }

        TMP_DIR="${CI_TEMP_DIR}/log_analyse"
        mkdir -p "${TMP_DIR}"

        pushd "${TMP_DIR}"

        # Download the current running pipeline logs
        download_pipeline_logs

        # Generate single file with all pipeline failures
        ${PATH_TO_GENCTL_CI}/scripts/log_analysis/generate_pipeline_logs.sh pipeline_logs

        # Color codes
        BOLD="\033[1m"
        CYAN="\033[1;36m"
        YELLOW="\033[1;33m"
        GREEN="\033[1;32m"
        RESET="\033[0m"

        if [ -f "failed-logs.txt" ]; then
            echo "Found the failed-logs.txt file. Redacting the apikeys if found any"
            # Redacting the apikeys if any
            sed -i -E 's/(token|password|apikey)=\S+/REDACTED/g' failed-logs.txt

            # Set Bob credentials
            export BOBSHELL_API_KEY=$(get_secret onepipelineci-bob-apikey)
            export BOBSHELL_BASE_URL="https://prod.ibm-bob-staging.cloud.ibm.com"

            BOB_OUTPUT=$(cat ${PATH_TO_GENCTL_CI}/scripts/log_analysis/prompt.txt | bob --accept-license --auth-method api-key --chat-mode advanced | sed -n '/---output---/,/---output---/p' | sed '1d;$d')

            echo ""
            echo -e "${CYAN}========================================${RESET}"
            echo -e "${BOLD}${CYAN}        CI Failure Analysis Report${RESET}"
            echo -e "${CYAN}========================================${RESET}"
            echo -e "${YELLOW}${BOB_OUTPUT}${RESET}"
            echo -e "${GREEN}========================================${RESET}"
            echo -e "${BOLD}${GREEN}           End of Analysis${RESET}"
            echo -e "${GREEN}========================================${RESET}"
            echo ""
        else
            echo -e "${GREEN}No failures detected. Skipping Bob analysis.${RESET}"
        fi
        popd
    ) || true
fi
